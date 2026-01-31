//
//  ChromecastKit
//  Swift package for Google Cast (Chromecast).
//

import Foundation

/// Helpers that map typed public models into typed Cast wire request models.
///
/// `JSONValue` is used only for truly dynamic fields (for example `customData`).
/// Standardized Cast payloads should be represented as typed wire models.
public enum CastMediaPayloadBuilder {
    /// Options used to build a Cast `LOAD` media request.
    public struct LoadOptions: Sendable, Hashable, Codable {
        public var autoplay: Bool
        public var startTime: TimeInterval?
        public var activeTextTrackIDs: [Int]
        public var customData: JSONValue?

        public init(
            autoplay: Bool = true,
            startTime: TimeInterval? = nil,
            activeTextTrackIDs: [Int] = [],
            customData: JSONValue? = nil
        ) {
            self.autoplay = autoplay
            self.startTime = startTime
            self.activeTextTrackIDs = activeTextTrackIDs
            self.customData = customData
        }
    }

    /// Builds a typed `LOAD` request for the default media receiver.
    public static func load(
        item: CastMediaItem,
        options: LoadOptions = .init()
    ) -> CastWire.Media.LoadRequest {
        CastWire.Media.LoadRequest(
            media: mediaInformation(from: item),
            autoplay: options.autoplay,
            currentTime: options.startTime,
            activeTrackIds: options.activeTextTrackIDs.isEmpty ? nil : options.activeTextTrackIDs,
            customData: options.customData ?? .object([:])
        )
    }

    /// Builds an `EDIT_TRACKS_INFO` request to enable one text track.
    public static func enableTextTrack(trackID: Int) -> CastWire.Media.EditTracksInfoRequest {
        CastWire.Media.EditTracksInfoRequest(activeTrackIds: [trackID])
    }

    /// Builds an `EDIT_TRACKS_INFO` request to disable active text tracks.
    public static func disableTextTracks() -> CastWire.Media.EditTracksInfoRequest {
        CastWire.Media.EditTracksInfoRequest(activeTrackIds: [])
    }

    /// Builds an `EDIT_TRACKS_INFO` request to update text track style.
    public static func textTrackStyle(_ style: CastTextTrackStyle) -> CastWire.Media.EditTracksInfoRequest {
        CastWire.Media.EditTracksInfoRequest(textTrackStyle: wireTextTrackStyle(from: style))
    }

    private static func mediaInformation(from item: CastMediaItem) -> CastWire.Media.Information {
        CastWire.Media.Information(
            contentId: item.contentURL.absoluteString,
            contentType: item.contentType,
            streamType: item.streamType,
            metadata: wireMetadata(from: item.metadata),
            tracks: item.textTracks.isEmpty ? nil : item.textTracks.map(wireTrack(from:)),
            textTrackStyle: item.textTrackStyle.map(wireTextTrackStyle(from:)),
            customData: item.customData
        )
    }

    private static func wireMetadata(from metadata: CastMediaMetadata) -> CastWire.Media.Metadata {
        switch metadata {
        case let .generic(value):
            return CastWire.Media.Metadata(
                metadataType: 0,
                title: value.title,
                subtitle: value.subtitle,
                images: wireImages(value.images)
            )
        case let .movie(value):
            return CastWire.Media.Metadata(
                metadataType: 1,
                title: value.title,
                subtitle: value.subtitle,
                studio: value.studio,
                releaseDate: value.releaseDate.map(iso8601String(from:)),
                images: wireImages(value.images)
            )
        case let .tvShow(value):
            return CastWire.Media.Metadata(
                metadataType: 2,
                title: value.title,
                seriesTitle: value.seriesTitle,
                season: value.season,
                episode: value.episode,
                images: wireImages(value.images)
            )
        case let .musicTrack(value):
            return CastWire.Media.Metadata(
                metadataType: 3,
                title: value.title,
                artist: value.artist,
                albumName: value.albumName,
                albumArtist: value.albumArtist,
                track: value.trackNumber,
                images: wireImages(value.images)
            )
        case let .photo(value):
            return CastWire.Media.Metadata(
                metadataType: 4,
                title: value.title,
                location: value.location,
                images: wireImages(value.images)
            )
        }
    }

    private static func wireImages(_ images: [CastImage]) -> [CastWire.Media.Image]? {
        guard !images.isEmpty else {
            return nil
        }
        return images.map { image in
            CastWire.Media.Image(
                url: image.url.absoluteString,
                width: image.width,
                height: image.height
            )
        }
    }

    private static func wireTrack(from track: CastTextTrack) -> CastWire.Media.Track {
        CastWire.Media.Track(
            trackId: track.id,
            type: track.kind,
            name: track.name,
            language: track.languageCode,
            trackContentId: track.contentURL.absoluteString,
            trackContentType: track.contentType,
            subtype: track.subtype
        )
    }

    private static func wireTextTrackStyle(from style: CastTextTrackStyle) -> CastWire.Media.TextTrackStyle {
        CastWire.Media.TextTrackStyle(
            backgroundColor: style.backgroundColorRGBAHex,
            foregroundColor: style.foregroundColorRGBAHex,
            edgeType: style.edgeType,
            edgeColor: style.edgeColorRGBAHex,
            fontScale: style.fontScale,
            fontStyle: style.fontStyle,
            fontFamily: style.fontFamily,
            fontGenericFamily: style.fontGenericFamily,
            windowColor: style.windowColorRGBAHex,
            windowRoundedCornerRadius: style.windowRoundedCornerRadius,
            windowType: style.windowType
        )
    }
}

private func iso8601String(from date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    return formatter.string(from: date)
}
