//
//  ChromecastKit
//  Swift package for Google Cast (Chromecast).
//

import Testing
import Foundation
@testable import ChromecastKit

@Suite("Cast Protocol Primitives")
struct CastProtocolPrimitivesTests {
    @Test("request id generator increments monotonically")
    func requestIDGenerator() {
        var generator = CastRequestIDGenerator()

        #expect(generator.current == 0)
        #expect(generator.next() == 1)
        #expect(generator.next() == 2)
        #expect(generator.current == 2)
    }

    @Test("message target codable round-trip preserves transport id")
    func messageTargetCodable() throws {
        let target = CastMessageTarget.transport(id: "web-9")
        let data = try JSONEncoder().encode(target)
        let decoded = try JSONDecoder().decode(CastMessageTarget.self, from: data)

        #expect(decoded == target)
    }

    @Test("custom namespaces are supported and codable")
    func customNamespaceSupport() throws {
        let namespace = CastNamespace("urn:x-cast:com.example.custom")
        let data = try JSONEncoder().encode(namespace)
        let decoded = try JSONDecoder().decode(CastNamespace.self, from: data)

        #expect(decoded == namespace)
        #expect(CastNamespace.media.rawValue == "urn:x-cast:com.google.cast.media")
    }

    @Test("load payload builder returns typed request model")
    func loadPayloadBuilder() throws {
        let mediaURL = try #require(URL(string: "https://example.com/movie.mp4"))
        let imageURL = try #require(URL(string: "https://example.com/poster.jpg"))
        let subtitlesURL = try #require(URL(string: "https://example.com/en.vtt"))

        let item = CastMediaItem(
            contentURL: mediaURL,
            contentType: "video/mp4",
            streamType: .buffered,
            metadata: .generic(title: "Movie", subtitle: "Demo", images: [.init(url: imageURL)]),
            textTracks: [.subtitleVTT(id: 1, name: "English", languageCode: "en-US", url: subtitlesURL)],
            textTrackStyle: .init(
                foregroundColorRGBAHex: "#FFFFFFFF",
                edgeType: .outline,
                edgeColorRGBAHex: "#000000FF",
                fontScale: 1.1
            )
        )

        let payload = CastMediaPayloadBuilder.load(
            item: item,
            options: .init(autoplay: true, startTime: 12, activeTextTrackIDs: [1])
        )

        #expect(payload.type == .load)
        #expect(payload.autoplay)
        #expect(payload.currentTime == 12)
        #expect(payload.activeTrackIds == [1])
        #expect(payload.media.contentId == mediaURL.absoluteString)
        #expect(payload.media.contentType == "video/mp4")
        #expect(payload.media.metadata.metadataType == 0)
        #expect(payload.media.metadata.title == "Movie")
        #expect(payload.media.tracks?.count == 1)
        #expect(payload.media.tracks?.first?.trackContentId == subtitlesURL.absoluteString)
        #expect(payload.media.textTrackStyle?.edgeType == .outline)

        let encoded = try encodedJSONObject(payload)
        #expect(encoded["type"] == .string("LOAD"))
        #expect(encoded["currentTime"] == .number(12))
        #expect(encoded["activeTrackIds"] == .array([.number(1)]))
    }

    @Test("subtitle edit payloads match cast message shape")
    func subtitleEditPayloads() throws {
        let enable = CastMediaPayloadBuilder.enableTextTrack(trackID: 7)
        let disable = CastMediaPayloadBuilder.disableTextTracks()

        #expect(enable.type == .editTracksInfo)
        #expect(enable.activeTrackIds == [7])
        #expect(disable.type == .editTracksInfo)
        #expect(disable.activeTrackIds == [])

        let enableJSON = try encodedJSONObject(enable)
        let disableJSON = try encodedJSONObject(disable)
        #expect(enableJSON["type"] == .string("EDIT_TRACKS_INFO"))
        #expect(enableJSON["activeTrackIds"] == .array([.number(7)]))
        #expect(disableJSON["type"] == .string("EDIT_TRACKS_INFO"))
        #expect(disableJSON["activeTrackIds"] == .array([]))
    }

    @Test("text track style edit payload serializes known fields")
    func textTrackStylePayload() throws {
        let style = CastTextTrackStyle(
            backgroundColorRGBAHex: "#00000000",
            foregroundColorRGBAHex: "#FFFFFFFF",
            edgeType: .outline,
            edgeColorRGBAHex: "#000000FF",
            fontScale: 1.25,
            fontStyle: .bold,
            fontFamily: "Droid Sans",
            fontGenericFamily: .sansSerif,
            windowType: .roundedCorners
        )

        let payload = CastMediaPayloadBuilder.textTrackStyle(style)

        #expect(payload.type == .editTracksInfo)
        #expect(payload.textTrackStyle?.edgeType == .outline)
        #expect(payload.textTrackStyle?.fontStyle == .bold)

        let encoded = try encodedJSONObject(payload)
        #expect(encoded["type"] == .string("EDIT_TRACKS_INFO"))
        guard case let .object(styleObject)? = encoded["textTrackStyle"] else {
            Issue.record("Missing textTrackStyle")
            return
        }

        #expect(styleObject["foregroundColor"] == .string("#FFFFFFFF"))
        #expect(styleObject["edgeType"] == .string("OUTLINE"))
        #expect(styleObject["fontScale"] == .number(1.25))
        #expect(styleObject["fontStyle"] == .string("BOLD"))
        #expect(styleObject["fontGenericFamily"] == .string("SANS_SERIF"))
        #expect(styleObject["windowType"] == .string("ROUNDED_CORNERS"))
    }

    private func encodedJSONObject<T: Encodable & Sendable>(_ value: T) throws -> [String: JSONValue] {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode([String: JSONValue].self, from: data)
    }
}
