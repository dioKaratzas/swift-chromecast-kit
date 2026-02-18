//
//  ChromecastKit
//  Swift package for Google Cast (Chromecast).
//

import Foundation

/// High-level sender for Cast multizone (speaker group) namespace commands.
///
/// Use this controller to query group membership and related casting-group metadata.
public actor CastMultizoneController {
    private let dispatcher: CastCommandDispatcher
    private let stateStore: CastSessionStateStore

    init(dispatcher: CastCommandDispatcher, stateStore: CastSessionStateStore) {
        self.dispatcher = dispatcher
        self.stateStore = stateStore
    }

    /// Requests current multizone group membership status.
    @discardableResult
    public func getStatus() async throws -> CastRequestID {
        try await dispatcher.send(
            namespace: .multizone,
            target: .platform,
            payload: CastMultizonePayloadBuilder.getStatus()
        )
    }

    /// Requests casting-groups metadata from the multizone namespace.
    @discardableResult
    public func getCastingGroups() async throws -> CastRequestID {
        try await dispatcher.send(
            namespace: .multizone,
            target: .platform,
            payload: CastMultizonePayloadBuilder.getCastingGroups()
        )
    }

    /// Returns the latest known multizone status for this session, if any.
    public func status() async -> CastMultizoneStatus? {
        await stateStore.multizoneStatus()
    }
}
