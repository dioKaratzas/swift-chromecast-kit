//
//  ChromecastKit
//  Swift package for Google Cast (Chromecast).
//

import Foundation

public extension CastWire.Media {
    /// Wire response for `MEDIA_STATUS`.
    struct StatusResponse: Sendable, Hashable, Codable {
        public let type: CastMediaMessageType
        public let status: [Status]

        public init(
            type: CastMediaMessageType = .mediaStatus,
            status: [Status]
        ) {
            self.type = type
            self.status = status
        }
    }
}

public extension CastWire.Media {
    /// Wire media session status entry from `MEDIA_STATUS`.
    struct Status: Sendable, Hashable, Codable {
        public let mediaSessionId: CastMediaSessionID?
        public let playerState: CastPlayerState?
        public let idleReason: CastIdleReason?
        public let currentTime: TimeInterval?
        public let playbackRate: Double?
        public let supportedMediaCommands: UInt64?
        public let volume: ReceiverVolume?
        public let activeTrackIds: [CastMediaTrackID]?
        public let media: StatusMedia?

        public init(
            mediaSessionId: CastMediaSessionID? = nil,
            playerState: CastPlayerState? = nil,
            idleReason: CastIdleReason? = nil,
            currentTime: TimeInterval? = nil,
            playbackRate: Double? = nil,
            supportedMediaCommands: UInt64? = nil,
            volume: ReceiverVolume? = nil,
            activeTrackIds: [CastMediaTrackID]? = nil,
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
            self.media = media
        }
    }
}

public extension CastWire.Media {
    /// Receiver-reported volume embedded in media status.
    struct ReceiverVolume: Sendable, Hashable, Codable {
        public let level: Double?
        public let muted: Bool?

        public init(level: Double? = nil, muted: Bool? = nil) {
            self.level = level
            self.muted = muted
        }
    }
}

public extension CastWire.Media {
    /// Media object embedded in a `MEDIA_STATUS` response.
    struct StatusMedia: Sendable, Hashable, Codable {
        public let contentId: String?
        public let contentType: String?
        public let streamType: CastStreamType?
        public let metadata: Metadata?
        public let duration: TimeInterval?
        public let tracks: [Track]?

        public init(
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
