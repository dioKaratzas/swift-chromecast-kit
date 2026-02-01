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
    private let dispatcher: CastCommandDispatcher
    private var mediaSessionID: CastMediaSessionID?

    init(dispatcher: CastCommandDispatcher) {
        self.dispatcher = dispatcher
    }

    /// Sets the active media session ID used for session-bound media commands.
    ///
    /// This is typically sourced from media status updates after a `LOAD` succeeds.
    public func setMediaSessionID(_ mediaSessionID: CastMediaSessionID?) {
        self.mediaSessionID = mediaSessionID
    }

    /// Requests media status from the active media transport.
    @discardableResult
    public func getStatus() async throws -> CastRequestID {
        try await dispatcher.send(
            namespace: .media,
            target: .currentApplication,
            payload: CastMediaPayloadBuilder.getStatus()
        )
    }

    /// Loads media into the active media receiver/app transport.
    @discardableResult
    public func load(
        _ item: CastMediaItem,
        options: CastMediaPayloadBuilder.LoadOptions = .init()
    ) async throws -> CastRequestID {
        try await dispatcher.send(
            namespace: .media,
            target: .currentApplication,
            payload: CastMediaPayloadBuilder.load(item: item, options: options)
        )
    }

    /// Enables a text track by Cast track ID.
    @discardableResult
    public func enableTextTrack(id: CastMediaTrackID) async throws -> CastRequestID {
        let mediaSessionID = try requireMediaSessionID()
        return try await dispatcher.send(
            namespace: .media,
            target: .currentApplication,
            payload: CastMediaPayloadBuilder.enableTextTrack(trackID: id, mediaSessionID: mediaSessionID)
        )
    }

    /// Disables all active text tracks.
    @discardableResult
    public func disableTextTracks() async throws -> CastRequestID {
        let mediaSessionID = try requireMediaSessionID()
        return try await dispatcher.send(
            namespace: .media,
            target: .currentApplication,
            payload: CastMediaPayloadBuilder.disableTextTracks(mediaSessionID: mediaSessionID)
        )
    }

    /// Updates text track styling for the current media session.
    @discardableResult
    public func setTextTrackStyle(_ style: CastTextTrackStyle) async throws -> CastRequestID {
        let mediaSessionID = try requireMediaSessionID()
        return try await dispatcher.send(
            namespace: .media,
            target: .currentApplication,
            payload: CastMediaPayloadBuilder.textTrackStyle(style, mediaSessionID: mediaSessionID)
        )
    }

    /// Sends a `PLAY` command for the current media session.
    @discardableResult
    public func play() async throws -> CastRequestID {
        let mediaSessionID = try requireMediaSessionID()
        return try await dispatcher.send(
            namespace: .media,
            target: .currentApplication,
            payload: CastMediaPayloadBuilder.play(mediaSessionID: mediaSessionID)
        )
    }

    /// Sends a `PAUSE` command for the current media session.
    @discardableResult
    public func pause() async throws -> CastRequestID {
        let mediaSessionID = try requireMediaSessionID()
        return try await dispatcher.send(
            namespace: .media,
            target: .currentApplication,
            payload: CastMediaPayloadBuilder.pause(mediaSessionID: mediaSessionID)
        )
    }

    /// Sends a `STOP` command for the current media session.
    @discardableResult
    public func stop() async throws -> CastRequestID {
        let mediaSessionID = try requireMediaSessionID()
        return try await dispatcher.send(
            namespace: .media,
            target: .currentApplication,
            payload: CastMediaPayloadBuilder.stop(mediaSessionID: mediaSessionID)
        )
    }

    /// Sends a `SEEK` command for the current media session.
    @discardableResult
    public func seek(
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
    public func setPlaybackRate(_ rate: Double) async throws -> CastRequestID {
        let mediaSessionID = try requireMediaSessionID()
        return try await dispatcher.send(
            namespace: .media,
            target: .currentApplication,
            payload: CastMediaPayloadBuilder.setPlaybackRate(rate, mediaSessionID: mediaSessionID)
        )
    }

    private func requireMediaSessionID() throws -> CastMediaSessionID {
        guard let mediaSessionID else {
            throw CastError.noActiveMediaSession
        }
        return mediaSessionID
    }
}
