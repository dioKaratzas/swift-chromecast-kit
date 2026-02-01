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

    init(dispatcher: CastCommandDispatcher) {
        self.dispatcher = dispatcher
    }

    /// Loads media into the active media receiver/app transport.
    @discardableResult
    public func load(
        _ item: CastMediaItem,
        options: CastMediaPayloadBuilder.LoadOptions = .init()
    ) async throws -> Int {
        try await dispatcher.send(
            namespace: .media,
            target: .currentApplication,
            payload: CastMediaPayloadBuilder.load(item: item, options: options)
        )
    }

    /// Enables a text track by Cast track ID.
    @discardableResult
    public func enableTextTrack(id: Int) async throws -> Int {
        try await dispatcher.send(
            namespace: .media,
            target: .currentApplication,
            payload: CastMediaPayloadBuilder.enableTextTrack(trackID: id)
        )
    }

    /// Disables all active text tracks.
    @discardableResult
    public func disableTextTracks() async throws -> Int {
        try await dispatcher.send(
            namespace: .media,
            target: .currentApplication,
            payload: CastMediaPayloadBuilder.disableTextTracks()
        )
    }

    /// Updates text track styling for the current media session.
    @discardableResult
    public func setTextTrackStyle(_ style: CastTextTrackStyle) async throws -> Int {
        try await dispatcher.send(
            namespace: .media,
            target: .currentApplication,
            payload: CastMediaPayloadBuilder.textTrackStyle(style)
        )
    }
}

