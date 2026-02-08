//
//  ChromecastKit
//  Swift package for Google Cast (Chromecast).
//

import Testing
import Foundation
@testable import ChromecastKit

@Suite("Cast V2 Transport Codec")
struct CastV2TransportCodecTests {
    @Test("channel message codec round-trips UTF8 payload and route")
    func channelMessageRoundTrip() throws {
        let route = CastMessageRoute(
            sourceID: "sender-0",
            destinationID: "receiver-0",
            namespace: .receiver
        )
        let payload = #"{"type":"GET_STATUS","requestId":1}"#

        let encoded = try CastV2ChannelMessageCodec.encode(route: route, payloadUTF8: payload)
        let decoded = try CastV2ChannelMessageCodec.decode(encoded)

        #expect(decoded.route == route)
        #expect(decoded.payloadUTF8 == payload)
    }

    @Test("frame codec round-trips framed cast message")
    func frameRoundTrip() throws {
        let route = CastMessageRoute(
            sourceID: "sender-0",
            destinationID: "web-42",
            namespace: .media
        )
        let payload = #"{"type":"PLAY","mediaSessionId":55}"#

        let frame = try CastV2FrameCodec.encodeFrame(route: route, payloadUTF8: payload)
        let decoded = try CastV2FrameCodec.decodeFrame(frame)

        #expect(decoded.route == route)
        #expect(decoded.payloadUTF8 == payload)
    }

    @Test("incremental deframer emits multiple bodies across partial chunks")
    func deframerPartialChunks() throws {
        let routeA = CastMessageRoute(sourceID: "sender-0", destinationID: "receiver-0", namespace: .receiver)
        let routeB = CastMessageRoute(sourceID: "receiver-0", destinationID: "sender-0", namespace: .receiver)
        let frameA = try CastV2FrameCodec.encodeFrame(
            route: routeA,
            payloadUTF8: #"{"type":"GET_STATUS","requestId":1}"#
        )
        let frameB = try CastV2FrameCodec.encodeFrame(
            route: routeB,
            payloadUTF8: #"{"type":"RECEIVER_STATUS","requestId":1}"#
        )
        var combined = Data()
        combined.append(frameA)
        combined.append(frameB)

        var deframer = CastV2FrameDeframer()
        let splitIndex = 7
        guard combined.count > splitIndex else {
            Issue.record("Expected combined frames to exceed split index")
            return
        }
        let firstChunk = Data(combined.prefix(splitIndex))
        let secondChunk = Data(combined.dropFirst(splitIndex))

        let noneYet = try deframer.append(firstChunk)
        #expect(noneYet.isEmpty)

        let bodies = try deframer.append(secondChunk)
        #expect(bodies.count == 2)
        guard bodies.count == 2 else {
            Issue.record("Expected two deframed Cast message bodies, got \(bodies.count)")
            return
        }

        let decodedA = try CastV2ChannelMessageCodec.decode(bodies[0])
        let decodedB = try CastV2ChannelMessageCodec.decode(bodies[1])
        #expect(decodedA.route == routeA)
        #expect(decodedB.route == routeB)
    }

    @Test("transport codec decodes binary payload envelopes")
    func decodesBinaryPayloadsForTransportLayer() throws {
        let body = makeBinaryPayloadCastMessageBody(binaryPayload: Data([0x01, 0x02, 0x03]))
        let message = try CastV2ChannelMessageCodec.decodeTransportMessage(body)

        #expect(message.route.namespace == .receiver)
        guard case let .binary(payload) = message.payload else {
            Issue.record("Expected binary payload")
            return
        }
        #expect(payload == Data([0x01, 0x02, 0x03]))
    }

    @Test("json convenience decode still rejects binary payload envelopes")
    func convenienceDecodeRejectsBinaryPayloads() throws {
        let body = makeBinaryPayloadCastMessageBody(binaryPayload: Data())

        #expect(throws: CastError.self) {
            _ = try CastV2ChannelMessageCodec.decode(body)
        }
    }

    private func makeBinaryPayloadCastMessageBody(binaryPayload: Data) -> Data {
        var writer = TestProtoWriter()
        writer.writeVarint(fieldNumber: 1, value: 0)
        writer.writeString(fieldNumber: 2, value: "receiver-0")
        writer.writeString(fieldNumber: 3, value: "sender-0")
        writer.writeString(fieldNumber: 4, value: CastNamespace.receiver.rawValue)
        writer.writeVarint(fieldNumber: 5, value: 1)
        writer.writeBytes(fieldNumber: 7, value: binaryPayload)
        return writer.data
    }
}

private struct TestProtoWriter {
    private(set) var data = Data()

    mutating func writeVarint(fieldNumber: Int, value: UInt64) {
        writeVarintValue(UInt64(fieldNumber) << 3)
        writeVarintValue(value)
    }

    mutating func writeString(fieldNumber: Int, value: String) {
        writeBytes(fieldNumber: fieldNumber, value: Data(value.utf8))
    }

    mutating func writeBytes(fieldNumber: Int, value: Data) {
        writeVarintValue((UInt64(fieldNumber) << 3) | 0b010)
        writeVarintValue(UInt64(value.count))
        data.append(value)
    }

    private mutating func writeVarintValue(_ value: UInt64) {
        var value = value
        while value >= 0x80 {
            data.append(UInt8((value & 0x7F) | 0x80))
            value >>= 7
        }
        data.append(UInt8(value))
    }
}
