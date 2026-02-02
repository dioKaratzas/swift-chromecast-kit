//
//  ChromecastKit
//  Swift package for Google Cast (Chromecast).
//

import Foundation

/// Snapshot of the latest receiver and media status known for a Cast session.
public struct CastSessionStateSnapshot: Sendable, Hashable {
    public let receiverStatus: CastReceiverStatus?
    public let mediaStatus: CastMediaStatus?

    public init(
        receiverStatus: CastReceiverStatus? = nil,
        mediaStatus: CastMediaStatus? = nil
    ) {
        self.receiverStatus = receiverStatus
        self.mediaStatus = mediaStatus
    }
}

/// State change event emitted by `CastSessionStateStore`.
public enum CastSessionStateEvent: Sendable, Hashable {
    case receiverStatusUpdated(CastReceiverStatus?)
    case mediaStatusUpdated(CastMediaStatus?)
}

/// Actor that owns the latest typed receiver/media status snapshots for a Cast session.
public actor CastSessionStateStore {
    private var receiverStatusValue: CastReceiverStatus?
    private var mediaStatusValue: CastMediaStatus?
    private var eventContinuations = [UUID: AsyncStream<CastSessionStateEvent>.Continuation]()

    public init() {}

    /// Returns the latest receiver status snapshot.
    public func receiverStatus() -> CastReceiverStatus? {
        receiverStatusValue
    }

    /// Returns the latest media status snapshot.
    public func mediaStatus() -> CastMediaStatus? {
        mediaStatusValue
    }

    /// Returns a combined state snapshot.
    public func snapshot() -> CastSessionStateSnapshot {
        .init(receiverStatus: receiverStatusValue, mediaStatus: mediaStatusValue)
    }

    /// Subscribes to state updates for this session.
    public func events() -> AsyncStream<CastSessionStateEvent> {
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
