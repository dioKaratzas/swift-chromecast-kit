//
//  ChromecastKit
//  SPDX-License-Identifier: Apache-2.0
//  Copyright 2026 Dionysis Karatzas
//

import Foundation

/// Actor that owns discovered device state and discovery lifecycle coordination.
///
/// Browser/network implementation details are injected behind an internal protocol.
/// This keeps the public API stable while enabling independent testing of state and
/// event semantics before mDNS transport integration is implemented.
public actor CastDiscovery {
    // MARK: Public State

    public let configuration: CastDiscovery.Configuration

    // MARK: Private State

    private let browser: any CastDiscoveryBrowser
    private var stateValue = CastDiscovery.State.stopped
    private var devicesByID = [CastDeviceID: CastDeviceDescriptor]()
    private var eventContinuations = [UUID: AsyncStream<CastDiscovery.Event>.Continuation]()
    private var browserEventsTask: Task<Void, Never>?
    private var browseTimeoutTask: Task<Void, Never>?
    private var activeBrowseRunID: UUID?

    // MARK: Public Initialization

    public init(configuration: CastDiscovery.Configuration = .init()) {
        self.init(configuration: configuration, browser: CompositeCastDiscoveryBrowser())
    }

    // MARK: Public API

    /// Current discovery runtime state.
    public func state() -> CastDiscovery.State {
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
    public func events() -> AsyncStream<CastDiscovery.Event> {
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

    /// Starts discovery only when not already running.
    ///
    /// This is a convenience alias that makes call sites explicit about idempotent behavior.
    public func startIfNeeded() async throws {
        try await start()
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

    /// Restarts discovery browsing and preserves the current snapshot unless browsers emit removals.
    public func restart() async throws {
        await stop()
        try await start()
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

    /// Returns the first discovered device in the current snapshot, if any.
    public func firstDevice() -> CastDeviceDescriptor? {
        devices().first
    }

    /// Waits for the first available discovered device, returning immediately if one already exists.
    public func waitForFirstDevice(timeout: TimeInterval? = nil) async throws -> CastDeviceDescriptor {
        if let existing = firstDevice() {
            return existing
        }

        let stream = events()
        return try await waitForDeviceFromEvents(
            stream,
            timeout: timeout,
            operationDescription: "discover first device"
        ) { event in
            guard case let .deviceUpserted(device, _) = event else {
                return nil
            }
            return device
        }
    }

    // MARK: Internal Initialization

    init(
        configuration: CastDiscovery.Configuration = .init(),
        browser: any CastDiscoveryBrowser
    ) {
        self.configuration = configuration
        self.browser = browser
    }

    // MARK: Internal Browser Integration

    /// Applies or updates a discovered device descriptor.
    ///
    /// This method is `internal` for the eventual mDNS browser integration.
    func upsertDiscoveredDevice(_ device: CastDeviceDescriptor) {
        if devicesByID[device.id] != nil {
            devicesByID[device.id] = device
            emit(.deviceUpserted(device: device, isNew: false))
            return
        }

        if let existingID = existingDeviceID(matching: device) {
            let existing = devicesByID[existingID] ?? device
            let merged = mergeDiscoveredDevice(existing: existing, incoming: device, preservingID: existingID)
            devicesByID[existingID] = merged
            emit(.deviceUpserted(device: merged, isNew: false))
            return
        }

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

    // MARK: Private Helpers

    private func emit(_ event: CastDiscovery.Event) {
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

    private func existingDeviceID(matching incoming: CastDeviceDescriptor) -> CastDeviceID? {
        if devicesByID[incoming.id] != nil {
            return incoming.id
        }

        if let incomingUUID = incoming.uuid {
            if let match = devicesByID.values.first(where: { $0.uuid == incomingUUID }) {
                return match.id
            }
        }

        if let match = devicesByID.values.first(where: {
            $0.host.caseInsensitiveCompare(incoming.host) == .orderedSame && $0.port == incoming.port
        }) {
            return match.id
        }

        return nil
    }

    private func mergeDiscoveredDevice(
        existing: CastDeviceDescriptor,
        incoming: CastDeviceDescriptor,
        preservingID id: CastDeviceID
    ) -> CastDeviceDescriptor {
        let existingLooksLikeHostLabel = existing.friendlyName == existing.host
        let incomingLooksLikeHostLabel = incoming.friendlyName == incoming.host

        let friendlyName: String
        if existingLooksLikeHostLabel, incomingLooksLikeHostLabel == false {
            friendlyName = incoming.friendlyName
        } else {
            friendlyName = existing.friendlyName
        }

        return CastDeviceDescriptor(
            id: id,
            friendlyName: friendlyName,
            host: existing.host,
            port: existing.port,
            modelName: incoming.modelName ?? existing.modelName,
            manufacturer: incoming.manufacturer ?? existing.manufacturer,
            uuid: existing.uuid ?? incoming.uuid,
            capabilities: existing.capabilities.union(incoming.capabilities)
        )
    }

    private func scheduleBrowseTimeoutIfNeeded(runID: UUID) {
        browseTimeoutTask?.cancel()
        browseTimeoutTask = nil

        guard let timeout = configuration.browseTimeout, timeout > 0 else {
            return
        }

        browseTimeoutTask = Task {
            do {
                try await CastTaskTiming.sleep(for: timeout)
            } catch is CancellationError {
                return
            } catch {
                return
            }
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
        _ stream: AsyncStream<CastDiscovery.Event>,
        timeout: TimeInterval?,
        operationDescription: String,
        matcher: @escaping @Sendable (CastDiscovery.Event) -> CastDeviceDescriptor?
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
                    try await CastTaskTiming.sleep(for: timeout)
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
