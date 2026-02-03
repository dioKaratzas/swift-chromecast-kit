//
//  ChromecastKit
//  Swift package for Google Cast (Chromecast).
//

import Foundation

/// Configuration for Cast device discovery behavior.
public struct CastDiscoveryConfiguration: Sendable, Hashable {
    public var includeGroups: Bool
    public var browseTimeout: TimeInterval?

    public init(
        includeGroups: Bool = true,
        browseTimeout: TimeInterval? = nil
    ) {
        self.includeGroups = includeGroups
        self.browseTimeout = browseTimeout
    }
}

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
