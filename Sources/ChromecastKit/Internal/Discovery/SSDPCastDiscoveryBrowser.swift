//
//  ChromecastKit
//  SPDX-License-Identifier: Apache-2.0
//  Copyright 2026 Dionysis Karatzas
//

@preconcurrency import Network
import Dispatch
import Foundation

/// Best-effort SSDP/DIAL fallback discovery backend.
///
/// This is primarily useful on networks where Bonjour/mDNS browsing is restricted.
/// It sends DIAL SSDP `M-SEARCH` queries and fetches device-description XML from `LOCATION`.
actor SSDPCastDiscoveryBrowser: CastDiscoveryBrowser {
    // MARK: Types

    // MARK: State

    private let callbackQueue = DispatchQueue(label: "ChromecastKit.Discovery.SSDP")

    private var configuration = CastDiscovery.Configuration()
    private var connection: NWConnection?
    private var isRunning = false
    private var eventContinuations = [UUID: AsyncStream<CastDiscoveryBrowserEvent>.Continuation]()
    private var pollTask: Task<Void, Never>?
    private var knownLocations = KnownLocationRegistry()
    private var detailFetchTasks = [URL: Task<Void, Never>]()

    // MARK: CastDiscoveryBrowser

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
        guard isRunning == false else {
            return
        }
        isRunning = true
        self.configuration = configuration

        let params = NWParameters.udp
        params.includePeerToPeer = false
        params.allowLocalEndpointReuse = true

        let connection = NWConnection(
            host: NWEndpoint.Host(CastSSDPDiscoveryParser.multicastHost),
            port: NWEndpoint.Port(rawValue: UInt16(CastSSDPDiscoveryParser.multicastPort))!,
            using: params
        )
        self.connection = connection

        connection.stateUpdateHandler = { state in
            switch state {
            case let .failed(error):
                Task { await self.emit(.error(.discoveryFailed("SSDP failed: \(error)"))) }
            default:
                break
            }
        }

        connection.start(queue: callbackQueue)
        startReceiveLoopIfNeeded()
        startPollingLoopIfNeeded()

        do {
            try await sendSearchRequest()
        } catch {
            // keep backend alive; periodic retries may recover.
            emit(.error(error as? CastError ?? .discoveryFailed(String(describing: error))))
        }
    }

    func stop() async {
        isRunning = false
        pollTask?.cancel()
        pollTask = nil
        for task in detailFetchTasks.values {
            task.cancel()
        }
        detailFetchTasks.removeAll(keepingCapacity: false)
        connection?.cancel()
        connection = nil
        knownLocations.removeAll(keepingCapacity: false)
    }

    // MARK: Polling / Receive

    private func startPollingLoopIfNeeded() {
        guard pollTask == nil else {
            return
        }
        pollTask = Task {
            while Task.isCancelled == false {
                do {
                    try await Task.sleep(nanoseconds: 15_000_000_000)
                } catch {
                    return
                }
                guard !Task.isCancelled else {
                    return
                }
                do {
                    self.expireKnownLocationsIfNeeded()
                    try await self.sendSearchRequest()
                } catch {
                    self.emit(.error(error as? CastError ?? .discoveryFailed(String(describing: error))))
                }
            }
        }
    }

    private func startReceiveLoopIfNeeded() {
        guard let connection else {
            return
        }
        connection.receiveMessage { data, _, _, error in
            if let error {
                Task { await self.emit(.error(.discoveryFailed("SSDP receive failed: \(error)"))) }
            }
            if let data, data.isEmpty == false {
                Task { await self.handleDatagram(data) }
            }
            Task { await self.scheduleNextReceive() }
        }
    }

    private func scheduleNextReceive() {
        guard isRunning, connection != nil else {
            return
        }
        startReceiveLoopIfNeeded()
    }

    // MARK: SSDP Requests

    private func sendSearchRequest() async throws {
        guard let connection else {
            throw CastError.discoveryFailed("SSDP transport not started")
        }
        let payload = Data(ssdpSearchRequest.utf8)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            connection.send(content: payload, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: CastError.discoveryFailed("SSDP send failed: \(error)"))
                } else {
                    continuation.resume(returning: ())
                }
            })
        }
    }

    // MARK: Datagram Handling

    private func handleDatagram(_ data: Data) async {
        guard let response = CastSSDPDiscoveryParser.parseSearchResponse(data),
              CastSSDPDiscoveryParser.isDialResponse(response) else {
            return
        }

        guard detailFetchTasks[response.locationURL] == nil else {
            return
        }

        detailFetchTasks[response.locationURL] = Task {
            defer { self.clearDetailFetchTask(for: response.locationURL) }
            do {
                let includeGroups = self.configuration.includeGroups
                let (xmlData, _) = try await URLSession.shared.data(from: response.locationURL)
                guard let description = CastSSDPDiscoveryParser.parseDIALDeviceDescription(xmlData),
                      let descriptor = CastSSDPDiscoveryParser.makeDescriptor(
                          from: response,
                          description: description,
                          includeGroups: includeGroups
                      ) else {
                    return
                }
                self.finishDescriptor(
                    descriptor,
                    locationURL: response.locationURL,
                    cacheMaxAge: response.cacheMaxAge
                )
            } catch is CancellationError {
                return
            } catch {
                // Best effort fallback, ignore individual failures.
            }
        }
    }

    private func finishDescriptor(
        _ descriptor: CastDeviceDescriptor,
        locationURL: URL,
        cacheMaxAge: TimeInterval?
    ) {
        knownLocations.upsert(
            locationURL: locationURL,
            deviceID: descriptor.id,
            cacheMaxAge: cacheMaxAge
        )
        emit(.deviceUpserted(descriptor))
    }

    // MARK: Expiry / Task Cleanup

    private func clearDetailFetchTask(for locationURL: URL) {
        detailFetchTasks[locationURL]?.cancel()
        detailFetchTasks[locationURL] = nil
    }

    private func expireKnownLocationsIfNeeded(now: Date = .init()) {
        for deviceID in knownLocations.expire(now: now) {
            emit(.deviceRemoved(deviceID))
        }
    }

    // MARK: Message Construction

    private var ssdpSearchRequest: String {
        [
            "M-SEARCH * HTTP/1.1",
            "HOST: \(CastSSDPDiscoveryParser.multicastHost):\(CastSSDPDiscoveryParser.multicastPort)",
            "MAN: \"ssdp:discover\"",
            "MX: 1",
            "ST: \(CastSSDPDiscoveryParser.dialSearchTarget)",
            "USER-AGENT: ChromecastKit/1.0",
            "",
            "",
        ].joined(separator: "\r\n")
    }

    // MARK: Event Fanout

    private func emit(_ event: CastDiscoveryBrowserEvent) {
        for continuation in eventContinuations.values {
            continuation.yield(event)
        }
    }

    private func removeContinuation(id: UUID) {
        eventContinuations[id] = nil
    }
}

extension SSDPCastDiscoveryBrowser {
    // MARK: Backend Cache Registry

    struct KnownLocationRegistry: Sendable {
        struct Entry: Sendable, Hashable {
            var deviceID: CastDeviceID
            var expiresAt: Date?
        }

        private(set) var entries = [URL: Entry]()

        mutating func upsert(
            locationURL: URL,
            deviceID: CastDeviceID,
            cacheMaxAge: TimeInterval?,
            now: Date = .init()
        ) {
            let expiresAt = cacheMaxAge.map { now.addingTimeInterval($0) }
            entries[locationURL] = .init(deviceID: deviceID, expiresAt: expiresAt)
        }

        mutating func expire(now: Date = .init()) -> [CastDeviceID] {
            var expiredLocationURLs = [URL]()
            var removedDeviceIDs = [CastDeviceID]()

            for (locationURL, entry) in entries {
                guard let expiresAt = entry.expiresAt, expiresAt <= now else {
                    continue
                }
                expiredLocationURLs.append(locationURL)
            }

            for locationURL in expiredLocationURLs {
                guard let entry = entries.removeValue(forKey: locationURL) else {
                    continue
                }
                removedDeviceIDs.append(entry.deviceID)
            }

            return removedDeviceIDs
        }

        mutating func removeAll(keepingCapacity: Bool) {
            entries.removeAll(keepingCapacity: keepingCapacity)
        }
    }
}
