//
//  ChromecastKit
//  Swift package for Google Cast (Chromecast).
//

import Foundation

/// Cast stream type as defined by the media protocol.
public enum CastStreamType: String, Sendable, Hashable, Codable {
    case buffered = "BUFFERED"
    case live = "LIVE"
    case none = "NONE"
    case unknown = "UNKNOWN"
}

/// Image metadata for cover art and media previews.
public struct CastImage: Sendable, Hashable, Codable {
    public var url: URL
    public var width: Int?
    public var height: Int?

    public init(url: URL, width: Int? = nil, height: Int? = nil) {
        self.url = url
        self.width = width
        self.height = height
    }
}

/// Generic media metadata used for most video/audio content.
public struct CastGenericMediaMetadata: Sendable, Hashable, Codable {
    public var title: String?
    public var subtitle: String?
    public var images: [CastImage]

    public init(
        title: String? = nil,
        subtitle: String? = nil,
        images: [CastImage] = []
    ) {
        self.title = title
        self.subtitle = subtitle
        self.images = images
    }
}

/// Movie-specific metadata.
public struct CastMovieMediaMetadata: Sendable, Hashable, Codable {
    public var title: String?
    public var subtitle: String?
    public var studio: String?
    public var releaseDate: Date?
    public var images: [CastImage]

    public init(
        title: String? = nil,
        subtitle: String? = nil,
        studio: String? = nil,
        releaseDate: Date? = nil,
        images: [CastImage] = []
    ) {
        self.title = title
        self.subtitle = subtitle
        self.studio = studio
        self.releaseDate = releaseDate
        self.images = images
    }
}

/// TV episode metadata.
public struct CastTVShowMediaMetadata: Sendable, Hashable, Codable {
    public var title: String?
    public var seriesTitle: String?
    public var season: Int?
    public var episode: Int?
    public var images: [CastImage]

    public init(
        title: String? = nil,
        seriesTitle: String? = nil,
        season: Int? = nil,
        episode: Int? = nil,
        images: [CastImage] = []
    ) {
        self.title = title
        self.seriesTitle = seriesTitle
        self.season = season
        self.episode = episode
        self.images = images
    }
}

/// Music track metadata.
public struct CastMusicTrackMetadata: Sendable, Hashable, Codable {
    public var title: String?
    public var artist: String?
    public var albumName: String?
    public var albumArtist: String?
    public var trackNumber: Int?
    public var images: [CastImage]

    public init(
        title: String? = nil,
        artist: String? = nil,
        albumName: String? = nil,
        albumArtist: String? = nil,
        trackNumber: Int? = nil,
        images: [CastImage] = []
    ) {
        self.title = title
        self.artist = artist
        self.albumName = albumName
        self.albumArtist = albumArtist
        self.trackNumber = trackNumber
        self.images = images
    }
}

/// Photo metadata.
public struct CastPhotoMediaMetadata: Sendable, Hashable, Codable {
    public var title: String?
    public var location: String?
    public var images: [CastImage]

    public init(
        title: String? = nil,
        location: String? = nil,
        images: [CastImage] = []
    ) {
        self.title = title
        self.location = location
        self.images = images
    }
}

/// Strongly-typed media metadata variants.
public enum CastMediaMetadata: Sendable, Hashable, Codable {
    case generic(CastGenericMediaMetadata)
    case movie(CastMovieMediaMetadata)
    case tvShow(CastTVShowMediaMetadata)
    case musicTrack(CastMusicTrackMetadata)
    case photo(CastPhotoMediaMetadata)

    /// Convenience constructor for generic metadata.
    public static func generic(
        title: String? = nil,
        subtitle: String? = nil,
        images: [CastImage] = []
    ) -> Self {
        .generic(.init(title: title, subtitle: subtitle, images: images))
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case value
    }

    private enum Kind: String, Codable {
        case generic
        case movie
        case tvShow
        case musicTrack
        case photo
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)

        switch kind {
        case .generic:
            self = try .generic(container.decode(CastGenericMediaMetadata.self, forKey: .value))
        case .movie:
            self = try .movie(container.decode(CastMovieMediaMetadata.self, forKey: .value))
        case .tvShow:
            self = try .tvShow(container.decode(CastTVShowMediaMetadata.self, forKey: .value))
        case .musicTrack:
            self = try .musicTrack(container.decode(CastMusicTrackMetadata.self, forKey: .value))
        case .photo:
            self = try .photo(container.decode(CastPhotoMediaMetadata.self, forKey: .value))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case let .generic(value):
            try container.encode(Kind.generic, forKey: .kind)
            try container.encode(value, forKey: .value)
        case let .movie(value):
            try container.encode(Kind.movie, forKey: .kind)
            try container.encode(value, forKey: .value)
        case let .tvShow(value):
            try container.encode(Kind.tvShow, forKey: .kind)
            try container.encode(value, forKey: .value)
        case let .musicTrack(value):
            try container.encode(Kind.musicTrack, forKey: .kind)
            try container.encode(value, forKey: .value)
        case let .photo(value):
            try container.encode(Kind.photo, forKey: .kind)
            try container.encode(value, forKey: .value)
        }
    }
}

/// Text track kind supported by the default media receiver.
public enum CastTextTrackKind: String, Sendable, Hashable, Codable {
    case text = "TEXT"
}

/// Text track subtype indicating the intended accessibility/UX role.
public enum CastTextTrackSubtype: String, Sendable, Hashable, Codable {
    case subtitles = "SUBTITLES"
    case captions = "CAPTIONS"
    case descriptions = "DESCRIPTIONS"
    case chapters = "CHAPTERS"
    case metadata = "METADATA"
}

/// A subtitle/caption track associated with a media item.
public struct CastTextTrack: Sendable, Hashable, Codable, Identifiable {
    public var id: CastMediaTrackID
    public var kind: CastTextTrackKind
    public var subtype: CastTextTrackSubtype?
    public var name: String
    public var languageCode: String
    public var contentURL: URL
    public var contentType: String

    public init(
        id: CastMediaTrackID,
        kind: CastTextTrackKind = .text,
        subtype: CastTextTrackSubtype? = .subtitles,
        name: String,
        languageCode: String,
        contentURL: URL,
        contentType: String = "text/vtt"
    ) {
        self.id = id
        self.kind = kind
        self.subtype = subtype
        self.name = name
        self.languageCode = languageCode
        self.contentURL = contentURL
        self.contentType = contentType
    }

    /// Creates a VTT subtitle track with sensible defaults for Cast receivers.
    public static func subtitleVTT(
        id: CastMediaTrackID,
        name: String,
        languageCode: String,
        url: URL
    ) -> Self {
        .init(
            id: id,
            kind: .text,
            subtype: .subtitles,
            name: name,
            languageCode: languageCode,
            contentURL: url,
            contentType: "text/vtt"
        )
    }
}

/// Text track edge rendering style.
public enum CastTextTrackEdgeType: String, Sendable, Hashable, Codable {
    case none = "NONE"
    case outline = "OUTLINE"
    case dropShadow = "DROP_SHADOW"
    case raised = "RAISED"
    case depressed = "DEPRESSED"
}

/// Font style for subtitles/captions.
public enum CastTextTrackFontStyle: String, Sendable, Hashable, Codable {
    case normal = "NORMAL"
    case bold = "BOLD"
    case boldItalic = "BOLD_ITALIC"
    case italic = "ITALIC"
}

/// Generic font family classification used by the Cast receiver.
public enum CastTextTrackFontGenericFamily: String, Sendable, Hashable, Codable {
    case sansSerif = "SANS_SERIF"
    case monospacedSansSerif = "MONOSPACED_SANS_SERIF"
    case serif = "SERIF"
    case monospacedSerif = "MONOSPACED_SERIF"
    case casual = "CASUAL"
    case cursive = "CURSIVE"
    case smallCapitals = "SMALL_CAPITALS"
}

/// Subtitle window rendering mode.
public enum CastTextTrackWindowType: String, Sendable, Hashable, Codable {
    case none = "NONE"
    case normal = "NORMAL"
    case roundedCorners = "ROUNDED_CORNERS"
}

/// Visual styling for text tracks.
public struct CastTextTrackStyle: Sendable, Hashable, Codable {
    public var backgroundColorRGBAHex: String?
    public var foregroundColorRGBAHex: String?
    public var edgeType: CastTextTrackEdgeType?
    public var edgeColorRGBAHex: String?
    public var fontScale: Double?
    public var fontStyle: CastTextTrackFontStyle?
    public var fontFamily: String?
    public var fontGenericFamily: CastTextTrackFontGenericFamily?
    public var windowColorRGBAHex: String?
    public var windowRoundedCornerRadius: Int?
    public var windowType: CastTextTrackWindowType?

    public init(
        backgroundColorRGBAHex: String? = nil,
        foregroundColorRGBAHex: String? = nil,
        edgeType: CastTextTrackEdgeType? = nil,
        edgeColorRGBAHex: String? = nil,
        fontScale: Double? = nil,
        fontStyle: CastTextTrackFontStyle? = nil,
        fontFamily: String? = nil,
        fontGenericFamily: CastTextTrackFontGenericFamily? = nil,
        windowColorRGBAHex: String? = nil,
        windowRoundedCornerRadius: Int? = nil,
        windowType: CastTextTrackWindowType? = nil
    ) {
        self.backgroundColorRGBAHex = backgroundColorRGBAHex
        self.foregroundColorRGBAHex = foregroundColorRGBAHex
        self.edgeType = edgeType
        self.edgeColorRGBAHex = edgeColorRGBAHex
        self.fontScale = fontScale
        self.fontStyle = fontStyle
        self.fontFamily = fontFamily
        self.fontGenericFamily = fontGenericFamily
        self.windowColorRGBAHex = windowColorRGBAHex
        self.windowRoundedCornerRadius = windowRoundedCornerRadius
        self.windowType = windowType
    }
}

/// A media item to be loaded in the default media receiver or compatible apps.
public struct CastMediaItem: Sendable, Hashable, Codable {
    public var contentURL: URL
    public var contentType: String
    public var streamType: CastStreamType
    public var metadata: CastMediaMetadata
    public var textTracks: [CastTextTrack]
    public var textTrackStyle: CastTextTrackStyle?
    public var customData: JSONValue?

    public init(
        contentURL: URL,
        contentType: String,
        streamType: CastStreamType = .buffered,
        metadata: CastMediaMetadata = .generic(),
        textTracks: [CastTextTrack] = [],
        textTrackStyle: CastTextTrackStyle? = nil,
        customData: JSONValue? = nil
    ) {
        self.contentURL = contentURL
        self.contentType = contentType
        self.streamType = streamType
        self.metadata = metadata
        self.textTracks = textTracks
        self.textTrackStyle = textTrackStyle
        self.customData = customData
    }
}

/// Queue repeat behavior supported by the Cast media queue APIs.
public enum CastQueueRepeatMode: String, Sendable, Hashable, Codable {
    case off = "REPEAT_OFF"
    case all = "REPEAT_ALL"
    case single = "REPEAT_SINGLE"
    case allAndShuffle = "REPEAT_ALL_AND_SHUFFLE"
}

/// A queue entry for Cast queue load/insert/update commands.
public struct CastQueueItem: Sendable, Hashable, Codable {
    public var itemID: CastQueueItemID?
    public var media: CastMediaItem
    public var autoplay: Bool?
    public var startTime: TimeInterval?
    public var preloadTime: TimeInterval?
    public var activeTextTrackIDs: [CastMediaTrackID]
    public var customData: JSONValue?

    public init(
        itemID: CastQueueItemID? = nil,
        media: CastMediaItem,
        autoplay: Bool? = nil,
        startTime: TimeInterval? = nil,
        preloadTime: TimeInterval? = nil,
        activeTextTrackIDs: [CastMediaTrackID] = [],
        customData: JSONValue? = nil
    ) {
        self.itemID = itemID
        self.media = media
        self.autoplay = autoplay
        self.startTime = startTime
        self.preloadTime = preloadTime
        self.activeTextTrackIDs = activeTextTrackIDs
        self.customData = customData
    }
}

/// Playback state reported by the Cast media channel.
public enum CastPlayerState: String, Sendable, Hashable, Codable {
    case playing = "PLAYING"
    case buffering = "BUFFERING"
    case paused = "PAUSED"
    case idle = "IDLE"
    case unknown = "UNKNOWN"
}

/// The reason a media session became idle.
public enum CastIdleReason: String, Sendable, Hashable, Codable {
    case cancelled = "CANCELLED"
    case interrupted = "INTERRUPTED"
    case finished = "FINISHED"
    case error = "ERROR"
}

/// Supported commands bitset advertised by the receiver for the current media item.
public struct CastMediaCommandSet: OptionSet, Sendable, Hashable, Codable {
    public let rawValue: UInt64

    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public static let pause = Self(rawValue: 1 << 0)
    public static let seek = Self(rawValue: 1 << 1)
    public static let streamVolume = Self(rawValue: 1 << 2)
    public static let streamMute = Self(rawValue: 1 << 3)
    public static let queueNext = Self(rawValue: 1 << 6)
    public static let queuePrevious = Self(rawValue: 1 << 7)
    public static let queueShuffle = Self(rawValue: 1 << 8)
    /// Includes all repeat flags as a single mask.
    public static let queueRepeat = Self(rawValue: 0xC00)
    public static let editTracks = Self(rawValue: 1 << 12)
    public static let playbackRate = Self(rawValue: 1 << 13)

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(rawValue: container.decode(UInt64.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// Snapshot of the current media session status.
public struct CastMediaStatus: Sendable, Hashable, Codable {
    public let currentTime: TimeInterval
    public let duration: TimeInterval?
    public let playbackRate: Double
    public let playerState: CastPlayerState
    public let idleReason: CastIdleReason?
    public let streamType: CastStreamType
    public let mediaSessionID: CastMediaSessionID?
    public let contentURL: URL?
    public let contentType: String?
    public let metadata: CastMediaMetadata?
    public let textTracks: [CastTextTrack]
    public let activeTextTrackIDs: [CastMediaTrackID]
    public let queueCurrentItemID: CastQueueItemID?
    public let queueLoadingItemID: CastQueueItemID?
    public let queueRepeatMode: CastQueueRepeatMode?
    public let volume: CastVolumeStatus
    public let supportedCommands: CastMediaCommandSet
    public let lastUpdated: Date

    public init(
        currentTime: TimeInterval = 0,
        duration: TimeInterval? = nil,
        playbackRate: Double = 1,
        playerState: CastPlayerState = .unknown,
        idleReason: CastIdleReason? = nil,
        streamType: CastStreamType = .unknown,
        mediaSessionID: CastMediaSessionID? = nil,
        contentURL: URL? = nil,
        contentType: String? = nil,
        metadata: CastMediaMetadata? = nil,
        textTracks: [CastTextTrack] = [],
        activeTextTrackIDs: [CastMediaTrackID] = [],
        queueCurrentItemID: CastQueueItemID? = nil,
        queueLoadingItemID: CastQueueItemID? = nil,
        queueRepeatMode: CastQueueRepeatMode? = nil,
        volume: CastVolumeStatus = .init(level: 1, muted: false),
        supportedCommands: CastMediaCommandSet = [],
        lastUpdated: Date = Date()
    ) {
        self.currentTime = currentTime
        self.duration = duration
        self.playbackRate = playbackRate
        self.playerState = playerState
        self.idleReason = idleReason
        self.streamType = streamType
        self.mediaSessionID = mediaSessionID
        self.contentURL = contentURL
        self.contentType = contentType
        self.metadata = metadata
        self.textTracks = textTracks
        self.activeTextTrackIDs = activeTextTrackIDs
        self.queueCurrentItemID = queueCurrentItemID
        self.queueLoadingItemID = queueLoadingItemID
        self.queueRepeatMode = queueRepeatMode
        self.volume = volume
        self.supportedCommands = supportedCommands
        self.lastUpdated = lastUpdated
    }

    /// A best-effort current time estimate that advances while playback is active.
    public var adjustedCurrentTime: TimeInterval {
        guard playerState == .playing else {
            return currentTime
        }
        return currentTime + (Date().timeIntervalSince(lastUpdated) * playbackRate)
    }

    /// `true` when the receiver reports active playback.
    public var isPlaying: Bool {
        playerState == .playing || playerState == .buffering
    }

    /// `true` when playback is paused.
    public var isPaused: Bool {
        playerState == .paused
    }

    /// `true` when the media session is idle.
    public var isIdle: Bool {
        playerState == .idle
    }
}
