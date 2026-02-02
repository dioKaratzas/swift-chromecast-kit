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

public extension CastWire.Receiver {
    /// Wire response for `RECEIVER_STATUS`.
    struct StatusResponse: Sendable, Hashable, Codable {
        public let type: CastReceiverMessageType
        public let status: Status

        public init(
            type: CastReceiverMessageType = .receiverStatus,
            status: Status
        ) {
            self.type = type
            self.status = status
        }
    }
}

public extension CastWire.Receiver {
    /// Wire receiver status payload.
    struct Status: Sendable, Hashable, Codable {
        public let volume: Volume
        public let applications: [Application]?
        public let isStandBy: Bool?
        public let isActiveInput: Bool?

        public init(
            volume: Volume,
            applications: [Application]? = nil,
            isStandBy: Bool? = nil,
            isActiveInput: Bool? = nil
        ) {
            self.volume = volume
            self.applications = applications
            self.isStandBy = isStandBy
            self.isActiveInput = isActiveInput
        }
    }
}

public extension CastWire.Receiver {
    /// Wire receiver application entry.
    struct Application: Sendable, Hashable, Codable {
        public let appId: CastAppID
        public let displayName: String
        public let sessionId: CastAppSessionID?
        public let transportId: CastTransportID?
        public let statusText: String?
        public let namespaces: [ApplicationNamespace]?

        public init(
            appId: CastAppID,
            displayName: String,
            sessionId: CastAppSessionID? = nil,
            transportId: CastTransportID? = nil,
            statusText: String? = nil,
            namespaces: [ApplicationNamespace]? = nil
        ) {
            self.appId = appId
            self.displayName = displayName
            self.sessionId = sessionId
            self.transportId = transportId
            self.statusText = statusText
            self.namespaces = namespaces
        }
    }
}

public extension CastWire.Receiver {
    /// Wire namespace entry advertised by an app in receiver status.
    struct ApplicationNamespace: Sendable, Hashable, Codable {
        public let name: String

        public init(name: String) {
            self.name = name
        }
    }
}
