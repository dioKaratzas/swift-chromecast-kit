//
//  ChromecastKit
//  Swift package for Google Cast (Chromecast).
//

import Foundation

/// Actor that owns discovered device state and discovery lifecycle coordination.
///
/// Browser/network implementation details are injected behind an internal protocol.
/// This keeps the public API stable while enabling independent testing of state and
/// event semantics before mDNS transport integration is implemented.
public actor CastDiscovery {
    public let configuration: CastDiscoveryConfiguration

    private let browser: any CastDiscoveryBrowser
    private var stateValue = CastDiscoveryState.stopped
    private var devicesByID = [CastDeviceID: CastDeviceDescriptor]()
    private var eventContinuations = [UUID: AsyncStream<CastDiscoveryEvent>.Continuation]()
    private var browserEventsTask: Task<Void, Never>?
    private var browseTimeoutTask: Task<Void, Never>?
    private var activeBrowseRunID: UUID?

    public init(configuration: CastDiscoveryConfiguration = .init()) {
        self.init(configuration: configuration, browser: CompositeCastDiscoveryBrowser())
    }

    init(
        configuration: CastDiscoveryConfiguration = .init(),
        browser: any CastDiscoveryBrowser
    ) {
        self.configuration = configuration
        self.browser = browser
    }

    /// Current discovery runtime state.
    public func state() -> CastDiscoveryState {
        stateValue
    }

    /// Current discovered device snapshot.
    public func devices() -> [CastDeviceDescriptor] {
        devicesByID.values.sorted { lhs, rhs in
            if lhs.friendlyName == rhs.friendlyName {
                return lhs.id.rawValue < rhs.id.rawValue
            }
            return lhs.friendlyName.localizedCaseInsensitiveCompare(rhs.friendlyName) == .orderedAscending
        }
    }

    /// Returns a discovered device by Cast device ID if present in the current snapshot.
    public func device(id: CastDeviceID) -> CastDeviceDescriptor? {
        devicesByID[id]
    }

    /// Returns the first discovered device whose friendly name matches the provided value.
    ///
    /// Matching is case-insensitive by default to support user-entered device names.
    public func device(
        named name: String,
        caseInsensitive: Bool = true
    ) -> CastDeviceDescriptor? {
        devices().first { device in
            if caseInsensitive {
                return device.friendlyName.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            }
            return device.friendlyName == name
        }
    }

    /// Subscribes to discovery lifecycle and device change events.
    public func events() -> AsyncStream<CastDiscoveryEvent> {
        let id = UUID()

        return AsyncStream { continuation in
            eventContinuations[id] = continuation
            continuation.onTermination = { [id] _ in
                Task { await self.removeEventContinuation(id: id) }
            }
        }
    }

    /// Waits until a device with the provided Cast device ID is discovered.
    ///
    /// If a matching device is already in the snapshot, it is returned immediately.
    public func waitForDevice(
        id: CastDeviceID,
        timeout: TimeInterval? = nil
    ) async throws -> CastDeviceDescriptor {
        if let existing = device(id: id) {
            return existing
        }

        let stream = events()
        return try await waitForDeviceFromEvents(
            stream,
            timeout: timeout,
            operationDescription: "discover device \(id.rawValue)"
        ) { event in
            guard case let .deviceUpserted(device, _) = event, device.id == id else {
                return nil
            }
            return device
        }
    }

    /// Waits until a device with the provided friendly name is discovered.
    ///
    /// Matching is case-insensitive by default to support user-entered device names.
    public func waitForDevice(
        named name: String,
        caseInsensitive: Bool = true,
        timeout: TimeInterval? = nil
    ) async throws -> CastDeviceDescriptor {
        if let existing = device(named: name, caseInsensitive: caseInsensitive) {
            return existing
        }

        let stream = events()
        return try await waitForDeviceFromEvents(
            stream,
            timeout: timeout,
            operationDescription: "discover device named \(name)"
        ) { event in
            guard case let .deviceUpserted(device, _) = event else {
                return nil
            }
            let matches: Bool
            if caseInsensitive {
                matches = device.friendlyName.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            } else {
                matches = device.friendlyName == name
            }
            return matches ? device : nil
        }
    }

    /// Starts discovery browsing.
    public func start() async throws {
        switch stateValue {
        case .running, .starting:
            return
        case .stopped, .failed:
            break
        }

        stateValue = .starting
        startBrowserEventTaskIfNeeded()

        do {
            try await browser.start(configuration: configuration)
            stateValue = .running
            emit(.started)
        } catch {
            browserEventsTask?.cancel()
            browserEventsTask = nil
            browseTimeoutTask?.cancel()
            browseTimeoutTask = nil
            activeBrowseRunID = nil
            let castError = mapDiscoveryError(error)
            stateValue = .failed(castError)
            emit(.error(castError))
            throw castError
        }

        let runID = UUID()
        activeBrowseRunID = runID
        scheduleBrowseTimeoutIfNeeded(runID: runID)
    }

    /// Stops discovery browsing.
    public func stop() async {
        await browser.stop()
        browserEventsTask?.cancel()
        browserEventsTask = nil
        browseTimeoutTask?.cancel()
        browseTimeoutTask = nil
        activeBrowseRunID = nil
        stateValue = .stopped
        emit(.stopped)
    }

    /// Clears discovered devices without stopping browsing.
    public func clearDevices() {
        devicesByID.removeAll()
    }

    /// Adds or updates a known Cast device descriptor in the discovery snapshot.
    ///
    /// This is useful when discovery is restricted on the current network but a device host is known.
    public func addKnownDevice(_ device: CastDeviceDescriptor) {
        upsertDiscoveredDevice(device)
    }

    /// Adds or updates a known Cast host in the discovery snapshot and returns the descriptor.
    ///
    /// The default identifier is stable for the provided `host`/`port` pair.
    @discardableResult
    public func addKnownHost(
        host: String,
        port: Int = 8009,
        id: CastDeviceID? = nil,
        friendlyName: String? = nil,
        modelName: String? = nil,
        manufacturer: String? = nil,
        uuid: UUID? = nil,
        capabilities: Set<CastDeviceCapability> = []
    ) -> CastDeviceDescriptor {
        let descriptor = CastDeviceDescriptor(
            id: id ?? CastDeviceID("manual:\(host):\(port)"),
            friendlyName: friendlyName ?? host,
            host: host,
            port: port,
            modelName: modelName,
            manufacturer: manufacturer,
            uuid: uuid,
            capabilities: capabilities
        )
        upsertDiscoveredDevice(descriptor)
        return descriptor
    }

    /// Removes a manually added or discovered device from the current snapshot.
    public func removeKnownDevice(id: CastDeviceID) {
        removeDiscoveredDevice(id: id)
    }

    /// Applies or updates a discovered device descriptor.
    ///
    /// This method is `internal` for the eventual mDNS browser integration.
    func upsertDiscoveredDevice(_ device: CastDeviceDescriptor) {
        let isNew = devicesByID.updateValue(device, forKey: device.id) == nil
        emit(.deviceUpserted(device: device, isNew: isNew))
    }

    /// Removes a discovered device by identifier.
    ///
    /// This method is `internal` for the eventual mDNS browser integration.
    func removeDiscoveredDevice(id: CastDeviceID) {
        guard devicesByID.removeValue(forKey: id) != nil else {
            return
        }
        emit(.deviceRemoved(id: id))
    }

    private func emit(_ event: CastDiscoveryEvent) {
        for continuation in eventContinuations.values {
            continuation.yield(event)
        }
    }

    private func startBrowserEventTaskIfNeeded() {
        guard browserEventsTask == nil else {
            return
        }

        let browser = self.browser
        browserEventsTask = Task {
            let stream = await browser.events()
            for await event in stream {
                await self.handleBrowserEvent(event)
            }
        }
    }

    private func handleBrowserEvent(_ event: CastDiscoveryBrowserEvent) async {
        switch event {
        case let .deviceUpserted(device):
            upsertDiscoveredDevice(device)
        case let .deviceRemoved(id):
            removeDiscoveredDevice(id: id)
        case let .error(error):
            await transitionToFailed(error)
        }
    }

    private func removeEventContinuation(id: UUID) {
        eventContinuations[id] = nil
    }

    private func mapDiscoveryError(_ error: any Error) -> CastError {
        if let castError = error as? CastError {
            return castError
        }
        return .discoveryFailed(String(describing: error))
    }

    private func scheduleBrowseTimeoutIfNeeded(runID: UUID) {
        browseTimeoutTask?.cancel()
        browseTimeoutTask = nil

        guard let timeout = configuration.browseTimeout, timeout > 0 else {
            return
        }

        browseTimeoutTask = Task {
            let ns = UInt64(max(0, timeout) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: ns)
            guard !Task.isCancelled else {
                return
            }
            await self.handleBrowseTimeout(runID: runID)
        }
    }

    private func handleBrowseTimeout(runID: UUID) async {
        guard activeBrowseRunID == runID else {
            return
        }
        guard stateValue == .running else {
            return
        }
        await stop()
    }

    private func transitionToFailed(_ error: CastError) async {
        await browser.stop()
        browserEventsTask?.cancel()
        browserEventsTask = nil
        browseTimeoutTask?.cancel()
        browseTimeoutTask = nil
        activeBrowseRunID = nil
        stateValue = .failed(error)
        emit(.error(error))
    }

    private func waitForDeviceFromEvents(
        _ stream: AsyncStream<CastDiscoveryEvent>,
        timeout: TimeInterval?,
        operationDescription: String,
        matcher: @escaping @Sendable (CastDiscoveryEvent) -> CastDeviceDescriptor?
    ) async throws -> CastDeviceDescriptor {
        try await withThrowingTaskGroup(of: CastDeviceDescriptor.self) { group in
            group.addTask {
                for await event in stream {
                    if let device = matcher(event) {
                        return device
                    }
                }
                throw CastError.disconnected
            }

            if let timeout, timeout > 0 {
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                    throw CastError.timeout(operation: operationDescription)
                }
            }

            guard let device = try await group.next() else {
                throw CastError.timeout(operation: operationDescription)
            }

            group.cancelAll()
            return device
        }
    }
}
