//
//  ChromecastKit
//  Swift package for Google Cast (Chromecast).
//

import Foundation

public extension CastWire {
    /// Namespace for Cast receiver namespace wire-level request and payload models.
    enum Receiver {}
}

public extension CastWire.Receiver {
    /// Wire model for a receiver `GET_STATUS` request.
    struct GetStatusRequest: Sendable, Hashable, Codable {
        public let type: CastReceiverMessageType

        public init(type: CastReceiverMessageType = .getStatus) {
            self.type = type
        }
    }
}

public extension CastWire.Receiver {
    /// Wire model for receiver volume payload.
    struct Volume: Sendable, Hashable, Codable {
        public let level: Double?
        public let muted: Bool?

        public init(level: Double? = nil, muted: Bool? = nil) {
            self.level = level
            self.muted = muted
        }
    }
}

public extension CastWire.Receiver {
    /// Wire model for a receiver `SET_VOLUME` request.
    struct SetVolumeRequest: Sendable, Hashable, Codable {
        public let type: CastReceiverMessageType
        public let volume: Volume

        public init(
            type: CastReceiverMessageType = .setVolume,
            volume: Volume
        ) {
            self.type = type
            self.volume = volume
        }
    }
}

public extension CastWire.Receiver {
    /// Wire model for a receiver `LAUNCH` request.
    struct LaunchRequest: Sendable, Hashable, Codable {
        public let type: CastReceiverMessageType
        public let appId: CastAppID

        public init(
            type: CastReceiverMessageType = .launch,
            appId: CastAppID
        ) {
            self.type = type
            self.appId = appId
        }
    }
}

public extension CastWire.Receiver {
    /// Wire model for a receiver `STOP` request.
    struct StopRequest: Sendable, Hashable, Codable {
        public let type: CastReceiverMessageType
        public let sessionId: CastAppSessionID?

        public init(
            type: CastReceiverMessageType = .stop,
            sessionId: CastAppSessionID? = nil
        ) {
            self.type = type
            self.sessionId = sessionId
        }
    }
}

public extension CastWire.Receiver {
    /// Wire model for a receiver `GET_APP_AVAILABILITY` request.
    struct GetAppAvailabilityRequest: Sendable, Hashable, Codable {
        public let type: CastReceiverMessageType
        public let appId: [CastAppID]

        public init(
            type: CastReceiverMessageType = .getAppAvailability,
            appId: [CastAppID]
        ) {
            self.type = type
            self.appId = appId
        }
    }
}
