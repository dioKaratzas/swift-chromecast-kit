//
//  ChromecastKit
//  Swift package for Google Cast (Chromecast).
//

import Foundation

extension CastWire {
    /// Namespace for Cast transport-control namespace wire models.
    enum Connection {}

    /// Namespace for Cast heartbeat namespace wire models.
    enum Heartbeat {}
}

extension CastWire.Connection {
    /// Wire model for `urn:x-cast:com.google.cast.tp.connection` `CONNECT`.
    struct ConnectRequest: Sendable, Hashable, Codable {
        let type: String
        let origin: [String: JSONValue]

        init(type: String = "CONNECT", origin: [String: JSONValue] = [:]) {
            self.type = type
            self.origin = origin
        }
    }
}

extension CastWire.Heartbeat {
    /// Wire model for Cast heartbeat `PING` / `PONG` messages.
    struct Message: Sendable, Hashable, Codable {
        enum MessageType: String, Sendable, Hashable, Codable {
            case ping = "PING"
            case pong = "PONG"
        }

        let type: MessageType

        init(type: MessageType) {
            self.type = type
        }
    }
}
