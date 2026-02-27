//
//  ChromecastKit
//  SPDX-License-Identifier: Apache-2.0
//  Copyright 2026 Dionysis Karatzas
//

import Foundation

/// High-level sender for Cast multizone (speaker group) namespace commands.
///
/// Use this controller to query group membership and related casting-group metadata.
public actor CastMultizoneController {
    // MARK: Private State

    private let dispatcher: CastCommandDispatcher
    private let stateStore: CastSessionStateStore

    // MARK: Public API

    /// Requests current multizone group membership status.
    @discardableResult
    public func getStatus() async throws -> CastRequestID {
        try await sendPlatformCommand(CastMultizonePayloadBuilder.getStatus())
    }

    /// Requests casting-groups metadata from the multizone namespace.
    @discardableResult
    public func getCastingGroups() async throws -> CastRequestID {
        try await sendPlatformCommand(CastMultizonePayloadBuilder.getCastingGroups())
    }

    /// Returns the latest known multizone status for this session, if any.
    public func status() async -> CastMultizoneStatus? {
        await stateStore.multizoneStatus()
    }

    // MARK: Internal Initialization

    init(dispatcher: CastCommandDispatcher, stateStore: CastSessionStateStore) {
        self.dispatcher = dispatcher
        self.stateStore = stateStore
    }

    // MARK: Private Helpers

    @discardableResult
    private func sendPlatformCommand<Payload: Encodable & Sendable>(
        _ payload: Payload
    ) async throws -> CastRequestID {
        try await dispatcher.send(
            namespace: .multizone,
            target: .platform,
            payload: payload
        )
    }
}
