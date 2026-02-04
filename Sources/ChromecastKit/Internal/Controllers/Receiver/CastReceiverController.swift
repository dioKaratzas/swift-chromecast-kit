//
//  ChromecastKit
//  Swift package for Google Cast (Chromecast).
//

import Foundation

/// High-level sender for Cast receiver namespace commands.
///
/// This actor builds typed receiver requests and delegates route/request handling
/// to the command dispatcher.
actor CastReceiverController {
    private let dispatcher: CastCommandDispatcher

    init(dispatcher: CastCommandDispatcher) {
        self.dispatcher = dispatcher
    }

    /// Requests receiver status from the Cast platform namespace.
    @discardableResult
    func getStatus() async throws -> CastRequestID {
        try await dispatcher.send(
            namespace: .receiver,
            target: .platform,
            payload: CastReceiverPayloadBuilder.getStatus()
        )
    }

    /// Sets device volume to a level between `0.0` and `1.0`.
    @discardableResult
    func setVolume(level: Double) async throws -> CastRequestID {
        try await dispatcher.send(
            namespace: .receiver,
            target: .platform,
            payload: CastReceiverPayloadBuilder.setVolume(level: level)
        )
    }

    /// Sets muted state on the receiver.
    @discardableResult
    func setMuted(_ muted: Bool) async throws -> CastRequestID {
        try await dispatcher.send(
            namespace: .receiver,
            target: .platform,
            payload: CastReceiverPayloadBuilder.setMuted(muted)
        )
    }

    /// Launches an app on the receiver by app ID.
    @discardableResult
    func launch(appID: CastAppID) async throws -> CastRequestID {
        try await dispatcher.send(
            namespace: .receiver,
            target: .platform,
            payload: CastReceiverPayloadBuilder.launch(appID: appID)
        )
    }

    /// Stops the current receiver app session.
    @discardableResult
    func stop(sessionID: CastAppSessionID? = nil) async throws -> CastRequestID {
        try await dispatcher.send(
            namespace: .receiver,
            target: .platform,
            payload: CastReceiverPayloadBuilder.stop(sessionID: sessionID)
        )
    }

    /// Queries app availability for one or more app IDs.
    @discardableResult
    func getAppAvailability(appIDs: [CastAppID]) async throws -> CastRequestID {
        try await dispatcher.send(
            namespace: .receiver,
            target: .platform,
            payload: CastReceiverPayloadBuilder.getAppAvailability(appIDs: appIDs)
        )
    }
}
