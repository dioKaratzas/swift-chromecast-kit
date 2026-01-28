//
//  ChromecastKit
//  Swift package for Google Cast (Chromecast).
//

import Testing
import Foundation
@testable import ChromecastKit

@Suite("Model Foundations")
struct ModelFoundationTests {
    @Test("subtitleVTT helper fills Cast-friendly defaults")
    func subtitleVTTHelper() throws {
        let url = try #require(URL(string: "https://example.com/en.vtt"))
        let track = CastTextTrack.subtitleVTT(
            id: 7,
            name: "English",
            languageCode: "en-US",
            url: url
        )

        #expect(track.id == 7)
        #expect(track.kind == CastTextTrackKind.text)
        #expect(track.subtype == CastTextTrackSubtype.subtitles)
        #expect(track.name == "English")
        #expect(track.languageCode == "en-US")
        #expect(track.contentURL == url)
        #expect(track.contentType == "text/vtt")
    }

    @Test("generic metadata convenience preserves fields")
    func genericMetadataConvenience() throws {
        let imageURL = try #require(URL(string: "https://example.com/poster.jpg"))
        let metadata = CastMediaMetadata.generic(
            title: "Big Buck Bunny",
            subtitle: "Demo",
            images: [.init(url: imageURL)]
        )

        guard case let .generic(value) = metadata else {
            Issue.record("Expected generic metadata")
            return
        }

        #expect(value.title == "Big Buck Bunny")
        #expect(value.subtitle == "Demo")
        #expect(value.images.count == 1)
        #expect(value.images.first?.url == imageURL)
    }

    @Test("JSONValue round-trips nested objects and arrays")
    func jsonValueRoundTrip() throws {
        let value = JSONValue.object([
            "url": .string("https://example.com/video.mp4"),
            "autoplay": .bool(true),
            "position": .number(12.5),
            "tracks": .array([
                .object(["id": .number(1), "lang": .string("en-US")]),
                .object(["id": .number(2), "lang": .string("es-ES")]),
            ]),
            "custom": .null,
        ])

        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)

        #expect(decoded == value)
    }

    @Test("media command set encodes as bitset raw value")
    func mediaCommandSetCodable() throws {
        let commands: CastMediaCommandSet = [.pause, .seek, .editTracks]

        let data = try JSONEncoder().encode(commands)
        let decoded = try JSONDecoder().decode(CastMediaCommandSet.self, from: data)

        #expect(decoded == commands)
        #expect(decoded.contains(CastMediaCommandSet.pause))
        #expect(decoded.contains(CastMediaCommandSet.seek))
        #expect(decoded.contains(CastMediaCommandSet.editTracks))
        #expect(!decoded.contains(CastMediaCommandSet.queueNext))
    }

    @Test("adjustedCurrentTime advances while playing")
    func adjustedCurrentTimeWhenPlaying() {
        let status = CastMediaStatus(
            currentTime: 10,
            playbackRate: 1,
            playerState: .playing,
            lastUpdated: Date(timeIntervalSinceNow: -2)
        )

        #expect(status.adjustedCurrentTime > 11.5)
    }

    @Test("adjustedCurrentTime stays fixed when paused")
    func adjustedCurrentTimeWhenPaused() {
        let status = CastMediaStatus(
            currentTime: 10,
            playbackRate: 1,
            playerState: .paused,
            lastUpdated: Date(timeIntervalSinceNow: -60)
        )

        #expect(status.adjustedCurrentTime == 10)
    }
}
