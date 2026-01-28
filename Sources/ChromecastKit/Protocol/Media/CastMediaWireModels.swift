//
//  ChromecastKit
//  Swift package for Google Cast (Chromecast).
//

import Foundation

/// Namespace for Cast protocol wire-level models.
public enum CastWire {
    /// Namespace for Cast media namespace wire-level request and payload models.
    public enum Media {}
}

public extension CastWire.Media {
    /// Wire model for a Cast media `LOAD` request.
    struct LoadRequest: Sendable, Hashable, Codable {
        public let type: CastMediaMessageType
        public let media: Information
        public let autoplay: Bool
        public let currentTime: TimeInterval?
        public let activeTrackIds: [Int]?
        public let customData: JSONValue

        public init(
            type: CastMediaMessageType = .load,
            media: Information,
            autoplay: Bool,
            currentTime: TimeInterval? = nil,
            activeTrackIds: [Int]? = nil,
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

public extension CastWire.Media {
    /// Wire model for a Cast `EDIT_TRACKS_INFO` request.
    struct EditTracksInfoRequest: Sendable, Hashable, Codable {
        public let type: CastMediaMessageType
        public let activeTrackIds: [Int]?
        public let textTrackStyle: TextTrackStyle?

        public init(
            type: CastMediaMessageType = .editTracksInfo,
            activeTrackIds: [Int]? = nil,
            textTrackStyle: TextTrackStyle? = nil
        ) {
            self.type = type
            self.activeTrackIds = activeTrackIds
            self.textTrackStyle = textTrackStyle
        }
    }
}

public extension CastWire.Media {
    /// Wire model for Cast media information in `LOAD` requests.
    struct Information: Sendable, Hashable, Codable {
        public let contentId: String
        public let contentType: String
        public let streamType: CastStreamType
        public let metadata: Metadata
        public let tracks: [Track]?
        public let textTrackStyle: TextTrackStyle?
        public let customData: JSONValue?

        public init(
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

public extension CastWire.Media {
    /// Wire model for Cast media metadata.
    struct Metadata: Sendable, Hashable, Codable {
        public let metadataType: Int
        public let title: String?
        public let subtitle: String?
        public let seriesTitle: String?
        public let season: Int?
        public let episode: Int?
        public let studio: String?
        public let releaseDate: String?
        public let artist: String?
        public let albumName: String?
        public let albumArtist: String?
        public let track: Int?
        public let location: String?
        public let images: [Image]?

        public init(
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

public extension CastWire.Media {
    /// Wire model for Cast media artwork/image metadata.
    struct Image: Sendable, Hashable, Codable {
        public let url: String
        public let width: Int?
        public let height: Int?

        public init(url: String, width: Int? = nil, height: Int? = nil) {
            self.url = url
            self.width = width
            self.height = height
        }
    }
}

public extension CastWire.Media {
    /// Wire model for Cast subtitle/caption tracks.
    struct Track: Sendable, Hashable, Codable {
        public let trackId: Int
        public let type: CastTextTrackKind
        public let name: String
        public let language: String
        public let trackContentId: String
        public let trackContentType: String
        public let subtype: CastTextTrackSubtype?

        public init(
            trackId: Int,
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

public extension CastWire.Media {
    /// Wire model for text track style edits and media style configuration.
    struct TextTrackStyle: Sendable, Hashable, Codable {
        public let backgroundColor: String?
        public let foregroundColor: String?
        public let edgeType: CastTextTrackEdgeType?
        public let edgeColor: String?
        public let fontScale: Double?
        public let fontStyle: CastTextTrackFontStyle?
        public let fontFamily: String?
        public let fontGenericFamily: CastTextTrackFontGenericFamily?
        public let windowColor: String?
        public let windowRoundedCornerRadius: Int?
        public let windowType: CastTextTrackWindowType?

        public init(
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
