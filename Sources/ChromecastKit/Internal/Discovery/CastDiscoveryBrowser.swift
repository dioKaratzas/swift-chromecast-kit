//
//  ChromecastKit
//  SPDX-License-Identifier: Apache-2.0
//  Copyright 2026 Dionysis Karatzas
//

import Foundation

enum CastDiscoveryBrowserEvent: Sendable, Hashable {
    case deviceUpserted(CastDeviceDescriptor)
    case deviceRemoved(CastDeviceID)
    case error(CastError)
}

protocol CastDiscoveryBrowser: Sendable {
    func events() async -> AsyncStream<CastDiscoveryBrowserEvent>
    func start(configuration: CastDiscovery.Configuration) async throws
    func stop() async
}
