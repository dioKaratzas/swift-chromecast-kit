//
//  ChromecastKit
//  Swift package for Google Cast (Chromecast).
//

import Foundation

/// Stable identifier for a Cast device in local discovery and cached state.
public struct CastDeviceID: Sendable, Hashable, Codable, RawRepresentable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.rawValue = value
    }
}

/// High-level capabilities inferred from discovery or device metadata.
public enum CastDeviceCapability: String, Sendable, Hashable, Codable {
    case video
    case audio
    case multizone
    case group
}

/// Immutable descriptor discovered on the network.
public struct CastDeviceDescriptor: Sendable, Hashable, Codable {
    public let id: CastDeviceID
    public let friendlyName: String
    public let host: String
    public let port: Int
    public let modelName: String?
    public let manufacturer: String?
    public let uuid: UUID?
    public let capabilities: Set<CastDeviceCapability>

    public init(
        id: CastDeviceID,
        friendlyName: String,
        host: String,
        port: Int = 8009,
        modelName: String? = nil,
        manufacturer: String? = nil,
        uuid: UUID? = nil,
        capabilities: Set<CastDeviceCapability> = []
    ) {
        self.id = id
        self.friendlyName = friendlyName
        self.host = host
        self.port = port
        self.modelName = modelName
        self.manufacturer = manufacturer
        self.uuid = uuid
        self.capabilities = capabilities
    }
}

/// Receiver/app volume state.
public struct CastVolumeStatus: Sendable, Hashable, Codable {
    public let level: Double
    public let muted: Bool

    public init(level: Double, muted: Bool) {
        self.level = level
        self.muted = muted
    }
}

/// The app currently running on the Cast receiver.
public struct CastRunningApp: Sendable, Hashable, Codable {
    public let appID: CastAppID
    public let displayName: String
    public let sessionID: CastAppSessionID?
    public let transportID: CastTransportID?
    public let statusText: String?
    public let namespaces: [String]

    public init(
        appID: CastAppID,
        displayName: String,
        sessionID: CastAppSessionID? = nil,
        transportID: CastTransportID? = nil,
        statusText: String? = nil,
        namespaces: [String] = []
    ) {
        self.appID = appID
        self.displayName = displayName
        self.sessionID = sessionID
        self.transportID = transportID
        self.statusText = statusText
        self.namespaces = namespaces
    }
}

/// Receiver-level status returned by the Cast platform namespace.
public struct CastReceiverStatus: Sendable, Hashable, Codable {
    public let volume: CastVolumeStatus
    public let app: CastRunningApp?
    public let isStandBy: Bool?
    public let isActiveInput: Bool?

    public init(
        volume: CastVolumeStatus,
        app: CastRunningApp? = nil,
        isStandBy: Bool? = nil,
        isActiveInput: Bool? = nil
    ) {
        self.volume = volume
        self.app = app
        self.isStandBy = isStandBy
        self.isActiveInput = isActiveInput
    }
}
