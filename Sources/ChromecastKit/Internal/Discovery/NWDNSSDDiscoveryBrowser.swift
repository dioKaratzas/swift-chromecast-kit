//
//  ChromecastKit
//  Swift package for Google Cast (Chromecast).
//

@preconcurrency import Network
import Dispatch
import Foundation

/// Internal Bonjour/mDNS discovery backend built on `Network.NWBrowser`.
///
/// It browses `_googlecast._tcp`, extracts TXT metadata, then performs a lightweight
/// TCP connect to resolve the service endpoint to a host/port suitable for session setup.
actor NWDNSSDDiscoveryBrowser: CastDiscoveryBrowser {
    // MARK: State

    private let callbackQueue = DispatchQueue(label: "ChromecastKit.Discovery.NWBrowser")

    private var browser: NWBrowser?
    private var configuration = CastDiscovery.Configuration()
    private var eventContinuations = [UUID: AsyncStream<CastDiscoveryBrowserEvent>.Continuation]()
    private var resolutionTasks = [CastBonjourDiscoveryParser.ServiceIdentity: Task<Void, Never>]()
    private var discoveredDeviceIDsByService = [CastBonjourDiscoveryParser.ServiceIdentity: CastDeviceID]()

    // MARK: Browser Lifecycle

    func events() async -> AsyncStream<CastDiscoveryBrowserEvent> {
        let id = UUID()
        return AsyncStream { continuation in
            eventContinuations[id] = continuation
            continuation.onTermination = { [id] _ in
                Task { await self.removeContinuation(id: id) }
            }
        }
    }

    func start(configuration: CastDiscovery.Configuration) async throws {
        guard browser == nil else {
            return
        }

        self.configuration = configuration

        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = false

        let browser = NWBrowser(
            for: .bonjourWithTXTRecord(type: CastBonjourDiscoveryParser.serviceType, domain: nil),
            using: parameters
        )

        browser.stateUpdateHandler = { [self] state in
            Task { await self.handleBrowserState(state) }
        }

        browser.browseResultsChangedHandler = { [self] _, changes in
            Task { await self.handleResultChanges(changes) }
        }

        self.browser = browser
        browser.start(queue: callbackQueue)
    }

    func stop() async {
        browser?.cancel()
        browser = nil

        for task in resolutionTasks.values {
            task.cancel()
        }
        resolutionTasks.removeAll()
        discoveredDeviceIDsByService.removeAll()
    }

    // MARK: Browser Callbacks

    private func handleBrowserState(_ state: NWBrowser.State) {
        switch state {
        case .waiting:
            break
        case let .failed(error):
            emit(.error(.discoveryFailed(String(describing: error))))
        case .cancelled:
            break
        case .setup, .ready:
            break
        @unknown default:
            break
        }
    }

    private func handleResultChanges(_ changes: Set<NWBrowser.Result.Change>) {
        for change in changes {
            switch change {
            case .identical:
                continue
            case let .added(result):
                handleAddedOrChangedResult(result)
            case let .removed(result):
                handleRemovedResult(result)
            case let .changed(_, new, _):
                handleAddedOrChangedResult(new)
            @unknown default:
                continue
            }
        }
    }

    private func handleAddedOrChangedResult(_ result: NWBrowser.Result) {
        guard let service = CastBonjourDiscoveryParser.serviceIdentity(from: result.endpoint),
              service.type == CastBonjourDiscoveryParser.serviceType else {
            return
        }

        let txt = CastBonjourDiscoveryParser.txtDictionary(from: result.metadata)
        let includeGroups = configuration.includeGroups

        resolutionTasks[service]?.cancel()
        resolutionTasks[service] = Task {
            do {
                let resolvedEndpoint = try await Self.resolveEndpoint(for: result.endpoint)
                let descriptor = CastBonjourDiscoveryParser.deviceDescriptor(
                    serviceName: service.name,
                    resolvedEndpoint: resolvedEndpoint,
                    txt: txt
                )

                guard CastBonjourDiscoveryParser.shouldInclude(
                    descriptor,
                    includeGroups: includeGroups
                ) else {
                    self.removeKnownDeviceIfPresent(for: service)
                    return
                }

                self.finishResolvedDevice(descriptor, for: service)
            } catch is CancellationError {
                // Replaced or removed service while resolving.
            } catch {
                // Individual service resolution failures should not fail browsing entirely.
                self.clearResolutionTask(for: service)
            }
        }
    }

    private func handleRemovedResult(_ result: NWBrowser.Result) {
        guard let service = CastBonjourDiscoveryParser.serviceIdentity(from: result.endpoint) else {
            return
        }

        clearResolutionTask(for: service)
        if let deviceID = discoveredDeviceIDsByService.removeValue(forKey: service) {
            emit(.deviceRemoved(deviceID))
        }
    }

    private func finishResolvedDevice(
        _ descriptor: CastDeviceDescriptor,
        for service: CastBonjourDiscoveryParser.ServiceIdentity
    ) {
        clearResolutionTask(for: service)
        discoveredDeviceIDsByService[service] = descriptor.id
        emit(.deviceUpserted(descriptor))
    }

    private func removeKnownDeviceIfPresent(for service: CastBonjourDiscoveryParser.ServiceIdentity) {
        clearResolutionTask(for: service)
        guard let deviceID = discoveredDeviceIDsByService.removeValue(forKey: service) else {
            return
        }
        emit(.deviceRemoved(deviceID))
    }

    private func clearResolutionTask(for service: CastBonjourDiscoveryParser.ServiceIdentity) {
        resolutionTasks[service]?.cancel()
        resolutionTasks[service] = nil
    }

    private func emitBrowserError(_ error: any Error) {
        if let castError = error as? CastError {
            emit(.error(castError))
        } else {
            emit(.error(.discoveryFailed(String(describing: error))))
        }
    }

    private func emit(_ event: CastDiscoveryBrowserEvent) {
        for continuation in eventContinuations.values {
            continuation.yield(event)
        }
    }

    private func removeContinuation(id: UUID) {
        eventContinuations[id] = nil
    }

    // MARK: Endpoint Resolution

    private static func resolveEndpoint(for endpoint: NWEndpoint) async throws -> CastBonjourDiscoveryParser.ResolvedEndpoint {
        switch endpoint {
        case let .hostPort(host, port):
            return .init(host: hostString(host), port: Int(port.rawValue))
        case .service:
            break
        default:
            throw CastError.discoveryFailed("Unsupported Cast service endpoint: \(endpoint)")
        }

        return try await withThrowingTaskGroup(of: CastBonjourDiscoveryParser.ResolvedEndpoint.self) { group in
            group.addTask {
                try await resolveEndpointByConnecting(to: endpoint)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: 3_000_000_000)
                throw CastError.timeout(operation: "resolve cast bonjour service")
            }

            guard let resolved = try await group.next() else {
                throw CastError.discoveryFailed("No resolution result for Cast service endpoint")
            }
            group.cancelAll()
            return resolved
        }
    }

    private static func resolveEndpointByConnecting(to endpoint: NWEndpoint) async throws -> CastBonjourDiscoveryParser.ResolvedEndpoint {
        let connection = NWConnection(to: endpoint, using: .tcp)
        let queue = DispatchQueue(label: "ChromecastKit.Discovery.Resolve")
        let resolution = ConnectionResolutionBox(connection: connection)

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                resolution.install(continuation)
                connection.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        let resolvedEndpoint = connection.currentPath?.remoteEndpoint ?? connection.endpoint
                        do {
                            let resolved = try endpointFromNWEndpoint(resolvedEndpoint)
                            resolution.resume(with: .success(resolved))
                        } catch {
                            resolution.resume(with: .failure(error))
                        }
                        connection.cancel()
                    case let .failed(error):
                        resolution.resume(with: .failure(CastError.discoveryFailed(String(describing: error))))
                        connection.cancel()
                    case .cancelled:
                        resolution.resume(with: .failure(CancellationError()))
                    case .setup, .preparing, .waiting:
                        break
                    @unknown default:
                        break
                    }
                }
                connection.start(queue: queue)
            }
        } onCancel: {
            resolution.cancel()
            connection.cancel()
        }
    }

    private static func endpointFromNWEndpoint(_ endpoint: NWEndpoint) throws -> CastBonjourDiscoveryParser.ResolvedEndpoint {
        guard case let .hostPort(host, port) = endpoint else {
            throw CastError.discoveryFailed("Cast service did not resolve to host/port endpoint")
        }
        return .init(host: hostString(host), port: Int(port.rawValue))
    }

    private static func hostString(_ host: NWEndpoint.Host) -> String {
        switch host {
        case let .name(name, _):
            return name
        case let .ipv4(address):
            return address.debugDescription
        case let .ipv6(address):
            return address.debugDescription
        @unknown default:
            return host.debugDescription
        }
    }
}

private extension NWDNSSDDiscoveryBrowser {
    /// Coordinates callback-based NWConnection state updates with a one-shot async continuation.
    ///
    /// This uses a lock instead of an actor because NWConnection callbacks are synchronous and
    /// we only need exact-once continuation resumption for a single short-lived resolution task.
    final class ConnectionResolutionBox: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<CastBonjourDiscoveryParser.ResolvedEndpoint, any Error>?
        private var isCompleted = false

        init(connection _: NWConnection) {}

        func install(_ continuation: CheckedContinuation<CastBonjourDiscoveryParser.ResolvedEndpoint, any Error>) {
            lock.lock()
            self.continuation = continuation
            lock.unlock()
        }

        func resume(with result: Result<CastBonjourDiscoveryParser.ResolvedEndpoint, any Error>) {
            lock.lock()
            guard isCompleted == false, let continuation else {
                lock.unlock()
                return
            }
            isCompleted = true
            self.continuation = nil
            lock.unlock()

            switch result {
            case let .success(endpoint):
                continuation.resume(returning: endpoint)
            case let .failure(error):
                continuation.resume(throwing: error)
            }
        }

        func cancel() {
            resume(with: .failure(CancellationError()))
        }
    }
}
