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
    // MARK: Public State

    public nonisolated let device: CastDeviceDescriptor
    public nonisolated let media: CastMediaController
    public nonisolated let receiver: CastReceiverController
    public nonisolated let multizone: CastMultizoneController

    // MARK: Private State

    private let runtime: CastSessionRuntime
    private var namespaceHandlers = [NamespaceHandlerToken: any CastSessionNamespaceHandler]()
    private var registeredControllers = [ControllerToken: any CastSessionController]()
    private var namespaceHandlerFanoutTask: Task<Void, Never>?
    private var controllerConnectionFanoutTask: Task<Void, Never>?
    private var controllerStateFanoutTask: Task<Void, Never>?

    // MARK: Initialization

    /// Creates a Cast session for a discovered device using the built-in Cast v2 TLS transport.
    public init(
        device: CastDeviceDescriptor,
        configuration: Configuration = .init()
    ) {
        let transport = NWTLSCastV2Transport(device: device)
        let runtime = CastSessionRuntime(
            device: device,
            transport: transport,
            configuration: configuration
        )

        self.device = device
        self.runtime = runtime
        self.media = runtime.media
        self.receiver = runtime.receiver
        self.multizone = runtime.multizone
    }

    // MARK: Connection Lifecycle

    /// Establishes the Cast transport connection.
    public func connect() async throws {
        try await runtime.connect()
    }

    /// Establishes the Cast transport connection when the session is not already connected.
    public func connectIfNeeded() async throws {
        switch await runtime.connectionState() {
        case .connected, .connecting, .reconnecting:
            return
        case .disconnected, .failed:
            try await runtime.connect()
        }
    }

    /// Closes the Cast transport connection.
    public func disconnect(reason: DisconnectReason = .requested) async {
        await runtime.disconnect(reason: reason)
    }

    /// Reconnects the Cast transport connection.
    public func reconnect() async throws {
        try await runtime.reconnect()
    }

    /// Launches the Google Cast Default Media Receiver app.
    @discardableResult
    public func launchDefaultMediaReceiver() async throws -> CastRequestID {
        try await receiver.launch(appID: .defaultMediaReceiver)
    }

    /// Launches the YouTube receiver app.
    ///
    /// Playback/control beyond receiver-level status requires app-specific protocol support.
    @discardableResult
    public func launchYouTube() async throws -> CastRequestID {
        try await receiver.launch(appID: .youtube)
    }

    /// Requests fresh receiver/media/multizone status where available.
    ///
    /// Receiver status is required and throws on failure. Media and multizone refreshes are best-effort
    /// because they depend on the active app and receiver capabilities.
    public func refreshStatuses() async throws {
        _ = try await receiver.getStatus()
        _ = try? await media.getStatus()
        _ = try? await multizone.getStatus()
        _ = try? await multizone.getCastingGroups()
    }

    /// Waits until the receiver reports a specific app as active and ready (app transport connected).
    ///
    /// The method polls receiver status until the app is active with a non-`nil` transport ID, then
    /// returns the reported running app. It returns `nil` on timeout.
    public func waitForApp(
        _ appID: CastAppID,
        timeout: TimeInterval = 6,
        pollInterval: TimeInterval = 0.25
    ) async throws -> CastRunningApp? {
        try await waitForCondition(timeout: timeout, pollInterval: pollInterval) { session in
            _ = try? await session.receiver.getStatus()
            guard let app = await session.receiverStatus()?.app, app.appID == appID, app.transportID != nil else {
                return nil
            }
            return app
        }
    }

    /// Waits until the active receiver app reports support for a specific namespace.
    ///
    /// When `appID` is provided, the active app must also match that app ID.
    /// Returns `true` when the namespace is reported before timeout, otherwise `false`.
    public func waitForNamespace(
        _ namespace: CastNamespace,
        inApp appID: CastAppID? = nil,
        timeout: TimeInterval = 6,
        pollInterval: TimeInterval = 0.25
    ) async throws -> Bool {
        let result: Bool? = try await waitForCondition(timeout: timeout, pollInterval: pollInterval) { session in
            _ = try? await session.receiver.getStatus()
            guard let app = await session.receiverStatus()?.app else {
                return nil
            }
            if let appID, app.appID != appID {
                return nil
            }
            return app.namespaces.contains(namespace.rawValue) ? true : nil
        }
        return result == true
    }

    // MARK: Session State / Streams

    /// Returns the current connection lifecycle state.
    public func connectionState() async -> ConnectionState {
        await runtime.connectionState()
    }

    /// Emits connection lifecycle events for this session.
    public func connectionEvents() async -> AsyncStream<ConnectionEvent> {
        await runtime.connectionEvents()
    }

    /// Returns the latest known receiver status, if any.
    public func receiverStatus() async -> CastReceiverStatus? {
        await runtime.receiverStatus()
    }

    /// Returns the latest known media status, if any.
    public func mediaStatus() async -> CastMediaStatus? {
        await runtime.mediaStatus()
    }

    /// Returns the latest known multizone/group status, if any.
    public func multizoneStatus() async -> CastMultizoneStatus? {
        await runtime.multizoneStatus()
    }

    /// Returns the latest known receiver/media status snapshot.
    public func snapshot() async -> StateSnapshot {
        await runtime.snapshot().publicValue
    }

    /// Emits session status updates as receiver/media statuses change.
    public func stateEvents() async -> AsyncStream<StateEvent> {
        let coreStream = await runtime.stateEvents()
        return Self.mapStream(coreStream) { $0.publicValue }
    }

    // MARK: Custom Namespace Messaging

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

    /// Sends a JSON object on a Cast namespace and waits for a correlated reply (`requestId`).
    ///
    /// Cast protocol error replies are mapped to `CastError` and thrown.
    public func sendAndAwaitReply(
        namespace: CastNamespace,
        target: NamespaceTarget = .currentApplication,
        payload: [String: JSONValue],
        timeout: TimeInterval? = nil
    ) async throws -> NamespaceMessage {
        let reply = try await runtime.sendNamespaceMessageAndAwaitReply(
            namespace: namespace,
            target: target.coreValue,
            payload: payload,
            timeout: timeout
        )
        return reply.publicNamespaceMessage
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

    /// Sends a binary payload on a Cast namespace and injects a `requestId` by editing JSON payload bytes.
    ///
    /// Use this only for namespaces that define binary payloads. If the payload is not a JSON object
    /// and you do not want request correlation fields injected, prefer `sendBinaryUntracked`.
    @discardableResult
    public func sendBinary(
        namespace: CastNamespace,
        target: NamespaceTarget = .currentApplication,
        payload: Data
    ) async throws -> CastRequestID {
        try await runtime.sendBinaryNamespaceMessage(
            namespace: namespace,
            target: target.coreValue,
            payload: payload
        )
    }

    /// Sends a binary payload on a Cast namespace without injecting a `requestId`.
    public func sendBinaryUntracked(
        namespace: CastNamespace,
        target: NamespaceTarget = .currentApplication,
        payload: Data
    ) async throws {
        try await runtime.sendBinaryNamespaceMessageUntracked(
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
        return Self.mapStream(coreStream) { $0.publicNamespaceMessage }
    }

    /// Emits inbound custom namespace messages (UTF-8 or binary).
    ///
    /// This low-level API is useful for advanced integrations and app-specific protocols.
    public func namespaceEvents(_ namespace: CastNamespace? = nil) async -> AsyncStream<NamespaceEvent> {
        let coreStream = await runtime.namespaceEvents(namespace: namespace)
        return Self.mapStream(coreStream) { $0.publicNamespaceEvent }
    }

    /// Registers a custom namespace event handler.
    ///
    /// Handlers are invoked for inbound custom namespace events while the session is alive.
    /// Use `unregisterNamespaceHandler(_:)` to remove a handler later.
    @discardableResult
    public func registerNamespaceHandler(
        _ handler: any CastSessionNamespaceHandler
    ) -> NamespaceHandlerToken {
        let token = NamespaceHandlerToken(rawValue: UUID())
        namespaceHandlers[token] = handler
        startNamespaceHandlerFanoutIfNeeded()
        return token
    }

    /// Registers a higher-level session controller with lifecycle callbacks and namespace handling.
    ///
    /// The controller will receive:
    /// - custom namespace events (via `CastSessionNamespaceHandler`)
    /// - session connection events
    /// - session state events
    ///
    /// Use `unregisterController(_:)` to detach it later.
    @discardableResult
    public func registerController(
        _ controller: any CastSessionController
    ) async -> ControllerToken {
        let token = ControllerToken(rawValue: UUID())
        namespaceHandlers[token.namespaceHandlerToken] = controller
        registeredControllers[token] = controller
        startNamespaceHandlerFanoutIfNeeded()
        await startControllerFanoutIfNeeded()
        await controller.didRegister(in: self)
        return token
    }

    /// Registers multiple session controllers and returns their registry tokens in the same order.
    @discardableResult
    public func registerControllers(
        _ controllers: [any CastSessionController]
    ) async -> [ControllerToken] {
        var tokens = [ControllerToken]()
        tokens.reserveCapacity(controllers.count)
        for controller in controllers {
            let token = await registerController(controller)
            tokens.append(token)
        }
        return tokens
    }

    /// Unregisters a previously registered custom namespace event handler.
    ///
    /// If the token belongs to a controller registered with `registerController(_:)`, this also
    /// detaches the controller and schedules its `willUnregister(from:)` callback.
    /// Prefer `unregisterController(_:)` when you know the token is a controller token.
    public func unregisterNamespaceHandler(_ token: NamespaceHandlerToken) {
        if let controller = registeredControllers.removeValue(forKey: token.controllerToken) {
            namespaceHandlers[token] = nil
            stopNamespaceHandlerFanoutIfNeeded()
            stopControllerFanoutIfNeeded()

            let session = self
            Task {
                await controller.willUnregister(from: session)
            }
            return
        }

        namespaceHandlers[token] = nil
        stopNamespaceHandlerFanoutIfNeeded()
    }

    /// Unregisters a controller via the namespace-handler removal API.
    ///
    /// This preserves the same "schedule `willUnregister` and return immediately" behavior as
    /// `unregisterNamespaceHandler(_:)` for namespace handler tokens.
    public func unregisterNamespaceHandler(_ token: ControllerToken) {
        unregisterNamespaceHandler(token.namespaceHandlerToken)
    }

    /// Unregisters a previously registered `CastSessionController`.
    public func unregisterController(_ token: ControllerToken) async {
        if let controller = registeredControllers.removeValue(forKey: token) {
            await controller.willUnregister(from: self)
        }
        namespaceHandlers[token.namespaceHandlerToken] = nil
        stopNamespaceHandlerFanoutIfNeeded()
        stopControllerFanoutIfNeeded()
    }

    /// Unregisters multiple previously registered session controllers.
    public func unregisterControllers(_ tokens: [ControllerToken]) async {
        for token in tokens {
            await unregisterController(token)
        }
    }

    /// Removes all registered custom namespace handlers and session controllers.
    public func removeAllNamespaceHandlers() {
        let controllers = Array(registeredControllers.values)
        registeredControllers.removeAll(keepingCapacity: false)
        namespaceHandlers.removeAll(keepingCapacity: false)
        stopNamespaceHandlerFanoutIfNeeded(force: true)
        stopControllerFanoutIfNeeded(force: true)
        if controllers.isEmpty == false {
            let session = self
            Task {
                for controller in controllers {
                    await controller.willUnregister(from: session)
                }
            }
        }
    }

    // MARK: Internal Initialization

    init(runtime: CastSessionRuntime) {
        self.device = runtime.device
        self.runtime = runtime
        self.media = runtime.media
        self.receiver = runtime.receiver
        self.multizone = runtime.multizone
    }

    // MARK: Private Helpers

    private func startNamespaceHandlerFanoutIfNeeded() {
        guard namespaceHandlerFanoutTask == nil, namespaceHandlers.isEmpty == false else {
            return
        }

        let runtime = self.runtime
        let session = self
        namespaceHandlerFanoutTask = Task {
            let stream = await runtime.namespaceEvents()
            for await coreEvent in stream {
                await session.dispatchNamespaceHandlerEvent(coreEvent.publicNamespaceEvent)
            }
        }
    }

    private func stopNamespaceHandlerFanoutIfNeeded(force: Bool = false) {
        guard force || namespaceHandlers.isEmpty else {
            return
        }
        namespaceHandlerFanoutTask?.cancel()
        namespaceHandlerFanoutTask = nil
    }

    private func startControllerFanoutIfNeeded() async {
        guard registeredControllers.isEmpty == false else {
            return
        }

        if controllerConnectionFanoutTask == nil {
            let runtime = self.runtime
            let session = self
            let stream = await runtime.connectionEvents()
            controllerConnectionFanoutTask = Task {
                for await event in stream {
                    await session.dispatchControllerConnectionEvent(event)
                }
            }
        }

        if controllerStateFanoutTask == nil {
            let runtime = self.runtime
            let session = self
            let stream = await runtime.stateEvents()
            controllerStateFanoutTask = Task {
                for await event in stream {
                    await session.dispatchControllerStateEvent(event.publicValue)
                }
            }
        }
    }

    private func stopControllerFanoutIfNeeded(force: Bool = false) {
        guard force || registeredControllers.isEmpty else {
            return
        }
        controllerConnectionFanoutTask?.cancel()
        controllerConnectionFanoutTask = nil
        controllerStateFanoutTask?.cancel()
        controllerStateFanoutTask = nil
    }

    private func dispatchNamespaceHandlerEvent(_ event: NamespaceEvent) async {
        guard namespaceHandlers.isEmpty == false else {
            return
        }

        let handlers = Array(namespaceHandlers.values)
        for handler in handlers {
            guard handler.namespace == nil || handler.namespace == event.namespace else {
                continue
            }
            await handler.handle(event: event, in: self)
        }
    }

    private func dispatchControllerConnectionEvent(_ event: ConnectionEvent) async {
        guard registeredControllers.isEmpty == false else {
            return
        }

        let controllers = Array(registeredControllers.values)
        for controller in controllers {
            await controller.handle(connectionEvent: event, in: self)
        }
    }

    private func dispatchControllerStateEvent(_ event: StateEvent) async {
        guard registeredControllers.isEmpty == false else {
            return
        }

        let controllers = Array(registeredControllers.values)
        for controller in controllers {
            await controller.handle(stateEvent: event, in: self)
        }
    }

    private func waitForCondition<T: Sendable>(
        timeout: TimeInterval,
        pollInterval: TimeInterval,
        condition: @escaping @Sendable (CastSession) async throws -> T?
    ) async throws -> T? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            try Task.checkCancellation()

            if let value = try await condition(self) {
                return value
            }

            let sleepNanoseconds = UInt64(max(pollInterval, 0.01) * 1_000_000_000)
            try await Task.sleep(nanoseconds: sleepNanoseconds)
        }
        try Task.checkCancellation()
        return try await condition(self)
    }
}

private extension CastSession {
    final class StreamMapTaskBox: @unchecked Sendable {
        var task: Task<Void, Never>?
    }

    static func mapStream<Input: Sendable, Output: Sendable>(
        _ input: AsyncStream<Input>,
        transform: @escaping @Sendable (Input) -> Output
    ) -> AsyncStream<Output> {
        AsyncStream<Output> { continuation in
            let box = StreamMapTaskBox()
            box.task = Task { [box] in
                for await value in input {
                    continuation.yield(transform(value))
                }
                continuation.finish()
                box.task = nil
            }

            continuation.onTermination = { [weak box] _ in
                box?.task?.cancel()
                box?.task = nil
            }
        }
    }
}
