//
//  ChromecastKit
//  SPDX-License-Identifier: Apache-2.0
//  Copyright 2026 Dionysis Karatzas
//

import Foundation

/// Namespace for Cast protocol wire-level models.
enum CastWire {
    /// Namespace for Cast media namespace wire-level request and payload models.
    enum Media {}
}

extension CastWire.Media {
    /// Resume state behavior for `SEEK` commands.
    enum ResumeState: String, Sendable, Hashable, Codable {
        case playbackStart = "PLAYBACK_START"
        case playbackPause = "PLAYBACK_PAUSE"
    }
}

extension CastWire.Media {
    /// Wire model for a media `GET_STATUS` request.
    struct GetStatusRequest: Sendable, Hashable, Codable {
        let type: CastMediaMessageType

        init(type: CastMediaMessageType = .getStatus) {
            self.type = type
        }
    }
}

extension CastWire.Media {
    /// Wire model for a media `PLAY` request.
    struct PlayRequest: Sendable, Hashable, Codable {
        let type: CastMediaMessageType
        let mediaSessionId: CastMediaSessionID

        init(
            type: CastMediaMessageType = .play,
            mediaSessionId: CastMediaSessionID
        ) {
            self.type = type
            self.mediaSessionId = mediaSessionId
        }
    }
}

extension CastWire.Media {
    /// Wire model for a media `PAUSE` request.
    struct PauseRequest: Sendable, Hashable, Codable {
        let type: CastMediaMessageType
        let mediaSessionId: CastMediaSessionID

        init(
            type: CastMediaMessageType = .pause,
            mediaSessionId: CastMediaSessionID
        ) {
            self.type = type
            self.mediaSessionId = mediaSessionId
        }
    }
}

extension CastWire.Media {
    /// Wire model for a media `STOP` request.
    struct StopRequest: Sendable, Hashable, Codable {
        let type: CastMediaMessageType
        let mediaSessionId: CastMediaSessionID

        init(
            type: CastMediaMessageType = .stop,
            mediaSessionId: CastMediaSessionID
        ) {
            self.type = type
            self.mediaSessionId = mediaSessionId
        }
    }
}

extension CastWire.Media {
    /// Wire model for a media `SEEK` request.
    struct SeekRequest: Sendable, Hashable, Codable {
        let type: CastMediaMessageType
        let mediaSessionId: CastMediaSessionID
        let currentTime: TimeInterval
        let resumeState: ResumeState?

        init(
            type: CastMediaMessageType = .seek,
            mediaSessionId: CastMediaSessionID,
            currentTime: TimeInterval,
            resumeState: ResumeState? = nil
        ) {
            self.type = type
            self.mediaSessionId = mediaSessionId
            self.currentTime = currentTime
            self.resumeState = resumeState
        }
    }
}

extension CastWire.Media {
    /// Wire model for a media `SET_PLAYBACK_RATE` request.
    struct SetPlaybackRateRequest: Sendable, Hashable, Codable {
        let type: CastMediaMessageType
        let mediaSessionId: CastMediaSessionID
        let playbackRate: Double

        init(
            type: CastMediaMessageType = .setPlaybackRate,
            mediaSessionId: CastMediaSessionID,
            playbackRate: Double
        ) {
            self.type = type
            self.mediaSessionId = mediaSessionId
            self.playbackRate = playbackRate
        }
    }
}

extension CastWire.Media {
    /// Wire model for a Cast media `LOAD` request.
    struct LoadRequest: Sendable, Hashable, Codable {
        let type: CastMediaMessageType
        let media: Information
        let autoplay: Bool
        let currentTime: TimeInterval?
        let activeTrackIds: [CastMediaTrackID]?
        let customData: JSONValue

        init(
            type: CastMediaMessageType = .load,
            media: Information,
            autoplay: Bool,
            currentTime: TimeInterval? = nil,
            activeTrackIds: [CastMediaTrackID]? = nil,
            customData: JSONValue = .object([:])
        ) {
            self.type = type
            self.media = media
            self.autoplay = autoplay
            self.currentTime = currentTime
            self.activeTrackIds = activeTrackIds
            self.customData = customData
        }
    }
}

extension CastWire.Media {
    /// Wire model for a Cast `EDIT_TRACKS_INFO` request.
    struct EditTracksInfoRequest: Sendable, Hashable, Codable {
        let type: CastMediaMessageType
        let mediaSessionId: CastMediaSessionID?
        let activeTrackIds: [CastMediaTrackID]?
        let textTrackStyle: TextTrackStyle?

        init(
            type: CastMediaMessageType = .editTracksInfo,
            mediaSessionId: CastMediaSessionID? = nil,
            activeTrackIds: [CastMediaTrackID]? = nil,
            textTrackStyle: TextTrackStyle? = nil
        ) {
            self.type = type
            self.mediaSessionId = mediaSessionId
            self.activeTrackIds = activeTrackIds
            self.textTrackStyle = textTrackStyle
        }
    }
}

extension CastWire.Media {
    /// Wire model for Cast media information in `LOAD` requests.
    struct Information: Sendable, Hashable, Codable {
        let contentId: String
        let contentType: String
        let streamType: CastStreamType
        let metadata: Metadata
        let tracks: [Track]?
        let textTrackStyle: TextTrackStyle?
        let customData: JSONValue?

        init(
            contentId: String,
            contentType: String,
            streamType: CastStreamType,
            metadata: Metadata,
            tracks: [Track]? = nil,
            textTrackStyle: TextTrackStyle? = nil,
            customData: JSONValue? = nil
        ) {
            self.contentId = contentId
            self.contentType = contentType
            self.streamType = streamType
            self.metadata = metadata
            self.tracks = tracks
            self.textTrackStyle = textTrackStyle
            self.customData = customData
        }
    }
}

extension CastWire.Media {
    /// Wire model for Cast media metadata.
    struct Metadata: Sendable, Hashable, Codable {
        let metadataType: Int
        let title: String?
        let subtitle: String?
        let seriesTitle: String?
        let season: Int?
        let episode: Int?
        let studio: String?
        let releaseDate: String?
        let artist: String?
        let albumName: String?
        let albumArtist: String?
        let track: Int?
        let location: String?
        let images: [Image]?

        init(
            metadataType: Int,
            title: String? = nil,
            subtitle: String? = nil,
            seriesTitle: String? = nil,
            season: Int? = nil,
            episode: Int? = nil,
            studio: String? = nil,
            releaseDate: String? = nil,
            artist: String? = nil,
            albumName: String? = nil,
            albumArtist: String? = nil,
            track: Int? = nil,
            location: String? = nil,
            images: [Image]? = nil
        ) {
            self.metadataType = metadataType
            self.title = title
            self.subtitle = subtitle
            self.seriesTitle = seriesTitle
            self.season = season
            self.episode = episode
            self.studio = studio
            self.releaseDate = releaseDate
            self.artist = artist
            self.albumName = albumName
            self.albumArtist = albumArtist
            self.track = track
            self.location = location
            self.images = images
        }
    }
}

extension CastWire.Media {
    /// Wire model for Cast media artwork/image metadata.
    struct Image: Sendable, Hashable, Codable {
        let url: String
        let width: Int?
        let height: Int?

        init(url: String, width: Int? = nil, height: Int? = nil) {
            self.url = url
            self.width = width
            self.height = height
        }
    }
}

extension CastWire.Media {
    /// Wire model for Cast subtitle/caption tracks.
    struct Track: Sendable, Hashable, Codable {
        let trackId: CastMediaTrackID
        let type: CastTextTrackKind
        let name: String
        let language: String
        let trackContentId: String
        let trackContentType: String
        let subtype: CastTextTrackSubtype?

        init(
            trackId: CastMediaTrackID,
            type: CastTextTrackKind,
            name: String,
            language: String,
            trackContentId: String,
            trackContentType: String,
            subtype: CastTextTrackSubtype? = nil
        ) {
            self.trackId = trackId
            self.type = type
            self.name = name
            self.language = language
            self.trackContentId = trackContentId
            self.trackContentType = trackContentType
            self.subtype = subtype
        }
    }
}

extension CastWire.Media {
    /// Wire model for text track style edits and media style configuration.
    struct TextTrackStyle: Sendable, Hashable, Codable {
        let backgroundColor: String?
        let foregroundColor: String?
        let edgeType: CastTextTrackEdgeType?
        let edgeColor: String?
        let fontScale: Double?
        let fontStyle: CastTextTrackFontStyle?
        let fontFamily: String?
        let fontGenericFamily: CastTextTrackFontGenericFamily?
        let windowColor: String?
        let windowRoundedCornerRadius: Int?
        let windowType: CastTextTrackWindowType?

        init(
            backgroundColor: String? = nil,
            foregroundColor: String? = nil,
            edgeType: CastTextTrackEdgeType? = nil,
            edgeColor: String? = nil,
            fontScale: Double? = nil,
            fontStyle: CastTextTrackFontStyle? = nil,
            fontFamily: String? = nil,
            fontGenericFamily: CastTextTrackFontGenericFamily? = nil,
            windowColor: String? = nil,
            windowRoundedCornerRadius: Int? = nil,
            windowType: CastTextTrackWindowType? = nil
        ) {
            self.backgroundColor = backgroundColor
            self.foregroundColor = foregroundColor
            self.edgeType = edgeType
            self.edgeColor = edgeColor
            self.fontScale = fontScale
            self.fontStyle = fontStyle
            self.fontFamily = fontFamily
            self.fontGenericFamily = fontGenericFamily
            self.windowColor = windowColor
            self.windowRoundedCornerRadius = windowRoundedCornerRadius
            self.windowType = windowType
        }
    }
}
