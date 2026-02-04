//
//  ChromecastKit
//  Swift package for Google Cast (Chromecast).
//

import Foundation

/// Cast protocol namespaces used by platform and media communication.
struct CastNamespace: RawRepresentable, ExpressibleByStringLiteral, Sendable, Hashable, Codable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    init(stringLiteral value: StringLiteralType) {
        self.rawValue = value
    }

    static let connection = Self("urn:x-cast:com.google.cast.tp.connection")
    static let heartbeat = Self("urn:x-cast:com.google.cast.tp.heartbeat")
    static let receiver = Self("urn:x-cast:com.google.cast.receiver")
    static let media = Self("urn:x-cast:com.google.cast.media")

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.rawValue = try container.decode(String.self)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// Destination for a Cast message relative to the current connection/session.
enum CastMessageTarget: Sendable, Hashable, Codable {
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

    init(from decoder: any Decoder) throws {
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

    func encode(to encoder: any Encoder) throws {
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
struct CastRequestIDGenerator: Sendable, Hashable, Codable {
    private(set) var current: CastRequestID

    init(startingAt current: CastRequestID = 0) {
        self.current = current
    }

    /// Returns the next request identifier and advances the generator.
    @discardableResult
    mutating func next() -> CastRequestID {
        current = CastRequestID(rawValue: current.rawValue + 1)
        return current
    }
}

/// Common Cast media protocol message types used by the default media receiver.
enum CastMediaMessageType: String, Sendable, Hashable, Codable {
    case mediaStatus = "MEDIA_STATUS"
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
enum CastReceiverMessageType: String, Sendable, Hashable, Codable {
    case receiverStatus = "RECEIVER_STATUS"
    case getStatus = "GET_STATUS"
    case launch = "LAUNCH"
    case stop = "STOP"
    case setVolume = "SET_VOLUME"
    case getAppAvailability = "GET_APP_AVAILABILITY"
}
