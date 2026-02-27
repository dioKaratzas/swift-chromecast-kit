//
//  ChromecastKit
//  Swift package for Google Cast (Chromecast).
//

import Foundation

public extension CastSession {
    // MARK: Public Models

    /// Token returned when registering a custom namespace handler on a `CastSession`.
    struct NamespaceHandlerToken: Sendable, Hashable, Codable, RawRepresentable {
        public let rawValue: UUID

        public init(rawValue: UUID) {
            self.rawValue = rawValue
        }
    }

    /// Token returned when registering a session controller on a ``CastSession``.
    struct ControllerToken: Sendable, Hashable, Codable, RawRepresentable {
        public let rawValue: UUID

        public init(rawValue: UUID) {
            self.rawValue = rawValue
        }
    }

    /// Reconnect delay behavior between retry attempts.
    enum ReconnectBackoffStrategy: String, Sendable, Hashable, Codable {
        /// Always uses the same `initialDelay`.
        case fixed
        /// Uses `initialDelay * multiplier^(attempt-1)`, clamped by `maxDelay`.
        case exponential
    }

    /// Reconnect retry policy used after runtime disconnects/failures.
    struct ReconnectPolicy: Sendable, Hashable, Codable {
        /// Delay strategy used to compute per-attempt wait duration.
        public var backoffStrategy: ReconnectBackoffStrategy
        /// Delay for the first scheduled retry.
        public var initialDelay: TimeInterval
        /// Maximum retry delay for strategies that can grow.
        public var maxDelay: TimeInterval
        /// Growth multiplier for exponential backoff.
        public var multiplier: Double
        /// Random jitter percentage in the `0...1` range.
        ///
        /// `0` disables jitter. `0.2` means up to ±20% jitter around the base delay.
        public var jitterFactor: Double
        /// Maximum reconnect attempts after a disconnect.
        ///
        /// `nil` means retry indefinitely while `autoReconnect` is enabled.
        public var maxAttempts: Int?
        /// Waits for a satisfied network path before attempting reconnect.
        public var waitsForReachableNetworkPath: Bool
        /// Optional timeout for waiting on a reachable path.
        ///
        /// `nil` waits indefinitely (until cancellation).
        public var networkPathWaitTimeout: TimeInterval?

        public init(
            backoffStrategy: ReconnectBackoffStrategy = .exponential,
            initialDelay: TimeInterval = 1,
            maxDelay: TimeInterval = 30,
            multiplier: Double = 2,
            jitterFactor: Double = 0.2,
            maxAttempts: Int? = nil,
            waitsForReachableNetworkPath: Bool = true,
            networkPathWaitTimeout: TimeInterval? = nil
        ) {
            self.backoffStrategy = backoffStrategy
            self.initialDelay = max(0, initialDelay)
            self.maxDelay = max(0, maxDelay)
            self.multiplier = max(1, multiplier)
            self.jitterFactor = min(max(0, jitterFactor), 1)
            self.maxAttempts = maxAttempts.map { max(0, $0) }
            self.waitsForReachableNetworkPath = waitsForReachableNetworkPath
            self.networkPathWaitTimeout = networkPathWaitTimeout.map { max(0, $0) }
        }

        /// Convenience constructor for fixed-delay retries.
        public static func fixed(
            delay: TimeInterval = 1,
            jitterFactor: Double = 0,
            maxAttempts: Int? = nil,
            waitsForReachableNetworkPath: Bool = true,
            networkPathWaitTimeout: TimeInterval? = nil
        ) -> Self {
            .init(
                backoffStrategy: .fixed,
                initialDelay: delay,
                maxDelay: delay,
                multiplier: 1,
                jitterFactor: jitterFactor,
                maxAttempts: maxAttempts,
                waitsForReachableNetworkPath: waitsForReachableNetworkPath,
                networkPathWaitTimeout: networkPathWaitTimeout
            )
        }

        /// Convenience constructor for exponential backoff retries.
        public static func exponential(
            initialDelay: TimeInterval = 1,
            maxDelay: TimeInterval = 30,
            multiplier: Double = 2,
            jitterFactor: Double = 0.2,
            maxAttempts: Int? = nil,
            waitsForReachableNetworkPath: Bool = true,
            networkPathWaitTimeout: TimeInterval? = nil
        ) -> Self {
            .init(
                backoffStrategy: .exponential,
                initialDelay: initialDelay,
                maxDelay: maxDelay,
                multiplier: multiplier,
                jitterFactor: jitterFactor,
                maxAttempts: maxAttempts,
                waitsForReachableNetworkPath: waitsForReachableNetworkPath,
                networkPathWaitTimeout: networkPathWaitTimeout
            )
        }
    }

    /// Controls how much typed status state should be restored after reconnects.
    enum StateRestorationPolicy: String, Sendable, Hashable, Codable {
        /// Restores receiver status only (no media session bootstrap).
        case receiverOnly
        /// Restores receiver status and app/media session status when available.
        case receiverAndMedia
    }

    /// Session observability callbacks for logs, metrics, and traces.
    struct Observability: Sendable {
        public var onLog: (@Sendable (LogEvent) -> Void)?
        public var onMetric: (@Sendable (MetricEvent) -> Void)?
        public var onTrace: (@Sendable (TraceEvent) -> Void)?

        public init(
            onLog: (@Sendable (LogEvent) -> Void)? = nil,
            onMetric: (@Sendable (MetricEvent) -> Void)? = nil,
            onTrace: (@Sendable (TraceEvent) -> Void)? = nil
        ) {
            self.onLog = onLog
            self.onMetric = onMetric
            self.onTrace = onTrace
        }

        /// No-op observability configuration.
        public static let disabled = Self()
    }

    /// Structured log record emitted by session runtime internals.
    struct LogEvent: Sendable, Hashable {
        public enum Level: String, Sendable, Hashable, Codable {
            case debug
            case info
            case warning
            case error
        }

        public let level: Level
        public let code: String
        public let message: String
        public let metadata: [String: String]
        public let timestamp: Date

        public init(
            level: Level,
            code: String,
            message: String,
            metadata: [String: String] = [:],
            timestamp: Date = Date()
        ) {
            self.level = level
            self.code = code
            self.message = message
            self.metadata = metadata
            self.timestamp = timestamp
        }
    }

    /// Structured metric record emitted by session runtime internals.
    struct MetricEvent: Sendable, Hashable {
        public let name: String
        public let value: Double
        public let unit: String
        public let dimensions: [String: String]
        public let timestamp: Date

        public init(
            name: String,
            value: Double,
            unit: String,
            dimensions: [String: String] = [:],
            timestamp: Date = Date()
        ) {
            self.name = name
            self.value = value
            self.unit = unit
            self.dimensions = dimensions
            self.timestamp = timestamp
        }
    }

    /// Structured trace record emitted by session runtime internals.
    struct TraceEvent: Sendable, Hashable {
        public enum Phase: String, Sendable, Hashable, Codable {
            case begin
            case end
            case instant
        }

        public let name: String
        public let phase: Phase
        public let traceID: UUID
        public let attributes: [String: String]
        public let timestamp: Date

        public init(
            name: String,
            phase: Phase,
            traceID: UUID,
            attributes: [String: String] = [:],
            timestamp: Date = Date()
        ) {
            self.name = name
            self.phase = phase
            self.traceID = traceID
            self.attributes = attributes
            self.timestamp = timestamp
        }
    }

    /// Session connection behavior tuning.
    struct Configuration: Sendable, Hashable, Codable {
        public var connectTimeout: TimeInterval
        public var commandTimeout: TimeInterval
        public var heartbeatInterval: TimeInterval
        public var autoReconnect: Bool
        /// Compatibility alias for `reconnectPolicy.initialDelay`.
        ///
        /// New code should prefer `reconnectPolicy`.
        public var reconnectRetryDelay: TimeInterval
        public var reconnectPolicy: ReconnectPolicy
        public var stateRestorationPolicy: StateRestorationPolicy

        public init(
            connectTimeout: TimeInterval = 10,
            commandTimeout: TimeInterval = 10,
            heartbeatInterval: TimeInterval = 5,
            autoReconnect: Bool = true,
            reconnectRetryDelay: TimeInterval = 1,
            reconnectPolicy: ReconnectPolicy? = nil,
            stateRestorationPolicy: StateRestorationPolicy = .receiverAndMedia
        ) {
            self.connectTimeout = connectTimeout
            self.commandTimeout = commandTimeout
            self.heartbeatInterval = heartbeatInterval
            self.autoReconnect = autoReconnect
            let resolvedReconnectPolicy = reconnectPolicy ?? .exponential(initialDelay: reconnectRetryDelay)
            self.reconnectRetryDelay = resolvedReconnectPolicy.initialDelay
            self.reconnectPolicy = resolvedReconnectPolicy
            self.stateRestorationPolicy = stateRestorationPolicy
        }
    }

    /// Reason the SDK closed or observed a Cast session disconnect.
    enum DisconnectReason: String, Sendable, Hashable, Codable {
        case requested
        case remoteClosed
        case heartbeatTimeout
        case networkError
    }

    /// High-level connection state for a Cast session.
    enum ConnectionState: Sendable, Hashable {
        case disconnected
        case connecting
        case connected
        case reconnecting
        case failed(CastError)
    }

    /// Connection lifecycle events emitted by a session.
    enum ConnectionEvent: Sendable, Hashable {
        case connected
        case disconnected(reason: DisconnectReason?)
        case reconnected
        case error(CastError)
    }

    /// Snapshot of the latest receiver and media status known for a session.
    struct StateSnapshot: Sendable, Hashable {
        public let receiverStatus: CastReceiverStatus?
        public let mediaStatus: CastMediaStatus?
        public let multizoneStatus: CastMultizoneStatus?

        public init(
            receiverStatus: CastReceiverStatus? = nil,
            mediaStatus: CastMediaStatus? = nil,
            multizoneStatus: CastMultizoneStatus? = nil
        ) {
            self.receiverStatus = receiverStatus
            self.mediaStatus = mediaStatus
            self.multizoneStatus = multizoneStatus
        }
    }

    /// Session state updates emitted as receiver/media statuses change.
    enum StateEvent: Sendable, Hashable {
        case receiverStatusUpdated(CastReceiverStatus?)
        case mediaStatusUpdated(CastMediaStatus?)
        case multizoneStatusUpdated(CastMultizoneStatus?)
    }

    /// Destination for a custom namespace message.
    enum NamespaceTarget: Sendable, Hashable, Codable {
        case currentApplication
        case platform
        case transport(CastTransportID)
    }

    /// Inbound UTF-8 message received on a custom Cast namespace.
    struct NamespaceMessage: Sendable, Hashable, Codable {
        public let namespace: CastNamespace
        public let sourceID: String
        public let destinationID: String
        public let payloadUTF8: String

        public init(
            namespace: CastNamespace,
            sourceID: String,
            destinationID: String,
            payloadUTF8: String
        ) {
            self.namespace = namespace
            self.sourceID = sourceID
            self.destinationID = destinationID
            self.payloadUTF8 = payloadUTF8
        }

        /// Decodes the payload JSON string into a typed value.
        public func decodePayload<T: Decodable & Sendable>(_ type: T.Type = T.self) throws -> T {
            try CastMessageJSONCodec.decodePayload(T.self, from: payloadUTF8)
        }

        /// Decodes the payload to a JSON object escape hatch.
        public func jsonObject() throws -> [String: JSONValue] {
            try decodePayload([String: JSONValue].self)
        }
    }

    /// Payload for a custom namespace inbound message.
    enum NamespacePayload: Sendable, Hashable {
        case utf8(String)
        case binary(Data)
    }

    /// Inbound custom namespace message supporting UTF-8 and binary payloads.
    struct NamespaceEvent: Sendable, Hashable {
        public let namespace: CastNamespace
        public let sourceID: String
        public let destinationID: String
        public let payload: NamespacePayload

        public init(
            namespace: CastNamespace,
            sourceID: String,
            destinationID: String,
            payload: NamespacePayload
        ) {
            self.namespace = namespace
            self.sourceID = sourceID
            self.destinationID = destinationID
            self.payload = payload
        }

        public var payloadUTF8: String? {
            guard case let .utf8(value) = payload else {
                return nil
            }
            return value
        }

        public var payloadBinary: Data? {
            guard case let .binary(value) = payload else {
                return nil
            }
            return value
        }

        public func decodePayload<T: Decodable & Sendable>(_ type: T.Type = T.self) throws -> T {
            switch payload {
            case let .utf8(payloadUTF8):
                return try CastMessageJSONCodec.decodePayload(T.self, from: payloadUTF8)
            case let .binary(payloadBinary):
                guard let payloadUTF8 = String(data: payloadBinary, encoding: .utf8) else {
                    throw CastError.unsupportedFeature("Cannot decode non-UTF8 binary namespace payload as JSON")
                }
                return try CastMessageJSONCodec.decodePayload(T.self, from: payloadUTF8)
            }
        }

        public func jsonObject() throws -> [String: JSONValue] {
            try decodePayload([String: JSONValue].self)
        }
    }
}

extension CastSession.ReconnectPolicy {
    func retryDelay(forAttempt attempt: Int, randomUnit: Double) -> TimeInterval {
        guard attempt > 0 else {
            return 0
        }

        let baseDelay: TimeInterval
        switch backoffStrategy {
        case .fixed:
            baseDelay = initialDelay
        case .exponential:
            baseDelay = initialDelay * pow(multiplier, Double(attempt - 1))
        }

        let clamped = min(max(0, baseDelay), maxDelay)
        guard jitterFactor > 0 else {
            return clamped
        }

        let unit = min(max(0, randomUnit), 1)
        let centered = (unit * 2) - 1
        let jitterMagnitude = clamped * jitterFactor
        let jittered = clamped + (centered * jitterMagnitude)
        return max(0, jittered)
    }
}

// MARK: - Internal Bridging

extension CastSessionStateSnapshot {
    var publicValue: CastSession.StateSnapshot {
        .init(receiverStatus: receiverStatus, mediaStatus: mediaStatus, multizoneStatus: multizoneStatus)
    }
}

extension CastSessionStateEvent {
    var publicValue: CastSession.StateEvent {
        switch self {
        case let .receiverStatusUpdated(status): .receiverStatusUpdated(status)
        case let .mediaStatusUpdated(status): .mediaStatusUpdated(status)
        case let .multizoneStatusUpdated(status): .multizoneStatusUpdated(status)
        }
    }
}

extension CastSession.NamespaceTarget {
    var coreValue: CastMessageTarget {
        switch self {
        case .currentApplication: .currentApplication
        case .platform: .platform
        case let .transport(id): .transport(id: id)
        }
    }
}

extension CastSession.ControllerToken {
    var namespaceHandlerToken: CastSession.NamespaceHandlerToken {
        .init(rawValue: rawValue)
    }
}

extension CastSession.NamespaceHandlerToken {
    var controllerToken: CastSession.ControllerToken {
        .init(rawValue: rawValue)
    }
}

extension CastInboundMessage {
    var publicNamespaceMessage: CastSession.NamespaceMessage {
        .init(
            namespace: route.namespace,
            sourceID: route.sourceID.rawValue,
            destinationID: route.destinationID.rawValue,
            payloadUTF8: payloadUTF8
        )
    }
}

extension CastSessionRuntime.CastNamespaceInboundEvent {
    var publicNamespaceEvent: CastSession.NamespaceEvent {
        switch self {
        case let .utf8(message):
            return .init(
                namespace: message.route.namespace,
                sourceID: message.route.sourceID.rawValue,
                destinationID: message.route.destinationID.rawValue,
                payload: .utf8(message.payloadUTF8)
            )
        case let .binary(message):
            return .init(
                namespace: message.route.namespace,
                sourceID: message.route.sourceID.rawValue,
                destinationID: message.route.destinationID.rawValue,
                payload: .binary(message.payloadBinary)
            )
        }
    }
}
