//
//  ChromecastKit
//  Swift package for Google Cast (Chromecast).
//

import Foundation

/// Connection behavior tuning for Cast sessions.
struct CastConnectionConfiguration: Sendable, Hashable {
    var connectTimeout: TimeInterval
    var commandTimeout: TimeInterval
    var heartbeatInterval: TimeInterval
    var autoReconnect: Bool

    init(
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
enum CastDisconnectReason: String, Sendable, Hashable, Codable {
    case requested
    case remoteClosed
    case heartbeatTimeout
    case networkError
}

/// Runtime connection state for a Cast session transport.
enum CastConnectionState: Sendable, Hashable {
    case disconnected
    case connecting
    case connected
    case reconnecting
    case failed(CastError)
}

/// High-level connection lifecycle events emitted by `CastConnection`.
enum CastConnectionEvent: Sendable, Hashable {
    case connected
    case disconnected(reason: CastDisconnectReason?)
    case reconnected
    case error(CastError)
}
