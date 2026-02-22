//
//  ChromecastKit
//  Swift package for Google Cast (Chromecast).
//

import Foundation

// MARK: - Configuration

/// Configuration for Cast device discovery behavior.
public struct CastDiscoveryConfiguration: Sendable, Hashable {
    public var includeGroups: Bool
    public var browseTimeout: TimeInterval?
    public var enableSSDPFallback: Bool

    public init(
        includeGroups: Bool = true,
        browseTimeout: TimeInterval? = nil,
        enableSSDPFallback: Bool = false
    ) {
        self.includeGroups = includeGroups
        self.browseTimeout = browseTimeout
        self.enableSSDPFallback = enableSSDPFallback
    }
}

// MARK: - Runtime State / Events

/// Runtime state of the discovery subsystem.
public enum CastDiscoveryState: Sendable, Hashable {
    case stopped
    case starting
    case running
    case failed(CastError)
}

/// Discovery event emitted by `CastDiscovery`.
public enum CastDiscoveryEvent: Sendable, Hashable {
    case started
    case stopped
    case deviceUpserted(device: CastDeviceDescriptor, isNew: Bool)
    case deviceRemoved(id: CastDeviceID)
    case error(CastError)
}
