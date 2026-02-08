//
//  ChromecastKit
//  Swift package for Google Cast (Chromecast).
//

import Foundation

/// High-level Cast device session facade.
///
/// This is the primary entry point for controlling a Chromecast after discovery.
/// It exposes ergonomic receiver/media controllers while hiding transport, wire models,
/// and protocol machinery.
public actor CastSession {
    public nonisolated let device: CastDeviceDescriptor
    public nonisolated let media: CastMediaController
    public nonisolated let receiver: CastReceiverController

    private let runtime: CastSessionRuntime

    /// Creates a Cast session for a discovered device using the built-in Cast v2 TLS transport.
    public init(
        device: CastDeviceDescriptor,
        configuration: Configuration = .init()
    ) {
        let transport = NWTLSCastV2Transport(device: device)
        let runtime = CastSessionRuntime(
            device: device,
            transport: transport,
            configuration: configuration.coreValue
        )

        self.device = device
        self.runtime = runtime
        self.media = runtime.media
        self.receiver = runtime.receiver
    }

    init(runtime: CastSessionRuntime) {
        self.device = runtime.device
        self.runtime = runtime
        self.media = runtime.media
        self.receiver = runtime.receiver
    }

    /// Establishes the Cast transport connection.
    public func connect() async throws {
        try await runtime.connect()
    }

    /// Closes the Cast transport connection.
    public func disconnect(reason: DisconnectReason = .requested) async {
        await runtime.disconnect(reason: reason.coreValue)
    }

    /// Reconnects the Cast transport connection.
    public func reconnect() async throws {
        try await runtime.reconnect()
    }

    /// Returns the current connection lifecycle state.
    public func connectionState() async -> ConnectionState {
        await runtime.connectionState().publicValue
    }

    /// Emits connection lifecycle events for this session.
    public func connectionEvents() async -> AsyncStream<ConnectionEvent> {
        let coreStream = await runtime.connectionEvents()
        return mapStream(coreStream) { $0.publicValue }
    }

    /// Returns the latest known receiver status, if any.
    public func receiverStatus() async -> CastReceiverStatus? {
        await runtime.receiverStatus()
    }

    /// Returns the latest known media status, if any.
    public func mediaStatus() async -> CastMediaStatus? {
        await runtime.mediaStatus()
    }

    /// Returns the latest known receiver/media status snapshot.
    public func snapshot() async -> StateSnapshot {
        await runtime.snapshot().publicValue
    }

    /// Emits session status updates as receiver/media statuses change.
    public func stateEvents() async -> AsyncStream<StateEvent> {
        let coreStream = await runtime.stateEvents()
        return mapStream(coreStream) { $0.publicValue }
    }

    /// Sends a typed JSON object on a Cast namespace and injects a `requestId` for correlation.
    @discardableResult
    public func send(
        namespace: CastNamespace,
        target: NamespaceTarget = .currentApplication,
        payload: [String: JSONValue]
    ) async throws -> CastRequestID {
        try await runtime.sendNamespaceMessage(
            namespace: namespace,
            target: target.coreValue,
            payload: payload
        )
    }

    /// Sends a typed JSON object on a Cast namespace without injecting a `requestId`.
    ///
    /// This is primarily useful for transport-control or app-defined fire-and-forget messages.
    public func sendUntracked(
        namespace: CastNamespace,
        target: NamespaceTarget = .currentApplication,
        payload: [String: JSONValue]
    ) async throws {
        try await runtime.sendNamespaceMessageUntracked(
            namespace: namespace,
            target: target.coreValue,
            payload: payload
        )
    }

    /// Emits inbound messages for custom (non-core) Cast namespaces.
    ///
    /// Pass a specific namespace to filter to a single app-defined channel.
    public func namespaceMessages(_ namespace: CastNamespace? = nil) async -> AsyncStream<NamespaceMessage> {
        let coreStream = await runtime.namespaceMessages(namespace: namespace)
        return mapStream(coreStream) { $0.publicNamespaceMessage }
    }
}

private func mapStream<Input: Sendable, Output: Sendable>(
    _ input: AsyncStream<Input>,
    transform: @escaping @Sendable (Input) -> Output
) -> AsyncStream<Output> {
    AsyncStream { continuation in
        let task = Task {
            for await value in input {
                continuation.yield(transform(value))
            }
            continuation.finish()
        }

        continuation.onTermination = { _ in
            task.cancel()
        }
    }
}
