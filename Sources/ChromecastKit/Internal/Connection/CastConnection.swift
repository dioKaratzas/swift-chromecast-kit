//
//  ChromecastKit
//  Swift package for Google Cast (Chromecast).
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
    let configuration: CastConnectionConfiguration

    private var stateValue = CastConnectionState.disconnected
    private var eventContinuations = [UUID: AsyncStream<CastConnectionEvent>.Continuation]()
    private let transport: any CastConnectionTransport

    init(
        configuration: CastConnectionConfiguration = .init(),
        transport: any CastConnectionTransport
    ) {
        self.configuration = configuration
        self.transport = transport
    }

    /// Returns the current connection state snapshot.
    func state() -> CastConnectionState {
        stateValue
    }

    /// Subscribes to connection lifecycle events.
    ///
    /// The returned stream is multi-subscriber and cancellation-aware.
    func events() -> AsyncStream<CastConnectionEvent> {
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
        } catch {
            let castError = mapConnectionError(error)
            stateValue = .failed(castError)
            emit(.error(castError))
            throw castError
        }
    }

    /// Disconnects the underlying transport and emits a disconnection event.
    func disconnect(reason: CastDisconnectReason = .requested) async {
        await transport.disconnect()
        stateValue = .disconnected
        emit(.disconnected(reason: reason))
    }

    /// Reconnects the underlying transport and emits a reconnection event on success.
    func reconnect() async throws {
        stateValue = .reconnecting
        await transport.disconnect()

        do {
            try await transport.connect(timeout: configuration.connectTimeout)
            stateValue = .connected
            emit(.reconnected)
        } catch {
            let castError = mapConnectionError(error)
            stateValue = .failed(castError)
            emit(.error(castError))
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
    }

    private func emit(_ event: CastConnectionEvent) {
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
