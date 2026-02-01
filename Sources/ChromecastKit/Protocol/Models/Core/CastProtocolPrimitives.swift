//
//  ChromecastKit
//  Swift package for Google Cast (Chromecast).
//

import Foundation

/// Cast protocol namespaces used by platform and media communication.
public struct CastNamespace: RawRepresentable, ExpressibleByStringLiteral, Sendable, Hashable, Codable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.rawValue = value
    }

    public static let connection = Self("urn:x-cast:com.google.cast.tp.connection")
    public static let heartbeat = Self("urn:x-cast:com.google.cast.tp.heartbeat")
    public static let receiver = Self("urn:x-cast:com.google.cast.receiver")
    public static let media = Self("urn:x-cast:com.google.cast.media")

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.rawValue = try container.decode(String.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// Destination for a Cast message relative to the current connection/session.
public enum CastMessageTarget: Sendable, Hashable, Codable {
    case currentApplication
    case platform
    case transport(id: CastTransportID)

    private enum CodingKeys: String, CodingKey {
        case kind
        case transportID
    }

    private enum Kind: String, Codable {
        case currentApplication
        case platform
        case transport
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .currentApplication:
            self = .currentApplication
        case .platform:
            self = .platform
        case .transport:
            self = try .transport(id: container.decode(CastTransportID.self, forKey: .transportID))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .currentApplication:
            try container.encode(Kind.currentApplication, forKey: .kind)
        case .platform:
            try container.encode(Kind.platform, forKey: .kind)
        case let .transport(id):
            try container.encode(Kind.transport, forKey: .kind)
            try container.encode(id, forKey: .transportID)
        }
    }
}

/// Monotonic request identifier generator for Cast protocol request/response correlation.
///
/// This type is intentionally a value type. The owner responsible for shared access
/// (typically a connection/session actor) should serialize mutation.
public struct CastRequestIDGenerator: Sendable, Hashable, Codable {
    public private(set) var current: CastRequestID

    public init(startingAt current: CastRequestID = 0) {
        self.current = current
    }

    /// Returns the next request identifier and advances the generator.
    @discardableResult
    public mutating func next() -> CastRequestID {
        current = CastRequestID(rawValue: current.rawValue + 1)
        return current
    }
}

/// Common Cast media protocol message types used by the default media receiver.
public enum CastMediaMessageType: String, Sendable, Hashable, Codable {
    case getStatus = "GET_STATUS"
    case load = "LOAD"
    case pause = "PAUSE"
    case play = "PLAY"
    case stop = "STOP"
    case seek = "SEEK"
    case editTracksInfo = "EDIT_TRACKS_INFO"
    case setPlaybackRate = "SET_PLAYBACK_RATE"
    case queueLoad = "QUEUE_LOAD"
    case queueInsert = "QUEUE_INSERT"
    case queueRemove = "QUEUE_REMOVE"
    case queueReorder = "QUEUE_REORDER"
    case queueUpdate = "QUEUE_UPDATE"
}

/// Common Cast receiver protocol message types used by the platform receiver namespace.
public enum CastReceiverMessageType: String, Sendable, Hashable, Codable {
    case getStatus = "GET_STATUS"
    case launch = "LAUNCH"
    case stop = "STOP"
    case setVolume = "SET_VOLUME"
    case getAppAvailability = "GET_APP_AVAILABILITY"
}
