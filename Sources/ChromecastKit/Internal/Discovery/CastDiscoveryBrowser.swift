//
//  ChromecastKit
//  Swift package for Google Cast (Chromecast).
//

import Foundation

enum CastDiscoveryBrowserEvent: Sendable, Hashable {
    case deviceUpserted(CastDeviceDescriptor)
    case deviceRemoved(CastDeviceID)
    case error(CastError)
}

protocol CastDiscoveryBrowser: Sendable {
    func events() async -> AsyncStream<CastDiscoveryBrowserEvent>
    func start(configuration: CastDiscoveryConfiguration) async throws
    func stop() async
}
