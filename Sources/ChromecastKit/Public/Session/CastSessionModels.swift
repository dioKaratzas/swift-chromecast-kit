//
//  ChromecastKit
//  Swift package for Google Cast (Chromecast).
//

import Foundation

public extension CastSession {
    /// Session connection behavior tuning.
    struct Configuration: Sendable, Hashable, Codable {
        public var connectTimeout: TimeInterval
        public var commandTimeout: TimeInterval
        public var heartbeatInterval: TimeInterval
        public var autoReconnect: Bool

        public init(
            connectTimeout: TimeInterval = 10,
            commandTimeout: TimeInterval = 10,
            heartbeatInterval: TimeInterval = 5,
            autoReconnect: Bool = true
        ) {
            self.connectTimeout = connectTimeout
            self.commandTimeout = commandTimeout
            self.heartbeatInterval = heartbeatInterval
            self.autoReconnect = autoReconnect
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

        public init(
            receiverStatus: CastReceiverStatus? = nil,
            mediaStatus: CastMediaStatus? = nil
        ) {
            self.receiverStatus = receiverStatus
            self.mediaStatus = mediaStatus
        }
    }

    /// Session state updates emitted as receiver/media statuses change.
    enum StateEvent: Sendable, Hashable {
        case receiverStatusUpdated(CastReceiverStatus?)
        case mediaStatusUpdated(CastMediaStatus?)
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
            guard case let .utf8(value) = payload else { return nil }
            return value
        }

        public var payloadBinary: Data? {
            guard case let .binary(value) = payload else { return nil }
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

extension CastSession.Configuration {
    var coreValue: CastConnectionConfiguration {
        .init(
            connectTimeout: connectTimeout,
            commandTimeout: commandTimeout,
            heartbeatInterval: heartbeatInterval,
            autoReconnect: autoReconnect
        )
    }
}

extension CastDisconnectReason {
    var publicValue: CastSession.DisconnectReason {
        switch self {
        case .requested: .requested
        case .remoteClosed: .remoteClosed
        case .heartbeatTimeout: .heartbeatTimeout
        case .networkError: .networkError
        }
    }
}

extension CastSession.DisconnectReason {
    var coreValue: CastDisconnectReason {
        switch self {
        case .requested: .requested
        case .remoteClosed: .remoteClosed
        case .heartbeatTimeout: .heartbeatTimeout
        case .networkError: .networkError
        }
    }
}

extension CastConnectionState {
    var publicValue: CastSession.ConnectionState {
        switch self {
        case .disconnected: .disconnected
        case .connecting: .connecting
        case .connected: .connected
        case .reconnecting: .reconnecting
        case let .failed(error): .failed(error)
        }
    }
}

extension CastConnectionEvent {
    var publicValue: CastSession.ConnectionEvent {
        switch self {
        case .connected: .connected
        case .reconnected: .reconnected
        case let .error(error): .error(error)
        case let .disconnected(reason): .disconnected(reason: reason?.publicValue)
        }
    }
}

extension CastSessionStateSnapshot {
    var publicValue: CastSession.StateSnapshot {
        .init(receiverStatus: receiverStatus, mediaStatus: mediaStatus)
    }
}

extension CastSessionStateEvent {
    var publicValue: CastSession.StateEvent {
        switch self {
        case let .receiverStatusUpdated(status): .receiverStatusUpdated(status)
        case let .mediaStatusUpdated(status): .mediaStatusUpdated(status)
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
