//
//  ChromecastKit
//  Swift package for Google Cast (Chromecast).
//

import Foundation

/// Configuration for Cast device discovery behavior.
struct CastDiscoveryConfiguration: Sendable, Hashable {
    var includeGroups: Bool
    var browseTimeout: TimeInterval?

    init(
        includeGroups: Bool = true,
        browseTimeout: TimeInterval? = nil
    ) {
        self.includeGroups = includeGroups
        self.browseTimeout = browseTimeout
    }
}

/// Runtime state of the discovery subsystem.
enum CastDiscoveryState: Sendable, Hashable {
    case stopped
    case starting
    case running
    case failed(CastError)
}

/// Discovery event emitted by `CastDiscovery`.
enum CastDiscoveryEvent: Sendable, Hashable {
    case started
    case stopped
    case deviceUpserted(device: CastDeviceDescriptor, isNew: Bool)
    case deviceRemoved(id: CastDeviceID)
    case error(CastError)
}
