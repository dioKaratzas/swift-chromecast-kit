//
//  ChromecastKit
//  Swift package for Google Cast (Chromecast).
//

import Testing
import Foundation
@testable import ChromecastKit

@Suite("Cast Message JSON Codec")
struct CastMessageJSONCodecTests {
    @Test("encodes typed wire load request to payload utf8")
    func encodeTypedPayload() throws {
        let route = CastMessageRoute.platform(namespace: .media)
        let payload = CastWire.Media.LoadRequest(
            media: .init(
                contentId: "https://example.com/video.mp4",
                contentType: "video/mp4",
                streamType: .buffered,
                metadata: .init(metadataType: 0, title: "Demo")
            ),
            autoplay: true,
            currentTime: 8,
            activeTrackIds: [1]
        )
        let message = CastOutboundMessage(route: route, payload: payload)

        let payloadUTF8 = try CastMessageJSONCodec.encodePayload(message)
        let json = try JSONDecoder().decode([String: JSONValue].self, from: Data(payloadUTF8.utf8))

        #expect(json["type"] == .string("LOAD"))
        #expect(json["autoplay"] == .bool(true))
        #expect(json["currentTime"] == .number(8))
        #expect(json["activeTrackIds"] == .array([.number(1)]))
    }

    @Test("decodes inbound payload to typed wire request")
    func decodeTypedPayload() throws {
        let route = CastMessageRoute(
            sourceID: "receiver-0",
            destinationID: "sender-0",
            namespace: .media
        )
        let inbound = CastInboundMessage(
            route: route,
            payloadUTF8: #"{"type":"EDIT_TRACKS_INFO","activeTrackIds":[2]}"#
        )

        let decoded = try CastMessageJSONCodec.decodePayload(CastWire.Media.EditTracksInfoRequest.self, from: inbound)

        #expect(decoded.type == .editTracksInfo)
        #expect(decoded.activeTrackIds == [2])
    }

    @Test("platform route helper uses receiver-0 destination")
    func platformRouteHelper() {
        let route = CastMessageRoute.platform(sourceID: "sender-123", namespace: .heartbeat)

        #expect(route.sourceID == "sender-123")
        #expect(route.destinationID == "receiver-0")
        #expect(route.namespace == .heartbeat)
    }

    @Test("decode invalid json throws")
    func decodeInvalidJSON() {
        #expect(throws: (any Error).self) {
            _ = try CastMessageJSONCodec.decodePayload(
                CastWire.Media.EditTracksInfoRequest.self,
                from: #"{"type":"EDIT_TRACKS_INFO","activeTrackIds":"nope"}"#
            )
        }
    }
}
