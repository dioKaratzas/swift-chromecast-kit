//
//  ChromecastKit
//  SPDX-License-Identifier: Apache-2.0
//  Copyright 2026 Dionysis Karatzas
//

import Foundation

/// Snapshot of the latest receiver and media status known for a Cast session.
struct CastSessionStateSnapshot: Sendable, Hashable {
    let receiverStatus: CastReceiverStatus?
    let mediaStatus: CastMediaStatus?
    let multizoneStatus: CastMultizoneStatus?

    init(
        receiverStatus: CastReceiverStatus? = nil,
        mediaStatus: CastMediaStatus? = nil,
        multizoneStatus: CastMultizoneStatus? = nil
    ) {
        self.receiverStatus = receiverStatus
        self.mediaStatus = mediaStatus
        self.multizoneStatus = multizoneStatus
    }
}

/// State change event emitted by the session runtime state store.
enum CastSessionStateEvent: Sendable, Hashable {
    case receiverStatusUpdated(CastReceiverStatus?)
    case mediaStatusUpdated(CastMediaStatus?)
    case multizoneStatusUpdated(CastMultizoneStatus?)
}
