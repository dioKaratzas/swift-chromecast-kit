//
//  ChromecastKit
//  Swift package for Google Cast (Chromecast).
//

import Foundation

/// Snapshot of the latest receiver and media status known for a Cast session.
struct CastSessionStateSnapshot: Sendable, Hashable {
    let receiverStatus: CastReceiverStatus?
    let mediaStatus: CastMediaStatus?

    init(
        receiverStatus: CastReceiverStatus? = nil,
        mediaStatus: CastMediaStatus? = nil
    ) {
        self.receiverStatus = receiverStatus
        self.mediaStatus = mediaStatus
    }
}

/// State change event emitted by the session runtime state store.
enum CastSessionStateEvent: Sendable, Hashable {
    case receiverStatusUpdated(CastReceiverStatus?)
    case mediaStatusUpdated(CastMediaStatus?)
}
