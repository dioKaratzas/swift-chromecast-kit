//
//  ChromecastKit
//  SPDX-License-Identifier: Apache-2.0
//  Copyright 2026 Dionysis Karatzas
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
    private let reconnectPolicy: CastSession.ReconnectPolicy
    private let stateRestorationPolicy: CastSession.StateRestorationPolicy
    private let observability: CastSession.Observability
    private let networkPathMonitor: (any CastNetworkPathMonitoring)?
    private let reconnectRandomUnit: @Sendable () -> Double
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
        reconnectPolicy: CastSession.ReconnectPolicy = .exponential(initialDelay: 1),
        stateRestorationPolicy: CastSession.StateRestorationPolicy = .receiverAndMedia,
        observability: CastSession.Observability = .disabled,
        networkPathMonitor: (any CastNetworkPathMonitoring)? = nil,
        reconnectRandomUnit: @escaping @Sendable () -> Double = { Double.random(in: 0 ... 1) }
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
        self.reconnectPolicy = reconnectPolicy
        self.stateRestorationPolicy = stateRestorationPolicy
        self.observability = observability
        self.networkPathMonitor = networkPathMonitor
        self.reconnectRandomUnit = reconnectRandomUnit
    }

    init(
        device: CastDeviceDescriptor,
        transport: any CastConnectionTransport & CastCommandTransport,
        configuration: CastConnection.Configuration = .init(),
        observability: CastSession.Observability = .disabled,
        networkPathMonitor: (any CastNetworkPathMonitoring)? = nil,
        reconnectRandomUnit: @escaping @Sendable () -> Double = { Double.random(in: 0 ... 1) }
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
            reconnectPolicy: configuration.reconnectPolicy,
            stateRestorationPolicy: configuration.stateRestorationPolicy,
            observability: observability,
            networkPathMonitor: networkPathMonitor ?? {
                guard configuration.reconnectPolicy.waitsForReachableNetworkPath else {
                    return nil
                }
                return CastSystemNetworkPathMonitor()
            }(),
            reconnectRandomUnit: reconnectRandomUnit
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
        if handledStatus, stateRestorationPolicy == .receiverAndMedia {
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
                    await actor.emitInboundRuntimeError(
                        code: "inbound_message_ignored",
                        message: "Ignoring inbound message after processing failure",
                        error: error,
                        namespace: message.route.namespace
                    )
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
        let traceID = UUID()
        emitTrace(
            name: "cast.session.recovery",
            phase: .begin,
            traceID: traceID,
            attributes: ["reason": reason.rawValue]
        )

        inboundTask?.cancel()
        inboundTask = nil
        heartbeatTask?.cancel()
        heartbeatTask = nil
        connectedApplicationTransportID = nil
        await dispatcher.failAllPendingReplies(with: CastError.disconnected)

        await connection.disconnect(reason: reason)

        guard autoReconnect else {
            emitRecoveryLog(
                level: .info,
                code: "recovery_skipped_auto_reconnect_disabled",
                message: "Skipping recovery because autoReconnect is disabled",
                reason: reason
            )
            emitRecoveryTraceEnd(traceID: traceID, outcome: "disabled")
            return
        }

        emitRecoveryLog(
            level: .info,
            code: "recovery_started",
            message: "Starting reconnect recovery loop",
            reason: reason
        )
        emitReconnectMetric(
            name: "cast.session.recovery.started",
            value: 1,
            unit: "count",
            dimensions: ["reason": reason.rawValue]
        )

        let recoveryStartedAt = Date()
        var attempt = 1
        while Task.isCancelled == false {
            if let maxAttempts = reconnectPolicy.maxAttempts, attempt > maxAttempts {
                emitRecoveryLog(
                    level: .warning,
                    code: "reconnect_give_up",
                    message: "Reconnect attempt cap reached",
                    reason: reason,
                    attempt: attempt - 1,
                    metadata: ["maxAttempts": "\(maxAttempts)"]
                )
                emitReconnectMetric(
                    name: "cast.session.reconnect.give_up",
                    value: 1,
                    unit: "count",
                    dimensions: ["reason": reason.rawValue]
                )
                emitRecoveryTraceEnd(traceID: traceID, outcome: "max_attempts_reached", attempts: attempt - 1)
                return
            }

            if attempt > 1 {
                let delay = reconnectPolicy.retryDelay(
                    forAttempt: attempt - 1,
                    randomUnit: reconnectRandomUnit()
                )
                if delay > 0 {
                    emitReconnectMetric(
                        name: "cast.session.reconnect.delay",
                        value: delay,
                        unit: "seconds",
                        attempt: attempt
                    )
                    do {
                        try await CastTaskTiming.sleep(for: delay)
                    } catch {
                        emitRecoveryTraceEnd(traceID: traceID, outcome: "cancelled", attempts: attempt - 1)
                        return
                    }
                }
            }

            if reconnectPolicy.waitsForReachableNetworkPath, let networkPathMonitor {
                let currentStatus = await networkPathMonitor.status()
                if currentStatus != .satisfied {
                    emitRecoveryLog(
                        level: .info,
                        code: "network_wait_started",
                        message: "Waiting for reachable network path before reconnect",
                        reason: reason,
                        attempt: attempt,
                        metadata: ["status": currentStatus.rawValue]
                    )
                    let reachable = await networkPathMonitor.waitForReachable(
                        timeout: reconnectPolicy.networkPathWaitTimeout
                    )
                    if reachable == false {
                        emitRecoveryLog(
                            level: .warning,
                            code: "network_wait_timeout",
                            message: "Timed out waiting for reachable network path",
                            reason: reason,
                            attempt: attempt
                        )
                        emitReconnectMetric(
                            name: "cast.session.reconnect.network_wait_timeout",
                            value: 1,
                            unit: "count",
                            attempt: attempt
                        )
                        attempt += 1
                        continue
                    }
                }
            }

            let attemptStartedAt = Date()
            emitReconnectMetric(
                name: "cast.session.reconnect.attempt",
                value: 1,
                unit: "count",
                attempt: attempt
            )
            do {
                try await connection.reconnect()
                do {
                    try await finishPostConnectBootstrap()
                    emitRecoveryLog(
                        level: .info,
                        code: "reconnect_success",
                        message: "Reconnect recovery succeeded",
                        reason: reason,
                        attempt: attempt
                    )
                    emitReconnectMetric(
                        name: "cast.session.reconnect.success",
                        value: 1,
                        unit: "count",
                        attempt: attempt
                    )
                    emitReconnectMetric(
                        name: "cast.session.reconnect.attempt_duration",
                        value: Date().timeIntervalSince(attemptStartedAt),
                        unit: "seconds",
                        attempt: attempt
                    )
                    emitReconnectMetric(
                        name: "cast.session.recovery.duration",
                        value: Date().timeIntervalSince(recoveryStartedAt),
                        unit: "seconds",
                        dimensions: ["attempts": "\(attempt)"]
                    )
                    emitRecoveryTraceEnd(traceID: traceID, outcome: "success", attempts: attempt)
                    return
                } catch {
                    await handleBootstrapFailure(error)
                }
            } catch {
                emitRecoveryLog(
                    level: .warning,
                    code: "reconnect_attempt_failed",
                    message: "Reconnect attempt failed",
                    reason: reason,
                    attempt: attempt,
                    metadata: ["error": String(describing: error)]
                )
                emitReconnectMetric(
                    name: "cast.session.reconnect.failure",
                    value: 1,
                    unit: "count",
                    attempt: attempt
                )
                // Connection actor already emitted error state/event.
            }
            attempt += 1
        }

        emitRecoveryTraceEnd(traceID: traceID, outcome: "cancelled")
    }

    private func handleInboundTransportEvent(_ event: CastInboundTransportEvent) async {
        switch event {
        case let .utf8(message):
            do {
                _ = try await applyInboundMessage(message)
            } catch {
                emitInboundRuntimeError(
                    code: "inbound_event_ignored",
                    message: "Ignoring inbound transport event after processing failure",
                    error: error,
                    namespace: message.route.namespace
                )
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

    /// Emits runtime-boundary diagnostics for inbound message errors that are intentionally swallowed.
    ///
    /// These errors are non-fatal for the session loop, but are still surfaced through observability hooks
    /// to aid debugging and production telemetry.
    private func emitInboundRuntimeError(
        code: String,
        message: String,
        error: any Error,
        namespace: CastNamespace? = nil
    ) {
        var metadata = [String: String]()
        metadata["error"] = String(describing: error)
        if let namespace {
            metadata["namespace"] = namespace.rawValue
        }
        emitLog(level: .warning, code: code, message: message, metadata: metadata)

        var dimensions = ["code": code]
        if let namespace {
            dimensions["namespace"] = namespace.rawValue
        }
        emitMetric(name: "cast.session.runtime.inbound_error", value: 1, unit: "count", dimensions: dimensions)
    }

    private func emitRecoveryLog(
        level: CastSession.LogEvent.Level,
        code: String,
        message: String,
        reason: CastConnection.DisconnectReason? = nil,
        attempt: Int? = nil,
        metadata: [String: String] = [:]
    ) {
        var mergedMetadata = metadata
        if let reason {
            mergedMetadata["reason"] = reason.rawValue
        }
        if let attempt {
            mergedMetadata["attempt"] = "\(attempt)"
        }
        emitLog(level: level, code: code, message: message, metadata: mergedMetadata)
    }

    private func emitReconnectMetric(
        name: String,
        value: Double,
        unit: String,
        attempt: Int? = nil,
        dimensions: [String: String] = [:]
    ) {
        var mergedDimensions = dimensions
        if let attempt {
            mergedDimensions["attempt"] = "\(attempt)"
        }
        emitMetric(name: name, value: value, unit: unit, dimensions: mergedDimensions)
    }

    private func emitRecoveryTraceEnd(traceID: UUID, outcome: String, attempts: Int? = nil) {
        var attributes = [String: String]()
        attributes["outcome"] = outcome
        if let attempts {
            attributes["attempts"] = "\(attempts)"
        }
        emitTrace(name: "cast.session.recovery", phase: .end, traceID: traceID, attributes: attributes)
    }

    private func emitLog(
        level: CastSession.LogEvent.Level,
        code: String,
        message: String,
        metadata: [String: String] = [:]
    ) {
        observability.onLog?(
            .init(
                level: level,
                code: code,
                message: message,
                metadata: metadata
            )
        )
    }

    private func emitMetric(
        name: String,
        value: Double,
        unit: String,
        dimensions: [String: String] = [:]
    ) {
        observability.onMetric?(
            .init(
                name: name,
                value: value,
                unit: unit,
                dimensions: dimensions
            )
        )
    }

    private func emitTrace(
        name: String,
        phase: CastSession.TraceEvent.Phase,
        traceID: UUID,
        attributes: [String: String] = [:]
    ) {
        observability.onTrace?(
            .init(
                name: name,
                phase: phase,
                traceID: traceID,
                attributes: attributes
            )
        )
    }
}
