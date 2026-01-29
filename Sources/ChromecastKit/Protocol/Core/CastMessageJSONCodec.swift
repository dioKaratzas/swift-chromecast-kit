//
//  ChromecastKit
//  Swift package for Google Cast (Chromecast).
//

import Foundation

/// Encodes and decodes Cast namespace JSON payloads for typed messages.
///
/// This codec intentionally operates only on the payload JSON string (`payload_utf8`)
/// portion of Cast v2 messages. Protobuf framing belongs to the transport layer.
public enum CastMessageJSONCodec {
    /// Encodes an outbound message payload into a UTF-8 JSON string.
    public static func encodePayload<Payload: Encodable & Sendable>(
        _ message: CastOutboundMessage<Payload>
    ) throws -> String {
        let encoder = JSONEncoder()
        let data = try encoder.encode(message.payload)
        guard let string = String(data: data, encoding: .utf8) else {
            throw CastError.invalidResponse("Failed to encode UTF-8 payload string")
        }
        return string
    }

    /// Decodes a UTF-8 JSON payload from an inbound Cast message.
    public static func decodePayload<Payload: Decodable & Sendable>(
        _ type: Payload.Type,
        from message: CastInboundMessage
    ) throws -> Payload {
        let data = Data(message.payloadUTF8.utf8)
        let decoder = JSONDecoder()
        return try decoder.decode(type, from: data)
    }

    /// Convenience for decoding a payload directly from a UTF-8 JSON string.
    public static func decodePayload<Payload: Decodable & Sendable>(
        _ type: Payload.Type,
        from payloadUTF8: String
    ) throws -> Payload {
        let data = Data(payloadUTF8.utf8)
        let decoder = JSONDecoder()
        return try decoder.decode(type, from: data)
    }
}
