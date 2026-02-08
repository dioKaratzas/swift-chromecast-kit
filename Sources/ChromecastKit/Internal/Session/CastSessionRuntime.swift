//
//  ChromecastKit
//  Swift package for Google Cast (Chromecast).
//

import Foundation

/// Internal runtime facade that assembles connection, command dispatch, controllers,
/// and status processing for a single Cast device session.
actor CastSessionRuntime {
    nonisolated let device: CastDeviceDescriptor
    nonisolated let media: CastMediaController
    nonisolated let receiver: CastReceiverController

    private let connection: CastConnection
    private let stateStore: CastSessionStateStore
    private let statusProcessor: CastStatusMessageProcessor
    private let dispatcher: CastCommandDispatcher
    private let inboundTransport: (any CastInboundMessageTransport)?
    private let heartbeatInterval: TimeInterval
    private let autoReconnect: Bool
    private var inboundTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var heartbeatRecoveryTask: Task<Void, Never>?
    private var lastHeartbeatActivityAt = Date()
    private var connectedApplicationTransportID: CastTransportID?
    private var namespaceMessageContinuations = [UUID: NamespaceMessageSubscription]()

    private struct NamespaceMessageSubscription {
        let namespace: CastNamespace?
        let continuation: AsyncStream<CastInboundMessage>.Continuation
    }

    init(
        device: CastDeviceDescriptor,
        connection: CastConnection,
        dispatcher: CastCommandDispatcher,
        media: CastMediaController,
        receiver: CastReceiverController,
        stateStore: CastSessionStateStore,
        statusProcessor: CastStatusMessageProcessor,
        inboundTransport: (any CastInboundMessageTransport)? = nil,
        heartbeatInterval: TimeInterval = 5,
        autoReconnect: Bool = true
    ) {
        self.device = device
        self.connection = connection
        self.dispatcher = dispatcher
        self.media = media
        self.receiver = receiver
        self.stateStore = stateStore
        self.statusProcessor = statusProcessor
        self.inboundTransport = inboundTransport
        self.heartbeatInterval = heartbeatInterval
        self.autoReconnect = autoReconnect
    }

    init(
        device: CastDeviceDescriptor,
        transport: any CastConnectionTransport & CastCommandTransport,
        configuration: CastConnectionConfiguration = .init()
    ) {
        let connection = CastConnection(configuration: configuration, transport: transport)
        let dispatcher = CastCommandDispatcher(transport: transport, defaultReplyTimeout: configuration.commandTimeout)
        let media = CastMediaController(dispatcher: dispatcher)
        let receiver = CastReceiverController(dispatcher: dispatcher)
        let stateStore = CastSessionStateStore()
        let statusProcessor = CastStatusMessageProcessor(
            stateStore: stateStore,
            dispatcher: dispatcher,
            mediaController: media
        )
        let inboundTransport = transport as? CastInboundMessageTransport

        self.init(
            device: device,
            connection: connection,
            dispatcher: dispatcher,
            media: media,
            receiver: receiver,
            stateStore: stateStore,
            statusProcessor: statusProcessor,
            inboundTransport: inboundTransport,
            heartbeatInterval: configuration.heartbeatInterval,
            autoReconnect: configuration.autoReconnect
        )
    }

    func connect() async throws {
        try await connection.connect()
        lastHeartbeatActivityAt = Date()
        startInboundLoopIfNeeded()
        try await bootstrapPlatformNamespaces()
        startHeartbeatLoopIfNeeded()
    }

    func disconnect(reason: CastDisconnectReason = .requested) async {
        inboundTask?.cancel()
        inboundTask = nil
        heartbeatTask?.cancel()
        heartbeatTask = nil
        heartbeatRecoveryTask?.cancel()
        heartbeatRecoveryTask = nil
        connectedApplicationTransportID = nil
        await connection.disconnect(reason: reason)
    }

    func reconnect() async throws {
        inboundTask?.cancel()
        inboundTask = nil
        heartbeatTask?.cancel()
        heartbeatTask = nil
        heartbeatRecoveryTask?.cancel()
        heartbeatRecoveryTask = nil
        connectedApplicationTransportID = nil
        try await connection.reconnect()
        lastHeartbeatActivityAt = Date()
        startInboundLoopIfNeeded()
        try await bootstrapPlatformNamespaces()
        startHeartbeatLoopIfNeeded()
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

    func namespaceMessages(namespace: CastNamespace? = nil) -> AsyncStream<CastInboundMessage> {
        let id = UUID()
        return AsyncStream { continuation in
            namespaceMessageContinuations[id] = .init(namespace: namespace, continuation: continuation)
            continuation.onTermination = { [id] _ in
                Task { await self.removeNamespaceMessageContinuation(id: id) }
            }
        }
    }

    @discardableResult
    func sendNamespaceMessage(
        namespace: CastNamespace,
        target: CastMessageTarget,
        payload: [String: JSONValue]
    ) async throws -> CastRequestID {
        try await dispatcher.send(namespace: namespace, target: target, payload: payload)
    }

    func sendNamespaceMessageUntracked(
        namespace: CastNamespace,
        target: CastMessageTarget,
        payload: [String: JSONValue]
    ) async throws {
        try await dispatcher.sendUntracked(namespace: namespace, target: target, payload: payload)
    }

    @discardableResult
    func applyInboundMessage(_ message: CastInboundMessage) async throws -> Bool {
        lastHeartbeatActivityAt = Date()
        let handledHeartbeat = try await handleHeartbeatMessage(message)
        let matchedPendingReply = try await dispatcher.consumeInboundMessage(message)
        let handledStatus = try await statusProcessor.apply(message)
        if handledStatus {
            try await synchronizeApplicationTransportBootstrapIfNeeded()
        }
        emitNamespaceMessageIfNeeded(message)
        return handledHeartbeat || matchedPendingReply || handledStatus
    }

    private func startInboundLoopIfNeeded() {
        guard inboundTask == nil, let inboundTransport else {
            return
        }

        let actor = self
        inboundTask = Task {
            let stream = await inboundTransport.inboundMessages()
            for await message in stream {
                do {
                    _ = try await actor.applyInboundMessage(message)
                } catch {
                    continue
                }
            }
        }
    }

    private func emitNamespaceMessageIfNeeded(_ message: CastInboundMessage) {
        guard message.route.namespace.isCoreChromecastNamespace == false else {
            return
        }

        for subscription in namespaceMessageContinuations.values {
            guard subscription.namespace == nil || subscription.namespace == message.route.namespace else {
                continue
            }
            subscription.continuation.yield(message)
        }
    }

    private func removeNamespaceMessageContinuation(id: UUID) {
        namespaceMessageContinuations[id] = nil
    }

    private func bootstrapPlatformNamespaces() async throws {
        connectedApplicationTransportID = nil
        try await dispatcher.sendUntracked(
            namespace: .connection,
            target: .platform,
            payload: CastWire.Connection.ConnectRequest()
        )
        _ = try await receiver.getStatus()
    }

    private func startHeartbeatLoopIfNeeded() {
        guard heartbeatTask == nil, heartbeatInterval > 0 else {
            return
        }

        let actor = self
        let interval = heartbeatInterval
        heartbeatTask = Task {
            while Task.isCancelled == false {
                let ns = UInt64(max(0, interval) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: ns)
                guard !Task.isCancelled else {
                    break
                }

                let timeoutWindow = max(interval * 3, 0.25)
                if await Date().timeIntervalSince(actor.heartbeatLastActivityDate()) > timeoutWindow {
                    await actor.scheduleHeartbeatRecoveryIfNeeded()
                    break
                }

                do {
                    try await actor.dispatcher.sendUntracked(
                        namespace: .heartbeat,
                        target: .platform,
                        payload: CastWire.Heartbeat.Message(type: .ping)
                    )
                } catch {
                    break
                }
            }
        }
    }

    private func synchronizeApplicationTransportBootstrapIfNeeded() async throws {
        let currentTransportID = await stateStore.receiverStatus()?.app?.transportID

        guard currentTransportID != connectedApplicationTransportID else {
            return
        }

        connectedApplicationTransportID = currentTransportID

        guard let currentTransportID else {
            return
        }

        try await dispatcher.sendUntracked(
            namespace: .connection,
            target: .transport(id: currentTransportID),
            payload: CastWire.Connection.ConnectRequest()
        )
        _ = try await media.getStatus()
    }

    private func heartbeatLastActivityDate() -> Date {
        lastHeartbeatActivityAt
    }

    private func scheduleHeartbeatRecoveryIfNeeded() {
        guard heartbeatRecoveryTask == nil else {
            return
        }

        let actor = self
        heartbeatRecoveryTask = Task {
            await actor.performHeartbeatRecovery()
            await actor.clearHeartbeatRecoveryTask()
        }
    }

    private func clearHeartbeatRecoveryTask() {
        heartbeatRecoveryTask = nil
    }

    private func performHeartbeatRecovery() async {
        inboundTask?.cancel()
        inboundTask = nil
        heartbeatTask?.cancel()
        heartbeatTask = nil
        connectedApplicationTransportID = nil

        await connection.disconnect(reason: .heartbeatTimeout)

        guard autoReconnect else {
            return
        }

        do {
            try await connection.connect()
            lastHeartbeatActivityAt = Date()
            startInboundLoopIfNeeded()
            try await bootstrapPlatformNamespaces()
            startHeartbeatLoopIfNeeded()
        } catch {
            // Connection actor already emitted error state/event.
        }
    }

    private func handleHeartbeatMessage(_ message: CastInboundMessage) async throws -> Bool {
        guard message.route.namespace == .heartbeat else {
            return false
        }

        guard let heartbeatMessage = try? CastMessageJSONCodec.decodePayload(
            CastWire.Heartbeat.Message.self,
            from: message.payloadUTF8
        ) else {
            return false
        }

        switch heartbeatMessage.type {
        case .ping:
            try await dispatcher.sendUntracked(
                namespace: .heartbeat,
                target: .platform,
                payload: CastWire.Heartbeat.Message(type: .pong)
            )
            lastHeartbeatActivityAt = Date()
            return true
        case .pong:
            lastHeartbeatActivityAt = Date()
            return true
        }
    }
}
