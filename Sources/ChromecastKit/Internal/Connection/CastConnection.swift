//
//  ChromecastKit
//  SPDX-License-Identifier: Apache-2.0
//  Copyright 2026 Dionysis Karatzas
//

import Foundation

protocol CastConnectionTransport: Sendable {
    func connect(timeout: TimeInterval) async throws
    func disconnect() async
}

/// Actor that owns mutable Cast connection runtime state and lifecycle coordination.
///
/// This type serializes connection transitions and event fan-out. Transport/socket
/// implementation details are injected behind an internal transport protocol so the
/// state machine can be tested independently.
actor CastConnection {
    // MARK: State

    let configuration: Configuration

    private var stateValue = State.disconnected
    private var eventContinuations = [UUID: AsyncStream<Event>.Continuation]()
    private let transport: any CastConnectionTransport
    private let logger: ChromecastKitDiagnosticsLogger

    // MARK: Lifecycle

    init(
        configuration: Configuration = .init(),
        transport: any CastConnectionTransport
    ) {
        self.configuration = configuration
        self.transport = transport
        logger = .init(level: configuration.logLevel, category: .session)
    }

    /// Returns the current connection state snapshot.
    func state() -> State {
        stateValue
    }

    /// Subscribes to connection lifecycle events.
    ///
    /// The returned stream is multi-subscriber and cancellation-aware.
    func events() -> AsyncStream<Event> {
        let id = UUID()

        return AsyncStream { continuation in
            eventContinuations[id] = continuation
            continuation.onTermination = { [id] _ in
                Task { await self.removeEventContinuation(id: id) }
            }
        }
    }

    /// Connects the underlying transport and transitions the connection state.
    func connect() async throws {
        switch stateValue {
        case .connected, .connecting:
            return
        case .reconnecting, .disconnected, .failed:
            break
        }

        stateValue = .connecting

        do {
            try await transport.connect(timeout: configuration.connectTimeout)
            stateValue = .connected
            emit(.connected)
            logger.info("connection established")
        } catch {
            let castError = mapConnectionError(error)
            stateValue = .failed(castError)
            emit(.error(castError))
            logger.error("connection failed: \(castError)")
            throw castError
        }
    }

    /// Disconnects the underlying transport and emits a disconnection event.
    func disconnect(reason: DisconnectReason = .requested) async {
        await transport.disconnect()
        stateValue = .disconnected
        emit(.disconnected(reason: reason))
        logger.info("connection closed reason=\(reason.rawValue)")
    }

    /// Reconnects the underlying transport and emits a reconnection event on success.
    func reconnect() async throws {
        stateValue = .reconnecting
        await transport.disconnect()

        do {
            try await transport.connect(timeout: configuration.connectTimeout)
            stateValue = .connected
            emit(.reconnected)
            logger.info("connection re-established")
        } catch {
            let castError = mapConnectionError(error)
            stateValue = .failed(castError)
            emit(.error(castError))
            logger.error("reconnect failed: \(castError)")
            throw castError
        }
    }

    /// Records a runtime transport failure detected outside the connect/reconnect call path.
    ///
    /// This is used by session runtime ingress (read loop, heartbeat, etc.) to surface
    /// errors through the same connection event stream.
    func reportRuntimeError(_ error: CastError) {
        stateValue = .failed(error)
        emit(.error(error))
        logger.error("runtime connection failure: \(error)")
    }

    // MARK: Helpers

    private func emit(_ event: Event) {
        for continuation in eventContinuations.values {
            continuation.yield(event)
        }
    }

    private func removeEventContinuation(id: UUID) {
        eventContinuations[id] = nil
    }

    private func mapConnectionError(_ error: any Error) -> CastError {
        if let castError = error as? CastError {
            return castError
        }
        return .connectionFailed(String(describing: error))
    }
}
