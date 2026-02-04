//
//  ChromecastKit
//  Swift package for Google Cast (Chromecast).
//

import Foundation

/// High-level sender for Cast media namespace commands.
///
/// This actor emits typed media commands to the currently active application transport.
/// Response parsing and session/media status handling will be layered on top later.
actor CastMediaController {
    /// Options for `load(_:options:)`.
    struct LoadOptions: Sendable, Hashable, Codable {
        var autoplay: Bool
        var startTime: TimeInterval?
        var activeTextTrackIDs: [CastMediaTrackID]
        var customData: JSONValue?

        init(
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
    struct QueueLoadOptions: Sendable, Hashable, Codable {
        var startIndex: Int?
        var repeatMode: CastQueueRepeatMode?
        var currentTime: TimeInterval?
        var customData: JSONValue?

        init(
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
    struct QueueInsertOptions: Sendable, Hashable, Codable {
        var currentItemID: CastQueueItemID?
        var currentItemIndex: Int?
        var currentTime: TimeInterval?
        var insertBeforeItemID: CastQueueItemID?

        init(
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
    struct QueueRemoveOptions: Sendable, Hashable, Codable {
        var currentItemID: CastQueueItemID?
        var currentTime: TimeInterval?

        init(
            currentItemID: CastQueueItemID? = nil,
            currentTime: TimeInterval? = nil
        ) {
            self.currentItemID = currentItemID
            self.currentTime = currentTime
        }
    }

    /// Options for `queueReorder(itemIDs:options:)`.
    struct QueueReorderOptions: Sendable, Hashable, Codable {
        var currentItemID: CastQueueItemID?
        var currentTime: TimeInterval?
        var insertBeforeItemID: CastQueueItemID?

        init(
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
    struct QueueUpdateOptions: Sendable, Hashable, Codable {
        var currentItemID: CastQueueItemID?
        var currentTime: TimeInterval?
        var jump: Int?
        var repeatMode: CastQueueRepeatMode?

        init(
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

    private let dispatcher: CastCommandDispatcher
    private var mediaSessionID: CastMediaSessionID?

    init(dispatcher: CastCommandDispatcher) {
        self.dispatcher = dispatcher
    }

    /// Sets the active media session ID used for session-bound media commands.
    ///
    /// This is typically sourced from media status updates after a `LOAD` succeeds.
    func setMediaSessionID(_ mediaSessionID: CastMediaSessionID?) {
        self.mediaSessionID = mediaSessionID
    }

    /// Requests media status from the active media transport.
    @discardableResult
    func getStatus() async throws -> CastRequestID {
        try await dispatcher.send(
            namespace: .media,
            target: .currentApplication,
            payload: CastMediaPayloadBuilder.getStatus()
        )
    }

    /// Loads media into the active media receiver/app transport.
    @discardableResult
    func load(
        _ item: CastMediaItem,
        options: LoadOptions = .init()
    ) async throws -> CastRequestID {
        try await dispatcher.send(
            namespace: .media,
            target: .currentApplication,
            payload: CastMediaPayloadBuilder.load(
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
    func queueLoad(
        items: [CastQueueItem],
        options: QueueLoadOptions = .init()
    ) async throws -> CastRequestID {
        try await dispatcher.send(
            namespace: .media,
            target: .currentApplication,
            payload: CastMediaPayloadBuilder.queueLoad(
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

    /// Enables a text track by Cast track ID.
    @discardableResult
    func enableTextTrack(id: CastMediaTrackID) async throws -> CastRequestID {
        let mediaSessionID = try requireMediaSessionID()
        return try await dispatcher.send(
            namespace: .media,
            target: .currentApplication,
            payload: CastMediaPayloadBuilder.enableTextTrack(trackID: id, mediaSessionID: mediaSessionID)
        )
    }

    /// Disables all active text tracks.
    @discardableResult
    func disableTextTracks() async throws -> CastRequestID {
        let mediaSessionID = try requireMediaSessionID()
        return try await dispatcher.send(
            namespace: .media,
            target: .currentApplication,
            payload: CastMediaPayloadBuilder.disableTextTracks(mediaSessionID: mediaSessionID)
        )
    }

    /// Updates text track styling for the current media session.
    @discardableResult
    func setTextTrackStyle(_ style: CastTextTrackStyle) async throws -> CastRequestID {
        let mediaSessionID = try requireMediaSessionID()
        return try await dispatcher.send(
            namespace: .media,
            target: .currentApplication,
            payload: CastMediaPayloadBuilder.textTrackStyle(style, mediaSessionID: mediaSessionID)
        )
    }

    /// Sends a `PLAY` command for the current media session.
    @discardableResult
    func play() async throws -> CastRequestID {
        let mediaSessionID = try requireMediaSessionID()
        return try await dispatcher.send(
            namespace: .media,
            target: .currentApplication,
            payload: CastMediaPayloadBuilder.play(mediaSessionID: mediaSessionID)
        )
    }

    /// Sends a `PAUSE` command for the current media session.
    @discardableResult
    func pause() async throws -> CastRequestID {
        let mediaSessionID = try requireMediaSessionID()
        return try await dispatcher.send(
            namespace: .media,
            target: .currentApplication,
            payload: CastMediaPayloadBuilder.pause(mediaSessionID: mediaSessionID)
        )
    }

    /// Sends a `STOP` command for the current media session.
    @discardableResult
    func stop() async throws -> CastRequestID {
        let mediaSessionID = try requireMediaSessionID()
        return try await dispatcher.send(
            namespace: .media,
            target: .currentApplication,
            payload: CastMediaPayloadBuilder.stop(mediaSessionID: mediaSessionID)
        )
    }

    /// Sends a `SEEK` command for the current media session.
    @discardableResult
    func seek(
        to time: TimeInterval,
        resume: Bool? = nil
    ) async throws -> CastRequestID {
        let mediaSessionID = try requireMediaSessionID()
        return try await dispatcher.send(
            namespace: .media,
            target: .currentApplication,
            payload: CastMediaPayloadBuilder.seek(to: time, mediaSessionID: mediaSessionID, resume: resume)
        )
    }

    /// Sends a `SET_PLAYBACK_RATE` command for the current media session.
    @discardableResult
    func setPlaybackRate(_ rate: Double) async throws -> CastRequestID {
        let mediaSessionID = try requireMediaSessionID()
        return try await dispatcher.send(
            namespace: .media,
            target: .currentApplication,
            payload: CastMediaPayloadBuilder.setPlaybackRate(rate, mediaSessionID: mediaSessionID)
        )
    }

    /// Inserts queue items into the current media session queue.
    @discardableResult
    func queueInsert(
        items: [CastQueueItem],
        options: QueueInsertOptions = .init()
    ) async throws -> CastRequestID {
        let mediaSessionID = try requireMediaSessionID()
        return try await dispatcher.send(
            namespace: .media,
            target: .currentApplication,
            payload: CastMediaPayloadBuilder.queueInsert(
                items: items,
                mediaSessionID: mediaSessionID,
                options: .init(
                    currentItemID: options.currentItemID,
                    currentItemIndex: options.currentItemIndex,
                    currentTime: options.currentTime,
                    insertBeforeItemID: options.insertBeforeItemID
                )
            )
        )
    }

    /// Removes queue items from the current media session queue.
    @discardableResult
    func queueRemove(
        itemIDs: [CastQueueItemID],
        options: QueueRemoveOptions = .init()
    ) async throws -> CastRequestID {
        let mediaSessionID = try requireMediaSessionID()
        return try await dispatcher.send(
            namespace: .media,
            target: .currentApplication,
            payload: CastMediaPayloadBuilder.queueRemove(
                itemIDs: itemIDs,
                mediaSessionID: mediaSessionID,
                options: .init(
                    currentItemID: options.currentItemID,
                    currentTime: options.currentTime
                )
            )
        )
    }

    /// Reorders queue items in the current media session queue.
    @discardableResult
    func queueReorder(
        itemIDs: [CastQueueItemID],
        options: QueueReorderOptions = .init()
    ) async throws -> CastRequestID {
        let mediaSessionID = try requireMediaSessionID()
        return try await dispatcher.send(
            namespace: .media,
            target: .currentApplication,
            payload: CastMediaPayloadBuilder.queueReorder(
                itemIDs: itemIDs,
                mediaSessionID: mediaSessionID,
                options: .init(
                    currentItemID: options.currentItemID,
                    currentTime: options.currentTime,
                    insertBeforeItemID: options.insertBeforeItemID
                )
            )
        )
    }

    /// Updates queue state or items in the current media session queue.
    @discardableResult
    func queueUpdate(
        items: [CastQueueItem]? = nil,
        options: QueueUpdateOptions = .init()
    ) async throws -> CastRequestID {
        let mediaSessionID = try requireMediaSessionID()
        return try await dispatcher.send(
            namespace: .media,
            target: .currentApplication,
            payload: CastMediaPayloadBuilder.queueUpdate(
                items: items,
                mediaSessionID: mediaSessionID,
                options: .init(
                    currentItemID: options.currentItemID,
                    currentTime: options.currentTime,
                    jump: options.jump,
                    repeatMode: options.repeatMode
                )
            )
        )
    }

    private func requireMediaSessionID() throws -> CastMediaSessionID {
        guard let mediaSessionID else {
            throw CastError.noActiveMediaSession
        }
        return mediaSessionID
    }
}
