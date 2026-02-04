//
//  ChromecastKit
//  Swift package for Google Cast (Chromecast).
//

import Foundation

protocol CastDiscoveryBrowser: Sendable {
    func start(configuration: CastDiscoveryConfiguration) async throws
    func stop() async
}

/// Actor that owns discovered device state and discovery lifecycle coordination.
///
/// Browser/network implementation details are injected behind an internal protocol.
/// This keeps the public API stable while enabling independent testing of state and
/// event semantics before mDNS transport integration is implemented.
actor CastDiscovery {
    let configuration: CastDiscoveryConfiguration

    private let browser: any CastDiscoveryBrowser
    private var stateValue = CastDiscoveryState.stopped
    private var devicesByID = [CastDeviceID: CastDeviceDescriptor]()
    private var eventContinuations = [UUID: AsyncStream<CastDiscoveryEvent>.Continuation]()

    init(
        configuration: CastDiscoveryConfiguration = .init(),
        browser: any CastDiscoveryBrowser
    ) {
        self.configuration = configuration
        self.browser = browser
    }

    /// Current discovery runtime state.
    func state() -> CastDiscoveryState {
        stateValue
    }

    /// Current discovered device snapshot.
    func devices() -> [CastDeviceDescriptor] {
        devicesByID.values.sorted { lhs, rhs in
            if lhs.friendlyName == rhs.friendlyName {
                return lhs.id.rawValue < rhs.id.rawValue
            }
            return lhs.friendlyName.localizedCaseInsensitiveCompare(rhs.friendlyName) == .orderedAscending
        }
    }

    /// Subscribes to discovery lifecycle and device change events.
    func events() -> AsyncStream<CastDiscoveryEvent> {
        let id = UUID()

        return AsyncStream { continuation in
            eventContinuations[id] = continuation
            continuation.onTermination = { [id] _ in
                Task { await self.removeEventContinuation(id: id) }
            }
        }
    }

    /// Starts discovery browsing.
    func start() async throws {
        switch stateValue {
        case .running, .starting:
            return
        case .stopped, .failed:
            break
        }

        stateValue = .starting

        do {
            try await browser.start(configuration: configuration)
            stateValue = .running
            emit(.started)
        } catch {
            let castError = mapDiscoveryError(error)
            stateValue = .failed(castError)
            emit(.error(castError))
            throw castError
        }
    }

    /// Stops discovery browsing.
    func stop() async {
        await browser.stop()
        stateValue = .stopped
        emit(.stopped)
    }

    /// Clears discovered devices without stopping browsing.
    func clearDevices() {
        devicesByID.removeAll()
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

    private func removeEventContinuation(id: UUID) {
        eventContinuations[id] = nil
    }

    private func mapDiscoveryError(_ error: any Error) -> CastError {
        if let castError = error as? CastError {
            return castError
        }
        return .discoveryFailed(String(describing: error))
    }
}
