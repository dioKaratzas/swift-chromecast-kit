//
//  ChromecastKit
//  Swift package for Google Cast (Chromecast).
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
