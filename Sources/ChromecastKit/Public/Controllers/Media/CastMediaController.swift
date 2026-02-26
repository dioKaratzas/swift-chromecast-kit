//
//  ChromecastKit
//  Swift package for Google Cast (Chromecast).
//

import Foundation

/// High-level sender for Cast media namespace commands.
///
/// This actor emits typed media commands to the currently active application transport.
/// Response parsing and session/media status handling will be layered on top later.
public actor CastMediaController {
    // MARK: Public Models

    /// Options for `load(_:options:)`.
    public struct LoadOptions: Sendable, Hashable, Codable {
        public var autoplay: Bool
        public var startTime: TimeInterval?
        public var activeTextTrackIDs: [CastMediaTrackID]
        public var customData: JSONValue?

        public init(
            autoplay: Bool = true,
            startTime: TimeInterval? = nil,
            activeTextTrackIDs: [CastMediaTrackID] = [],
            customData: JSONValue? = nil
        ) {
            self.autoplay = autoplay
            self.startTime = startTime
            self.activeTextTrackIDs = activeTextTrackIDs
            self.customData = customData
        }
    }

    /// Options for `queueLoad(items:options:)`.
    public struct QueueLoadOptions: Sendable, Hashable, Codable {
        public var startIndex: Int?
        public var repeatMode: CastQueueRepeatMode?
        public var currentTime: TimeInterval?
        public var customData: JSONValue?

        public init(
            startIndex: Int? = nil,
            repeatMode: CastQueueRepeatMode? = nil,
            currentTime: TimeInterval? = nil,
            customData: JSONValue? = nil
        ) {
            self.startIndex = startIndex
            self.repeatMode = repeatMode
            self.currentTime = currentTime
            self.customData = customData
        }
    }

    /// Options for `queueInsert(items:options:)`.
    public struct QueueInsertOptions: Sendable, Hashable, Codable {
        public var currentItemID: CastQueueItemID?
        public var currentItemIndex: Int?
        public var currentTime: TimeInterval?
        public var insertBeforeItemID: CastQueueItemID?

        public init(
            currentItemID: CastQueueItemID? = nil,
            currentItemIndex: Int? = nil,
            currentTime: TimeInterval? = nil,
            insertBeforeItemID: CastQueueItemID? = nil
        ) {
            self.currentItemID = currentItemID
            self.currentItemIndex = currentItemIndex
            self.currentTime = currentTime
            self.insertBeforeItemID = insertBeforeItemID
        }
    }

    /// Options for `queueRemove(itemIDs:options:)`.
    public struct QueueRemoveOptions: Sendable, Hashable, Codable {
        public var currentItemID: CastQueueItemID?
        public var currentTime: TimeInterval?

        public init(
            currentItemID: CastQueueItemID? = nil,
            currentTime: TimeInterval? = nil
        ) {
            self.currentItemID = currentItemID
            self.currentTime = currentTime
        }
    }

    /// Options for `queueReorder(itemIDs:options:)`.
    public struct QueueReorderOptions: Sendable, Hashable, Codable {
        public var currentItemID: CastQueueItemID?
        public var currentTime: TimeInterval?
        public var insertBeforeItemID: CastQueueItemID?

        public init(
            currentItemID: CastQueueItemID? = nil,
            currentTime: TimeInterval? = nil,
            insertBeforeItemID: CastQueueItemID? = nil
        ) {
            self.currentItemID = currentItemID
            self.currentTime = currentTime
            self.insertBeforeItemID = insertBeforeItemID
        }
    }

    /// Options for `queueUpdate(items:options:)`.
    public struct QueueUpdateOptions: Sendable, Hashable, Codable {
        public var currentItemID: CastQueueItemID?
        public var currentTime: TimeInterval?
        public var jump: Int?
        public var repeatMode: CastQueueRepeatMode?

        public init(
            currentItemID: CastQueueItemID? = nil,
            currentTime: TimeInterval? = nil,
            jump: Int? = nil,
            repeatMode: CastQueueRepeatMode? = nil
        ) {
            self.currentItemID = currentItemID
            self.currentTime = currentTime
            self.jump = jump
            self.repeatMode = repeatMode
        }
    }

    // MARK: Private State

    private let dispatcher: CastCommandDispatcher
    private var mediaSessionID: CastMediaSessionID?

    // MARK: Public API

    /// Requests media status from the active media transport.
    @discardableResult
    public func getStatus() async throws -> CastRequestID {
        try await sendMediaCommand(CastMediaPayloadBuilder.getStatus())
    }

    /// Loads media into the active media receiver/app transport.
    @discardableResult
    public func load(
        _ item: CastMediaItem,
        options: LoadOptions = .init()
    ) async throws -> CastRequestID {
        try await sendMediaCommand(
            CastMediaPayloadBuilder.load(
                item: item,
                options: .init(
                    autoplay: options.autoplay,
                    startTime: options.startTime,
                    activeTextTrackIDs: options.activeTextTrackIDs,
                    customData: options.customData
                )
            )
        )
    }

    /// Loads a media queue into the active media receiver/app transport.
    @discardableResult
    public func queueLoad(
        items: [CastQueueItem],
        options: QueueLoadOptions = .init()
    ) async throws -> CastRequestID {
        try await sendMediaCommand(
            CastMediaPayloadBuilder.queueLoad(
                items: items,
                options: .init(
                    startIndex: options.startIndex,
                    repeatMode: options.repeatMode,
                    currentTime: options.currentTime,
                    customData: options.customData
                )
            )
        )
    }

    /// Convenience receiver-level volume control while working in the media workflow.
    ///
    /// This sends a platform `SET_VOLUME` request on the receiver namespace.
    @discardableResult
    public func setVolume(level: Double) async throws -> CastRequestID {
        try await sendReceiverPlatformCommand(CastReceiverPayloadBuilder.setVolume(level: level))
    }

    /// Convenience receiver-level mute control while working in the media workflow.
    ///
    /// This sends a platform `SET_VOLUME` request with the `muted` field.
    @discardableResult
    public func setMuted(_ muted: Bool) async throws -> CastRequestID {
        try await sendReceiverPlatformCommand(CastReceiverPayloadBuilder.setMuted(muted))
    }

    /// Enables a text track by Cast track ID.
    @discardableResult
    public func enableTextTrack(id: CastMediaTrackID) async throws -> CastRequestID {
        try await sendMediaSessionCommand { mediaSessionID in
            CastMediaPayloadBuilder.enableTextTrack(trackID: id, mediaSessionID: mediaSessionID)
        }
    }

    /// Disables all active text tracks.
    @discardableResult
    public func disableTextTracks() async throws -> CastRequestID {
        try await sendMediaSessionCommand(CastMediaPayloadBuilder.disableTextTracks(mediaSessionID:))
    }

    /// Updates text track styling for the current media session.
    @discardableResult
    public func setTextTrackStyle(_ style: CastTextTrackStyle) async throws -> CastRequestID {
        try await sendMediaSessionCommand { mediaSessionID in
            CastMediaPayloadBuilder.textTrackStyle(style, mediaSessionID: mediaSessionID)
        }
    }

    /// Sends a `PLAY` command for the current media session.
    @discardableResult
    public func play() async throws -> CastRequestID {
        try await sendMediaSessionCommand(CastMediaPayloadBuilder.play(mediaSessionID:))
    }

    /// Sends a `PAUSE` command for the current media session.
    @discardableResult
    public func pause() async throws -> CastRequestID {
        try await sendMediaSessionCommand(CastMediaPayloadBuilder.pause(mediaSessionID:))
    }

    /// Sends a `STOP` command for the current media session.
    @discardableResult
    public func stop() async throws -> CastRequestID {
        try await sendMediaSessionCommand(CastMediaPayloadBuilder.stop(mediaSessionID:))
    }

    /// Sends a `SEEK` command for the current media session.
    @discardableResult
    public func seek(
        to time: TimeInterval,
        resume: Bool? = nil
    ) async throws -> CastRequestID {
        try await sendMediaSessionCommand { mediaSessionID in
            CastMediaPayloadBuilder.seek(to: time, mediaSessionID: mediaSessionID, resume: resume)
        }
    }

    /// Sends a `SET_PLAYBACK_RATE` command for the current media session.
    @discardableResult
    public func setPlaybackRate(_ rate: Double) async throws -> CastRequestID {
        try await sendMediaSessionCommand { mediaSessionID in
            CastMediaPayloadBuilder.setPlaybackRate(rate, mediaSessionID: mediaSessionID)
        }
    }

    /// Inserts queue items into the current media session queue.
    @discardableResult
    public func queueInsert(
        items: [CastQueueItem],
        options: QueueInsertOptions = .init()
    ) async throws -> CastRequestID {
        try await sendMediaSessionCommand { mediaSessionID in
            CastMediaPayloadBuilder.queueInsert(
                items: items,
                mediaSessionID: mediaSessionID,
                options: .init(
                    currentItemID: options.currentItemID,
                    currentItemIndex: options.currentItemIndex,
                    currentTime: options.currentTime,
                    insertBeforeItemID: options.insertBeforeItemID
                )
            )
        }
    }

    /// Removes queue items from the current media session queue.
    @discardableResult
    public func queueRemove(
        itemIDs: [CastQueueItemID],
        options: QueueRemoveOptions = .init()
    ) async throws -> CastRequestID {
        try await sendMediaSessionCommand { mediaSessionID in
            CastMediaPayloadBuilder.queueRemove(
                itemIDs: itemIDs,
                mediaSessionID: mediaSessionID,
                options: .init(
                    currentItemID: options.currentItemID,
                    currentTime: options.currentTime
                )
            )
        }
    }

    /// Reorders queue items in the current media session queue.
    @discardableResult
    public func queueReorder(
        itemIDs: [CastQueueItemID],
        options: QueueReorderOptions = .init()
    ) async throws -> CastRequestID {
        try await sendMediaSessionCommand { mediaSessionID in
            CastMediaPayloadBuilder.queueReorder(
                itemIDs: itemIDs,
                mediaSessionID: mediaSessionID,
                options: .init(
                    currentItemID: options.currentItemID,
                    currentTime: options.currentTime,
                    insertBeforeItemID: options.insertBeforeItemID
                )
            )
        }
    }

    /// Updates queue state or items in the current media session queue.
    @discardableResult
    public func queueUpdate(
        items: [CastQueueItem]? = nil,
        options: QueueUpdateOptions = .init()
    ) async throws -> CastRequestID {
        try await sendMediaSessionCommand { mediaSessionID in
            CastMediaPayloadBuilder.queueUpdate(
                items: items,
                mediaSessionID: mediaSessionID,
                options: .init(
                    currentItemID: options.currentItemID,
                    currentTime: options.currentTime,
                    jump: options.jump,
                    repeatMode: options.repeatMode
                )
            )
        }
    }

    /// Advances to the next queue item in the current media session.
    ///
    /// Cast models this as a queue update with a positive `jump`.
    @discardableResult
    public func queueNext() async throws -> CastRequestID {
        try await queueUpdate(options: .init(jump: 1))
    }

    /// Moves to the previous queue item in the current media session.
    ///
    /// Cast models this as a queue update with a negative `jump`.
    @discardableResult
    public func queuePrevious() async throws -> CastRequestID {
        try await queueUpdate(options: .init(jump: -1))
    }

    // MARK: Internal Session Wiring

    init(dispatcher: CastCommandDispatcher) {
        self.dispatcher = dispatcher
    }

    // MARK: Private Helpers

    private func requireMediaSessionID() throws -> CastMediaSessionID {
        guard let mediaSessionID else {
            throw CastError.noActiveMediaSession
        }
        return mediaSessionID
    }

    @discardableResult
    private func sendMediaCommand<Payload: Encodable & Sendable>(
        _ payload: Payload
    ) async throws -> CastRequestID {
        try await dispatcher.send(
            namespace: .media,
            target: .currentApplication,
            payload: payload
        )
    }

    @discardableResult
    private func sendReceiverPlatformCommand<Payload: Encodable & Sendable>(
        _ payload: Payload
    ) async throws -> CastRequestID {
        try await dispatcher.send(
            namespace: .receiver,
            target: .platform,
            payload: payload
        )
    }

    @discardableResult
    private func sendMediaSessionCommand<Payload: Encodable & Sendable>(
        _ payload: (CastMediaSessionID) -> Payload
    ) async throws -> CastRequestID {
        try await sendMediaCommand(payload(requireMediaSessionID()))
    }

    // MARK: Internal Runtime Hooks

    /// Sets the active media session ID used for session-bound media commands.
    ///
    /// This is typically sourced from media status updates after a `LOAD` succeeds.
    func setMediaSessionID(_ mediaSessionID: CastMediaSessionID?) {
        self.mediaSessionID = mediaSessionID
    }
}
