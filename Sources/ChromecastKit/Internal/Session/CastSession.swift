//
//  ChromecastKit
//  Swift package for Google Cast (Chromecast).
//

import Foundation

/// Internal runtime facade that assembles connection, command dispatch, controllers,
/// and status processing for a single Cast device session.
///
/// This type is intentionally internal until the public API surface is finalized.
actor CastSession {
    nonisolated let device: CastDeviceDescriptor
    nonisolated let media: CastMediaController
    nonisolated let receiver: CastReceiverController

    private let connection: CastConnection
    private let stateStore: CastSessionStateStore
    private let statusProcessor: CastStatusMessageProcessor
    private let dispatcher: CastCommandDispatcher

    init(
        device: CastDeviceDescriptor,
        connection: CastConnection,
        dispatcher: CastCommandDispatcher,
        media: CastMediaController,
        receiver: CastReceiverController,
        stateStore: CastSessionStateStore,
        statusProcessor: CastStatusMessageProcessor
    ) {
        self.device = device
        self.connection = connection
        self.dispatcher = dispatcher
        self.media = media
        self.receiver = receiver
        self.stateStore = stateStore
        self.statusProcessor = statusProcessor
    }

    init(
        device: CastDeviceDescriptor,
        transport: any CastConnectionTransport & CastCommandTransport,
        configuration: CastConnectionConfiguration = .init()
    ) {
        let connection = CastConnection(configuration: configuration, transport: transport)
        let dispatcher = CastCommandDispatcher(transport: transport)
        let media = CastMediaController(dispatcher: dispatcher)
        let receiver = CastReceiverController(dispatcher: dispatcher)
        let stateStore = CastSessionStateStore()
        let statusProcessor = CastStatusMessageProcessor(
            stateStore: stateStore,
            dispatcher: dispatcher,
            mediaController: media
        )

        self.init(
            device: device,
            connection: connection,
            dispatcher: dispatcher,
            media: media,
            receiver: receiver,
            stateStore: stateStore,
            statusProcessor: statusProcessor
        )
    }

    func connect() async throws {
        try await connection.connect()
    }

    func disconnect(reason: CastDisconnectReason = .requested) async {
        await connection.disconnect(reason: reason)
    }

    func reconnect() async throws {
        try await connection.reconnect()
    }

    func connectionState() async -> CastConnectionState {
        await connection.state()
    }

    func connectionEvents() async -> AsyncStream<CastConnectionEvent> {
        await connection.events()
    }

    func receiverStatus() async -> CastReceiverStatus? {
        await stateStore.receiverStatus()
    }

    func mediaStatus() async -> CastMediaStatus? {
        await stateStore.mediaStatus()
    }

    func snapshot() async -> CastSessionStateSnapshot {
        await stateStore.snapshot()
    }

    func stateEvents() async -> AsyncStream<CastSessionStateEvent> {
        await stateStore.events()
    }

    @discardableResult
    func applyInboundMessage(_ message: CastInboundMessage) async throws -> Bool {
        let matchedPendingReply = try await dispatcher.consumeInboundMessage(message)
        let handledStatus = try await statusProcessor.apply(message)
        return matchedPendingReply || handledStatus
    }
}
