//
//  ChromecastKit
//  SPDX-License-Identifier: Apache-2.0
//  Copyright 2026 Dionysis Karatzas
//

import Foundation

extension CastWire {
    /// Namespace for Cast receiver namespace wire-level request and payload models.
    enum Receiver {}
}

extension CastWire.Receiver {
    /// Wire model for a receiver `GET_STATUS` request.
    struct GetStatusRequest: Sendable, Hashable, Codable {
        let type: CastReceiverMessageType

        init(type: CastReceiverMessageType = .getStatus) {
            self.type = type
        }
    }
}

extension CastWire.Receiver {
    /// Wire model for receiver volume payload.
    struct Volume: Sendable, Hashable, Codable {
        let level: Double?
        let muted: Bool?

        init(level: Double? = nil, muted: Bool? = nil) {
            self.level = level
            self.muted = muted
        }
    }
}

extension CastWire.Receiver {
    /// Wire model for a receiver `SET_VOLUME` request.
    struct SetVolumeRequest: Sendable, Hashable, Codable {
        let type: CastReceiverMessageType
        let volume: Volume

        init(
            type: CastReceiverMessageType = .setVolume,
            volume: Volume
        ) {
            self.type = type
            self.volume = volume
        }
    }
}

extension CastWire.Receiver {
    /// Wire model for a receiver `LAUNCH` request.
    struct LaunchRequest: Sendable, Hashable, Codable {
        let type: CastReceiverMessageType
        let appId: CastAppID

        init(
            type: CastReceiverMessageType = .launch,
            appId: CastAppID
        ) {
            self.type = type
            self.appId = appId
        }
    }
}

extension CastWire.Receiver {
    /// Wire model for a receiver `STOP` request.
    struct StopRequest: Sendable, Hashable, Codable {
        let type: CastReceiverMessageType
        let sessionId: CastAppSessionID?

        init(
            type: CastReceiverMessageType = .stop,
            sessionId: CastAppSessionID? = nil
        ) {
            self.type = type
            self.sessionId = sessionId
        }
    }
}

extension CastWire.Receiver {
    /// Wire model for a receiver `GET_APP_AVAILABILITY` request.
    struct GetAppAvailabilityRequest: Sendable, Hashable, Codable {
        let type: CastReceiverMessageType
        let appId: [CastAppID]

        init(
            type: CastReceiverMessageType = .getAppAvailability,
            appId: [CastAppID]
        ) {
            self.type = type
            self.appId = appId
        }
    }
}

extension CastWire.Receiver {
    /// Wire response for `RECEIVER_STATUS`.
    struct StatusResponse: Sendable, Hashable, Codable {
        let type: CastReceiverMessageType
        let status: Status

        init(
            type: CastReceiverMessageType = .receiverStatus,
            status: Status
        ) {
            self.type = type
            self.status = status
        }
    }
}

extension CastWire.Receiver {
    /// Wire receiver status payload.
    struct Status: Sendable, Hashable, Codable {
        let volume: Volume
        let applications: [Application]?
        let isStandBy: Bool?
        let isActiveInput: Bool?

        init(
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

extension CastWire.Receiver {
    /// Wire receiver application entry.
    struct Application: Sendable, Hashable, Codable {
        let appId: CastAppID
        let displayName: String
        let sessionId: CastAppSessionID?
        let transportId: CastTransportID?
        let statusText: String?
        let namespaces: [ApplicationNamespace]?

        init(
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

extension CastWire.Receiver {
    /// Wire namespace entry advertised by an app in receiver status.
    struct ApplicationNamespace: Sendable, Hashable, Codable {
        let name: String

        init(name: String) {
            self.name = name
        }
    }
}
