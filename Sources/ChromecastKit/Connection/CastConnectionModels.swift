//
//  ChromecastKit
//  Swift package for Google Cast (Chromecast).
//

import Foundation

/// Connection behavior tuning for Cast sessions.
public struct CastConnectionConfiguration: Sendable, Hashable {
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

/// Reason a Cast connection was closed.
public enum CastDisconnectReason: String, Sendable, Hashable, Codable {
    case requested
    case remoteClosed
    case heartbeatTimeout
    case networkError
}

/// Runtime connection state for a Cast session transport.
public enum CastConnectionState: Sendable, Hashable {
    case disconnected
    case connecting
    case connected
    case reconnecting
    case failed(CastError)
}

/// High-level connection lifecycle events emitted by `CastConnection`.
public enum CastConnectionEvent: Sendable, Hashable {
    case connected
    case disconnected(reason: CastDisconnectReason?)
    case reconnected
    case error(CastError)
}
