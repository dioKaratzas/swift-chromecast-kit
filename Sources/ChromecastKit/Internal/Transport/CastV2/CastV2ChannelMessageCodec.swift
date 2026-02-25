//
//  ChromecastKit
//  Swift package for Google Cast (Chromecast).
//

import Foundation
import SwiftProtobuf

/// Internal transport payload for a Cast v2 `CastMessage`.
enum CastV2ChannelPayload: Sendable, Hashable {
    case utf8(String)
    case binary(Data)
}

/// Internal decoded Cast v2 channel message envelope.
struct CastV2ChannelMessage: Sendable, Hashable {
    let route: CastMessageRoute
    let payload: CastV2ChannelPayload
}

/// Protobuf encoder/decoder for the Cast v2 `CastMessage` envelope.
///
/// This implementation uses SwiftProtobuf-generated models from
/// `/Users/dio/Desktop/Projects/ChromecastKit/Protos/CastV2/cast_channel.proto`.
enum CastV2ChannelMessageCodec {
    private typealias ProtoMessage = Extensions_Api_CastChannel_CastMessage

    static func encode(command: CastEncodedCommand) throws -> Data {
        switch command.payload {
        case let .utf8(payloadUTF8):
            return try encode(route: command.route, payloadUTF8: payloadUTF8)
        case let .binary(payloadBinary):
            return try encode(route: command.route, payloadBinary: payloadBinary)
        }
    }

    static func encode(route: CastMessageRoute, payloadUTF8: String) throws -> Data {
        var message = makeBaseProtoMessage(route: route)
        message.payloadType = .string
        message.payloadUtf8 = payloadUTF8
        do {
            return try message.serializedData()
        } catch {
            throw CastError.invalidResponse("Failed to encode CastMessage protobuf envelope: \(error)")
        }
    }

    static func encode(route: CastMessageRoute, payloadBinary: Data) throws -> Data {
        var message = makeBaseProtoMessage(route: route)
        message.payloadType = .binary
        message.payloadBinary = payloadBinary
        do {
            return try message.serializedData()
        } catch {
            throw CastError.invalidResponse("Failed to encode CastMessage protobuf envelope: \(error)")
        }
    }

    static func decodeTransportMessage(_ data: Data) throws -> CastV2ChannelMessage {
        let message: ProtoMessage
        do {
            message = try ProtoMessage(serializedBytes: data)
        } catch {
            throw CastError.invalidResponse("Failed to decode CastMessage protobuf envelope: \(error)")
        }

        let route = CastMessageRoute(
            sourceID: CastEndpointID(message.sourceID),
            destinationID: CastEndpointID(message.destinationID),
            namespace: CastNamespace(message.namespace)
        )

        let payload: CastV2ChannelPayload
        switch message.payloadType {
        case .string:
            guard message.hasPayloadUtf8 else {
                throw CastError.invalidResponse("Missing payload_utf8 for STRING CastMessage")
            }
            payload = .utf8(message.payloadUtf8)
        case .binary:
            guard message.hasPayloadBinary else {
                throw CastError.invalidResponse("Missing payload_binary for BINARY CastMessage")
            }
            payload = .binary(message.payloadBinary)
        }

        return .init(route: route, payload: payload)
    }

    /// Convenience bridge used by the current JSON-based higher layers.
    static func decode(_ data: Data) throws -> CastInboundMessage {
        let message = try decodeTransportMessage(data)
        guard case let .utf8(payloadUTF8) = message.payload else {
            throw CastError.unsupportedFeature("Binary CastMessage payloads are not supported by JSON controllers yet")
        }
        return .init(route: message.route, payloadUTF8: payloadUTF8)
    }

    private static func makeBaseProtoMessage(route: CastMessageRoute) -> ProtoMessage {
        var message = ProtoMessage()
        message.protocolVersion = .castv210
        message.sourceID = route.sourceID.rawValue
        message.destinationID = route.destinationID.rawValue
        message.namespace = route.namespace.rawValue
        return message
    }
}
