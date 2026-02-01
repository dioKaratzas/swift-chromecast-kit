//
//  ChromecastKit
//  Swift package for Google Cast (Chromecast).
//

import Foundation

/// High-level sender for Cast receiver namespace commands.
///
/// This actor builds typed receiver requests and delegates route/request handling
/// to the command dispatcher.
public actor CastReceiverController {
    private let dispatcher: CastCommandDispatcher

    init(dispatcher: CastCommandDispatcher) {
        self.dispatcher = dispatcher
    }

    /// Requests receiver status from the Cast platform namespace.
    @discardableResult
    public func getStatus() async throws -> Int {
        try await dispatcher.send(
            namespace: .receiver,
            target: .platform,
            payload: CastReceiverPayloadBuilder.getStatus()
        )
    }

    /// Sets device volume to a level between `0.0` and `1.0`.
    @discardableResult
    public func setVolume(level: Double) async throws -> Int {
        try await dispatcher.send(
            namespace: .receiver,
            target: .platform,
            payload: CastReceiverPayloadBuilder.setVolume(level: level)
        )
    }

    /// Sets muted state on the receiver.
    @discardableResult
    public func setMuted(_ muted: Bool) async throws -> Int {
        try await dispatcher.send(
            namespace: .receiver,
            target: .platform,
            payload: CastReceiverPayloadBuilder.setMuted(muted)
        )
    }

    /// Launches an app on the receiver by app ID.
    @discardableResult
    public func launch(appID: String) async throws -> Int {
        try await dispatcher.send(
            namespace: .receiver,
            target: .platform,
            payload: CastReceiverPayloadBuilder.launch(appID: appID)
        )
    }

    /// Stops the current receiver app session.
    @discardableResult
    public func stop(sessionID: String? = nil) async throws -> Int {
        try await dispatcher.send(
            namespace: .receiver,
            target: .platform,
            payload: CastReceiverPayloadBuilder.stop(sessionID: sessionID)
        )
    }

    /// Queries app availability for one or more app IDs.
    @discardableResult
    public func getAppAvailability(appIDs: [String]) async throws -> Int {
        try await dispatcher.send(
            namespace: .receiver,
            target: .platform,
            payload: CastReceiverPayloadBuilder.getAppAvailability(appIDs: appIDs)
        )
    }
}

