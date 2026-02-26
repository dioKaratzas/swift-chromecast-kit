//
//  ChromecastKit
//  Swift package for Google Cast (Chromecast).
//

import Foundation

public extension CastDiscovery {
    // MARK: Configuration

    /// Configuration for Cast device discovery behavior.
    struct Configuration: Sendable, Hashable {
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

    // MARK: Runtime State / Events

    /// Runtime state of the discovery subsystem.
    enum State: Sendable, Hashable {
        case stopped
        case starting
        case running
        case failed(CastError)
    }

    /// Discovery event emitted by ``CastDiscovery``.
    enum Event: Sendable, Hashable {
        case started
        case stopped
        case deviceUpserted(device: CastDeviceDescriptor, isNew: Bool)
        case deviceRemoved(id: CastDeviceID)
        case error(CastError)
    }
}
