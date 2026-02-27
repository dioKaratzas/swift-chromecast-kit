//
//  ChromecastKit
//  SPDX-License-Identifier: Apache-2.0
//  Copyright 2026 Dionysis Karatzas
//

import Foundation

extension CastWire.Media {
    /// Wire response for `MEDIA_STATUS`.
    struct StatusResponse: Sendable, Hashable, Codable {
        let type: CastMediaMessageType
        let status: [Status]

        init(
            type: CastMediaMessageType = .mediaStatus,
            status: [Status]
        ) {
            self.type = type
            self.status = status
        }
    }
}

extension CastWire.Media {
    /// Wire media session status entry from `MEDIA_STATUS`.
    struct Status: Sendable, Hashable, Codable {
        let mediaSessionId: CastMediaSessionID?
        let playerState: CastPlayerState?
        let idleReason: CastIdleReason?
        let currentTime: TimeInterval?
        let playbackRate: Double?
        let supportedMediaCommands: UInt64?
        let volume: ReceiverVolume?
        let activeTrackIds: [CastMediaTrackID]?
        let currentItemId: CastQueueItemID?
        let loadingItemId: CastQueueItemID?
        let repeatMode: CastQueueRepeatMode?
        let media: StatusMedia?

        init(
            mediaSessionId: CastMediaSessionID? = nil,
            playerState: CastPlayerState? = nil,
            idleReason: CastIdleReason? = nil,
            currentTime: TimeInterval? = nil,
            playbackRate: Double? = nil,
            supportedMediaCommands: UInt64? = nil,
            volume: ReceiverVolume? = nil,
            activeTrackIds: [CastMediaTrackID]? = nil,
            currentItemId: CastQueueItemID? = nil,
            loadingItemId: CastQueueItemID? = nil,
            repeatMode: CastQueueRepeatMode? = nil,
            media: StatusMedia? = nil
        ) {
            self.mediaSessionId = mediaSessionId
            self.playerState = playerState
            self.idleReason = idleReason
            self.currentTime = currentTime
            self.playbackRate = playbackRate
            self.supportedMediaCommands = supportedMediaCommands
            self.volume = volume
            self.activeTrackIds = activeTrackIds
            self.currentItemId = currentItemId
            self.loadingItemId = loadingItemId
            self.repeatMode = repeatMode
            self.media = media
        }
    }
}

extension CastWire.Media {
    /// Receiver-reported volume embedded in media status.
    struct ReceiverVolume: Sendable, Hashable, Codable {
        let level: Double?
        let muted: Bool?

        init(level: Double? = nil, muted: Bool? = nil) {
            self.level = level
            self.muted = muted
        }
    }
}

extension CastWire.Media {
    /// Media object embedded in a `MEDIA_STATUS` response.
    struct StatusMedia: Sendable, Hashable, Codable {
        let contentId: String?
        let contentType: String?
        let streamType: CastStreamType?
        let metadata: Metadata?
        let duration: TimeInterval?
        let tracks: [Track]?

        init(
            contentId: String? = nil,
            contentType: String? = nil,
            streamType: CastStreamType? = nil,
            metadata: Metadata? = nil,
            duration: TimeInterval? = nil,
            tracks: [Track]? = nil
        ) {
            self.contentId = contentId
            self.contentType = contentType
            self.streamType = streamType
            self.metadata = metadata
            self.duration = duration
            self.tracks = tracks
        }
    }
}
