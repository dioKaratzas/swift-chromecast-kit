//
//  ChromecastKit
//  Swift package for Google Cast (Chromecast).
//

import Foundation

/// Actor that owns the latest typed receiver/media status snapshots for a Cast session.
actor CastSessionStateStore {
    private var receiverStatusValue: CastReceiverStatus?
    private var mediaStatusValue: CastMediaStatus?
    private var eventContinuations = [UUID: AsyncStream<CastSessionStateEvent>.Continuation]()

    init() {}

    /// Returns the latest receiver status snapshot.
    func receiverStatus() -> CastReceiverStatus? {
        receiverStatusValue
    }

    /// Returns the latest media status snapshot.
    func mediaStatus() -> CastMediaStatus? {
        mediaStatusValue
    }

    /// Returns a combined state snapshot.
    func snapshot() -> CastSessionStateSnapshot {
        .init(receiverStatus: receiverStatusValue, mediaStatus: mediaStatusValue)
    }

    /// Subscribes to state updates for this session.
    func events() -> AsyncStream<CastSessionStateEvent> {
        let id = UUID()

        return AsyncStream { continuation in
            eventContinuations[id] = continuation
            continuation.onTermination = { [id] _ in
                Task { await self.removeContinuation(id: id) }
            }
        }
    }

    func setReceiverStatus(_ status: CastReceiverStatus?) {
        receiverStatusValue = status
        emit(.receiverStatusUpdated(status))
    }

    func setMediaStatus(_ status: CastMediaStatus?) {
        mediaStatusValue = status
        emit(.mediaStatusUpdated(status))
    }

    private func emit(_ event: CastSessionStateEvent) {
        for continuation in eventContinuations.values {
            continuation.yield(event)
        }
    }

    private func removeContinuation(id: UUID) {
        eventContinuations[id] = nil
    }
}
