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
    nonisolated let multizone: CastMultizoneController

    private let connection: CastConnection
    private let stateStore: CastSessionStateStore
    private let statusProcessor: CastStatusMessageProcessor
    private let dispatcher: CastCommandDispatcher
    private let inboundTransport: (any CastInboundMessageTransport)?
    private let inboundEventTransport: (any CastInboundEventTransport)?
    private let heartbeatInterval: TimeInterval
    private let autoReconnect: Bool
    private let reconnectRetryDelay: TimeInterval
    private var inboundTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var recoveryTask: Task<Void, Never>?
    private var lastHeartbeatActivityAt = Date()
    private var connectedApplicationTransportID: CastTransportID?
    private var namespaceMessageContinuations = [UUID: NamespaceMessageSubscription]()
    private var namespaceEnvelopeContinuations = [UUID: NamespaceEnvelopeSubscription]()

    private struct NamespaceMessageSubscription {
        let namespace: CastNamespace?
        let continuation: AsyncStream<CastInboundMessage>.Continuation
    }

    private struct NamespaceEnvelopeSubscription {
        let namespace: CastNamespace?
        let continuation: AsyncStream<CastNamespaceInboundEvent>.Continuation
    }

    enum CastNamespaceInboundEvent: Sendable, Hashable {
        case utf8(CastInboundMessage)
        case binary(CastInboundBinaryMessage)
    }

    init(
        device: CastDeviceDescriptor,
        connection: CastConnection,
        dispatcher: CastCommandDispatcher,
        media: CastMediaController,
        receiver: CastReceiverController,
        multizone: CastMultizoneController,
        stateStore: CastSessionStateStore,
        statusProcessor: CastStatusMessageProcessor,
        inboundTransport: (any CastInboundMessageTransport)? = nil,
        inboundEventTransport: (any CastInboundEventTransport)? = nil,
        heartbeatInterval: TimeInterval = 5,
        autoReconnect: Bool = true,
        reconnectRetryDelay: TimeInterval = 1
    ) {
        self.device = device
        self.connection = connection
        self.dispatcher = dispatcher
        self.media = media
        self.receiver = receiver
        self.multizone = multizone
        self.stateStore = stateStore
        self.statusProcessor = statusProcessor
        self.inboundTransport = inboundTransport
        self.inboundEventTransport = inboundEventTransport
        self.heartbeatInterval = heartbeatInterval
        self.autoReconnect = autoReconnect
        self.reconnectRetryDelay = reconnectRetryDelay
    }

    init(
        device: CastDeviceDescriptor,
        transport: any CastConnectionTransport & CastCommandTransport,
        configuration: CastConnection.Configuration = .init()
    ) {
        let connection = CastConnection(configuration: configuration, transport: transport)
        let dispatcher = CastCommandDispatcher(transport: transport, defaultReplyTimeout: configuration.commandTimeout)
        let media = CastMediaController(dispatcher: dispatcher)
        let receiver = CastReceiverController(dispatcher: dispatcher)
        let stateStore = CastSessionStateStore()
        let multizone = CastMultizoneController(dispatcher: dispatcher, stateStore: stateStore)
        let statusProcessor = CastStatusMessageProcessor(
            stateStore: stateStore,
            dispatcher: dispatcher,
            mediaController: media
        )
        let inboundTransport = transport as? CastInboundMessageTransport
        let inboundEventTransport = transport as? CastInboundEventTransport

        self.init(
            device: device,
            connection: connection,
            dispatcher: dispatcher,
            media: media,
            receiver: receiver,
            multizone: multizone,
            stateStore: stateStore,
            statusProcessor: statusProcessor,
            inboundTransport: inboundTransport,
            inboundEventTransport: inboundEventTransport,
            heartbeatInterval: configuration.heartbeatInterval,
            autoReconnect: configuration.autoReconnect,
            reconnectRetryDelay: configuration.reconnectRetryDelay
        )
    }

    func connect() async throws {
        try await connection.connect()
        do {
            try await finishPostConnectBootstrap()
        } catch {
            await handleBootstrapFailure(error)
            throw error
        }
    }

    func disconnect(reason: CastConnection.DisconnectReason = .requested) async {
        inboundTask?.cancel()
        inboundTask = nil
        heartbeatTask?.cancel()
        heartbeatTask = nil
        recoveryTask?.cancel()
        recoveryTask = nil
        connectedApplicationTransportID = nil
        await dispatcher.failAllPendingReplies(with: CastError.disconnected)
        await connection.disconnect(reason: reason)
    }

    func reconnect() async throws {
        inboundTask?.cancel()
        inboundTask = nil
        heartbeatTask?.cancel()
        heartbeatTask = nil
        recoveryTask?.cancel()
        recoveryTask = nil
        connectedApplicationTransportID = nil
        try await connection.reconnect()
        do {
            try await finishPostConnectBootstrap()
        } catch {
            await handleBootstrapFailure(error)
            throw error
        }
    }

    func connectionState() async -> CastConnection.State {
        await connection.state()
    }

    func connectionEvents() async -> AsyncStream<CastConnection.Event> {
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

    func multizoneStatus() async -> CastMultizoneStatus? {
        await stateStore.multizoneStatus()
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

    func namespaceEvents(namespace: CastNamespace? = nil) -> AsyncStream<CastNamespaceInboundEvent> {
        let id = UUID()
        return AsyncStream { continuation in
            namespaceEnvelopeContinuations[id] = .init(namespace: namespace, continuation: continuation)
            continuation.onTermination = { [id] _ in
                Task { await self.removeNamespaceEnvelopeContinuation(id: id) }
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

    func sendNamespaceMessageAndAwaitReply(
        namespace: CastNamespace,
        target: CastMessageTarget,
        payload: [String: JSONValue],
        timeout: TimeInterval? = nil
    ) async throws -> CastInboundMessage {
        try await dispatcher.sendAndAwaitReply(
            namespace: namespace,
            target: target,
            payload: payload,
            timeout: timeout
        )
    }

    func sendNamespaceMessageUntracked(
        namespace: CastNamespace,
        target: CastMessageTarget,
        payload: [String: JSONValue]
    ) async throws {
        try await dispatcher.sendUntracked(namespace: namespace, target: target, payload: payload)
    }

    @discardableResult
    func sendBinaryNamespaceMessage(
        namespace: CastNamespace,
        target: CastMessageTarget,
        payload: Data
    ) async throws -> CastRequestID {
        try await dispatcher.sendBinary(namespace: namespace, target: target, payload: payload)
    }

    func sendBinaryNamespaceMessageUntracked(
        namespace: CastNamespace,
        target: CastMessageTarget,
        payload: Data
    ) async throws {
        try await dispatcher.sendBinaryUntracked(namespace: namespace, target: target, payload: payload)
    }

    @discardableResult
    func applyInboundMessage(_ message: CastInboundMessage) async throws -> Bool {
        lastHeartbeatActivityAt = Date()
        let handledHeartbeat = try await handleHeartbeatMessage(message)
        let matchedPendingReply = try await dispatcher.consumeInboundMessage(message)
        let handledStatus = try await statusProcessor.apply(message)
        if handledStatus {
            do {
                try await synchronizeApplicationTransportBootstrapIfNeeded()
            } catch {
                await handleBackgroundRuntimeFailure(error, recoveryReason: .networkError)
            }
        }
        emitNamespaceMessageIfNeeded(message)
        return handledHeartbeat || matchedPendingReply || handledStatus
    }

    private func startInboundLoopIfNeeded() {
        guard inboundTask == nil else {
            return
        }

        let actor = self
        if let inboundEventTransport {
            inboundTask = Task {
                let stream = await inboundEventTransport.inboundEvents()
                for await event in stream {
                    await actor.handleInboundTransportEvent(event)
                }
            }
            return
        }

        guard let inboundTransport else {
            return
        }

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

        for subscription in namespaceEnvelopeContinuations.values {
            guard subscription.namespace == nil || subscription.namespace == message.route.namespace else {
                continue
            }
            subscription.continuation.yield(.utf8(message))
        }

        for subscription in namespaceMessageContinuations.values {
            guard subscription.namespace == nil || subscription.namespace == message.route.namespace else {
                continue
            }
            subscription.continuation.yield(message)
        }
    }

    private func emitNamespaceBinaryMessageIfNeeded(_ message: CastInboundBinaryMessage) {
        guard message.route.namespace.isCoreChromecastNamespace == false else {
            return
        }

        for subscription in namespaceEnvelopeContinuations.values {
            guard subscription.namespace == nil || subscription.namespace == message.route.namespace else {
                continue
            }
            subscription.continuation.yield(.binary(message))
        }
    }

    private func removeNamespaceEnvelopeContinuation(id: UUID) {
        namespaceEnvelopeContinuations[id] = nil
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
        _ = try await dispatcher.sendAndAwaitReply(
            namespace: .receiver,
            target: .platform,
            payload: CastReceiverPayloadBuilder.getStatus()
        )
        if device.capabilities.contains(.group) || device.capabilities.contains(.multizone) {
            _ = try? await dispatcher.send(
                namespace: .multizone,
                target: .platform,
                payload: CastMultizonePayloadBuilder.getStatus()
            )
            _ = try? await dispatcher.send(
                namespace: .multizone,
                target: .platform,
                payload: CastMultizonePayloadBuilder.getCastingGroups()
            )
        }
    }

    private func startHeartbeatLoopIfNeeded() {
        guard heartbeatTask == nil, heartbeatInterval > 0 else {
            return
        }

        let actor = self
        let interval = heartbeatInterval
        heartbeatTask = Task {
            while Task.isCancelled == false {
                do {
                    try await CastTaskTiming.sleep(for: interval)
                } catch is CancellationError {
                    break
                } catch {
                    break
                }
                guard !Task.isCancelled else {
                    break
                }

                let timeoutWindow = max(interval * 3, 0.25)
                if await Date().timeIntervalSince(actor.heartbeatLastActivityDate()) > timeoutWindow {
                    await actor.scheduleRecoveryIfNeeded(reason: .heartbeatTimeout)
                    break
                }

                do {
                    try await actor.dispatcher.sendUntracked(
                        namespace: .heartbeat,
                        target: .platform,
                        payload: CastWire.Heartbeat.Message(type: .ping)
                    )
                } catch {
                    await actor.handleBackgroundRuntimeFailure(error, recoveryReason: .networkError)
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
        _ = try await dispatcher.send(
            namespace: .media,
            target: .transport(id: currentTransportID),
            payload: CastMediaPayloadBuilder.getStatus()
        )
    }

    private func heartbeatLastActivityDate() -> Date {
        lastHeartbeatActivityAt
    }

    private func scheduleRecoveryIfNeeded(reason: CastConnection.DisconnectReason) {
        guard recoveryTask == nil else {
            return
        }

        let actor = self
        recoveryTask = Task {
            await actor.performRecovery(reason: reason)
            await actor.clearRecoveryTask()
        }
    }

    private func clearRecoveryTask() {
        recoveryTask = nil
    }

    private func performRecovery(reason: CastConnection.DisconnectReason) async {
        inboundTask?.cancel()
        inboundTask = nil
        heartbeatTask?.cancel()
        heartbeatTask = nil
        connectedApplicationTransportID = nil
        await dispatcher.failAllPendingReplies(with: CastError.disconnected)

        await connection.disconnect(reason: reason)

        guard autoReconnect else {
            return
        }

        while Task.isCancelled == false {
            do {
                try await connection.connect()
                do {
                    try await finishPostConnectBootstrap()
                    return
                } catch {
                    await handleBootstrapFailure(error)
                }
            } catch {
                // Connection actor already emitted error state/event.
            }

            guard reconnectRetryDelay > 0 else {
                continue
            }

            do {
                try await CastTaskTiming.sleep(for: reconnectRetryDelay)
            } catch {
                return
            }
        }
    }

    private func handleInboundTransportEvent(_ event: CastInboundTransportEvent) async {
        switch event {
        case let .utf8(message):
            do {
                _ = try await applyInboundMessage(message)
            } catch {
                // Ignore malformed/unsupported messages at runtime boundary.
            }
        case let .binary(message):
            lastHeartbeatActivityAt = Date()
            emitNamespaceBinaryMessageIfNeeded(message)
        case .closed:
            scheduleRecoveryIfNeeded(reason: .remoteClosed)
        case let .failure(error):
            await connection.reportRuntimeError(error)
            if case .disconnected = error {
                scheduleRecoveryIfNeeded(reason: .remoteClosed)
            } else {
                scheduleRecoveryIfNeeded(reason: .networkError)
            }
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

    private func finishPostConnectBootstrap() async throws {
        lastHeartbeatActivityAt = Date()
        startInboundLoopIfNeeded()
        try await bootstrapPlatformNamespaces()
        startHeartbeatLoopIfNeeded()
    }

    private func handleBootstrapFailure(_ error: any Error) async {
        let castError = (error as? CastError) ?? .connectionFailed(String(describing: error))
        inboundTask?.cancel()
        inboundTask = nil
        heartbeatTask?.cancel()
        heartbeatTask = nil
        connectedApplicationTransportID = nil
        await dispatcher.failAllPendingReplies(with: castError)
        await connection.reportRuntimeError(castError)
        await connection.disconnect(reason: .networkError)
    }

    private func handleBackgroundRuntimeFailure(
        _ error: any Error,
        recoveryReason: CastConnection.DisconnectReason
    ) async {
        let castError = (error as? CastError) ?? .connectionFailed(String(describing: error))
        await dispatcher.failAllPendingReplies(with: castError)
        await connection.reportRuntimeError(castError)
        scheduleRecoveryIfNeeded(reason: recoveryReason)
    }
}
