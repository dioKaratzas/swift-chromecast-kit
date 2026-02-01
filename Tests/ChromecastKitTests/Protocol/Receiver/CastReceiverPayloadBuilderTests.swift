//
//  ChromecastKit
//  Swift package for Google Cast (Chromecast).
//

import Testing
import Foundation
@testable import ChromecastKit

@Suite("Cast Receiver Payload Builder")
struct CastReceiverPayloadBuilderTests {
    @Test("get status payload encodes receiver get status")
    func getStatusPayload() throws {
        let payload = CastReceiverPayloadBuilder.getStatus()
        let json = try encodedJSONObject(payload)

        #expect(payload.type == .getStatus)
        #expect(json["type"] == .string("GET_STATUS"))
    }

    @Test("set volume level payload encodes nested volume object")
    func setVolumePayload() throws {
        let payload = CastReceiverPayloadBuilder.setVolume(level: 0.25)
        let json = try encodedJSONObject(payload)

        #expect(payload.type == .setVolume)
        #expect(payload.volume.level == 0.25)
        #expect(payload.volume.muted == nil)
        guard case let .object(volume)? = json["volume"] else {
            Issue.record("Missing volume object")
            return
        }
        #expect(volume["level"] == .number(0.25))
        #expect(volume["muted"] == nil)
    }

    @Test("set muted payload encodes nested mute field only")
    func setMutedPayload() throws {
        let payload = CastReceiverPayloadBuilder.setMuted(true)
        let json = try encodedJSONObject(payload)

        #expect(payload.volume.level == nil)
        #expect(payload.volume.muted == true)
        guard case let .object(volume)? = json["volume"] else {
            Issue.record("Missing volume object")
            return
        }
        #expect(volume["muted"] == .bool(true))
        #expect(volume["level"] == nil)
    }

    @Test("launch and stop payloads encode app and session ids")
    func launchAndStopPayloads() throws {
        let launch = CastReceiverPayloadBuilder.launch(appID: "CC1AD845")
        let stop = CastReceiverPayloadBuilder.stop(sessionID: "SESSION-1")

        let launchJSON = try encodedJSONObject(launch)
        let stopJSON = try encodedJSONObject(stop)

        #expect(launch.type == .launch)
        #expect(launch.appId == "CC1AD845")
        #expect(launchJSON["type"] == .string("LAUNCH"))
        #expect(launchJSON["appId"] == .string("CC1AD845"))

        #expect(stop.type == .stop)
        #expect(stop.sessionId == "SESSION-1")
        #expect(stopJSON["type"] == .string("STOP"))
        #expect(stopJSON["sessionId"] == .string("SESSION-1"))
    }

    @Test("app availability payload encodes array of app ids")
    func appAvailabilityPayload() throws {
        let payload = CastReceiverPayloadBuilder.getAppAvailability(appIDs: ["CC1AD845", "233637DE"])
        let json = try encodedJSONObject(payload)

        #expect(payload.type == .getAppAvailability)
        #expect(payload.appId == ["CC1AD845", "233637DE"])
        #expect(json["type"] == .string("GET_APP_AVAILABILITY"))
        #expect(json["appId"] == .array([.string("CC1AD845"), .string("233637DE")]))
    }

    private func encodedJSONObject<T: Encodable & Sendable>(_ value: T) throws -> [String: JSONValue] {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode([String: JSONValue].self, from: data)
    }
}
