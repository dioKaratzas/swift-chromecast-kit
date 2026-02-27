//
//  ChromecastKit
//  SPDX-License-Identifier: Apache-2.0
//  Copyright 2026 Dionysis Karatzas
//

import Foundation

/// Helpers that build typed Cast multizone namespace wire requests.
enum CastMultizonePayloadBuilder {
    static func getStatus() -> CastWire.Multizone.GetStatusRequest {
        .init()
    }

    static func getCastingGroups() -> CastWire.Multizone.GetCastingGroupsRequest {
        .init()
    }
}
