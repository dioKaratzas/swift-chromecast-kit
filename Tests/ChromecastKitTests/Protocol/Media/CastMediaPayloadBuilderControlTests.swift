//
//  ChromecastKit
//  SPDX-License-Identifier: Apache-2.0
//  Copyright 2026 Dionysis Karatzas
//

import Testing
import Foundation
@testable import ChromecastKit

@Suite("Cast Media Payload Builder Controls")
struct CastMediaPayloadBuilderControlTests {
    @Test("control payloads encode media session id and types")
    func sessionBoundControlPayloads() throws {
        let play = CastMediaPayloadBuilder.play(mediaSessionID: 99)
        let pause = CastMediaPayloadBuilder.pause(mediaSessionID: 99)
        let stop = CastMediaPayloadBuilder.stop(mediaSessionID: 99)
        let rate = CastMediaPayloadBuilder.setPlaybackRate(1.25, mediaSessionID: 99)

        let playJSON = try encode(play)
        let pauseJSON = try encode(pause)
        let stopJSON = try encode(stop)
        let rateJSON = try encode(rate)

        #expect(playJSON["type"] == .string("PLAY"))
        #expect(pauseJSON["type"] == .string("PAUSE"))
        #expect(stopJSON["type"] == .string("STOP"))
        #expect(rateJSON["type"] == .string("SET_PLAYBACK_RATE"))
        #expect(rateJSON["playbackRate"] == .number(1.25))

        #expect(playJSON["mediaSessionId"] == .number(99))
        #expect(pauseJSON["mediaSessionId"] == .number(99))
        #expect(stopJSON["mediaSessionId"] == .number(99))
        #expect(rateJSON["mediaSessionId"] == .number(99))
    }

    @Test("seek payload supports resume state mapping")
    func seekPayloadResumeState() throws {
        let seekPlay = CastMediaPayloadBuilder.seek(to: 42, mediaSessionID: 7, resume: true)
        let seekPause = CastMediaPayloadBuilder.seek(to: 42, mediaSessionID: 7, resume: false)
        let seekNoResume = CastMediaPayloadBuilder.seek(to: 42, mediaSessionID: 7, resume: nil)

        let seekPlayJSON = try encode(seekPlay)
        let seekPauseJSON = try encode(seekPause)
        let seekNoResumeJSON = try encode(seekNoResume)

        #expect(seekPlayJSON["type"] == .string("SEEK"))
        #expect(seekPlayJSON["currentTime"] == .number(42))
        #expect(seekPlayJSON["resumeState"] == .string("PLAYBACK_START"))

        #expect(seekPauseJSON["resumeState"] == .string("PLAYBACK_PAUSE"))
        #expect(seekNoResumeJSON["resumeState"] == nil)
    }

    @Test("edit tracks info overloads can include media session id")
    func editTracksWithMediaSession() throws {
        let enable = CastMediaPayloadBuilder.enableTextTrack(trackID: 3, mediaSessionID: 77)
        let disable = CastMediaPayloadBuilder.disableTextTracks(mediaSessionID: 77)

        let enableJSON = try encode(enable)
        let disableJSON = try encode(disable)

        #expect(enableJSON["mediaSessionId"] == .number(77))
        #expect(enableJSON["activeTrackIds"] == .array([.number(3)]))
        #expect(disableJSON["mediaSessionId"] == .number(77))
        #expect(disableJSON["activeTrackIds"] == .array([]))
    }

    private func encode<T: Encodable & Sendable>(_ value: T) throws -> [String: JSONValue] {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode([String: JSONValue].self, from: data)
    }
}
