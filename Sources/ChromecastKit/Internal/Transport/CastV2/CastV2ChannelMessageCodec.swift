//
//  ChromecastKit
//  Swift package for Google Cast (Chromecast).
//

import Foundation

private enum CastV2ProtoWireType: UInt64 {
    case varint = 0
    case fixed64 = 1
    case lengthDelimited = 2
    case fixed32 = 5
}

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

/// Minimal protobuf encoder/decoder for the Cast v2 `CastMessage` envelope.
///
/// It supports both payload kinds at the transport layer. Higher layers can choose
/// to reject binary payloads until they add namespace-specific handling.
enum CastV2ChannelMessageCodec {
    private enum Field {
        static let protocolVersion = 1
        static let sourceID = 2
        static let destinationID = 3
        static let namespace = 4
        static let payloadType = 5
        static let payloadUTF8 = 6
        static let payloadBinary = 7
    }

    private enum CastProtocolVersion: UInt64 {
        case castV2_1_0 = 0
    }

    private enum CastPayloadType: UInt64 {
        case string = 0
        case binary = 1
    }

    static func encode(command: CastEncodedCommand) throws -> Data {
        try encode(route: command.route, payloadUTF8: command.payloadUTF8)
    }

    static func encode(route: CastMessageRoute, payloadUTF8: String) throws -> Data {
        var writer = ProtobufWriter()
        writer.writeVarintField(Field.protocolVersion, value: CastProtocolVersion.castV2_1_0.rawValue)
        writer.writeStringField(Field.sourceID, value: route.sourceID.rawValue)
        writer.writeStringField(Field.destinationID, value: route.destinationID.rawValue)
        writer.writeStringField(Field.namespace, value: route.namespace.rawValue)
        writer.writeVarintField(Field.payloadType, value: CastPayloadType.string.rawValue)
        writer.writeStringField(Field.payloadUTF8, value: payloadUTF8)
        return writer.data
    }

    static func decodeTransportMessage(_ data: Data) throws -> CastV2ChannelMessage {
        var reader = ProtobufReader(data: data)

        var sourceID: String?
        var destinationID: String?
        var namespace: String?
        var payloadType = CastPayloadType.string
        var payloadUTF8: String?
        var payloadBinary: Data?

        while reader.isAtEnd == false {
            let key = try reader.readVarint()
            let fieldNumber = Int(key >> 3)
            guard let wireType = CastV2ProtoWireType(rawValue: key & 0b111) else {
                throw CastError.invalidResponse("Unsupported protobuf wire type in CastMessage")
            }

            switch (fieldNumber, wireType) {
            case (Field.protocolVersion, .varint):
                _ = try reader.readVarint()
            case (Field.sourceID, .lengthDelimited):
                sourceID = try reader.readString()
            case (Field.destinationID, .lengthDelimited):
                destinationID = try reader.readString()
            case (Field.namespace, .lengthDelimited):
                namespace = try reader.readString()
            case (Field.payloadType, .varint):
                let raw = try reader.readVarint()
                guard let decoded = CastPayloadType(rawValue: raw) else {
                    throw CastError.invalidResponse("Unsupported Cast payload type: \(raw)")
                }
                payloadType = decoded
            case (Field.payloadUTF8, .lengthDelimited):
                payloadUTF8 = try reader.readString()
            case (Field.payloadBinary, .lengthDelimited):
                payloadBinary = try reader.readLengthDelimitedData()
            default:
                try reader.skipField(wireType: wireType)
            }
        }

        guard let sourceID,
              let destinationID,
              let namespace else {
            throw CastError.invalidResponse("Missing required CastMessage fields")
        }

        let payload: CastV2ChannelPayload
        switch payloadType {
        case .string:
            guard let payloadUTF8 else {
                throw CastError.invalidResponse("Missing payload_utf8 for STRING CastMessage")
            }
            payload = .utf8(payloadUTF8)
        case .binary:
            guard let payloadBinary else {
                throw CastError.invalidResponse("Missing payload_binary for BINARY CastMessage")
            }
            payload = .binary(payloadBinary)
        }

        return .init(
            route: .init(
                sourceID: CastEndpointID(sourceID),
                destinationID: CastEndpointID(destinationID),
                namespace: CastNamespace(namespace)
            ),
            payload: payload
        )
    }

    /// Convenience bridge used by the current JSON-based higher layers.
    static func decode(_ data: Data) throws -> CastInboundMessage {
        let message = try decodeTransportMessage(data)
        guard case let .utf8(payloadUTF8) = message.payload else {
            throw CastError.unsupportedFeature("Binary CastMessage payloads are not supported by JSON controllers yet")
        }
        return .init(route: message.route, payloadUTF8: payloadUTF8)
    }
}

private struct ProtobufWriter {
    private(set) var data = Data()

    mutating func writeVarintField(_ fieldNumber: Int, value: UInt64) {
        writeVarint(fieldKey(fieldNumber, wireType: .varint))
        writeVarint(value)
    }

    mutating func writeStringField(_ fieldNumber: Int, value: String) {
        let bytes = Data(value.utf8)
        writeVarint(fieldKey(fieldNumber, wireType: .lengthDelimited))
        writeVarint(UInt64(bytes.count))
        data.append(bytes)
    }

    private func fieldKey(_ fieldNumber: Int, wireType: CastV2ProtoWireType) -> UInt64 {
        (UInt64(fieldNumber) << 3) | wireType.rawValue
    }

    private mutating func writeVarint(_ value: UInt64) {
        var value = value
        while value >= 0x80 {
            data.append(UInt8((value & 0x7F) | 0x80))
            value >>= 7
        }
        data.append(UInt8(value))
    }
}

private struct ProtobufReader {
    private let data: Data
    private var offset = 0

    init(data: Data) {
        self.data = data
    }

    var isAtEnd: Bool {
        offset >= data.count
    }

    mutating func readVarint() throws -> UInt64 {
        var result: UInt64 = 0
        var shift: UInt64 = 0

        while true {
            guard offset < data.count else {
                throw CastError.invalidResponse("Unexpected EOF while decoding protobuf varint")
            }
            let byte = data[offset]
            offset += 1

            result |= UInt64(byte & 0x7F) << shift

            if (byte & 0x80) == 0 {
                return result
            }

            shift += 7
            if shift >= 64 {
                throw CastError.invalidResponse("Protobuf varint overflow in CastMessage")
            }
        }
    }

    mutating func readString() throws -> String {
        let bytes = try readLengthDelimitedData()
        guard let string = String(data: bytes, encoding: .utf8) else {
            throw CastError.invalidResponse("Invalid UTF-8 CastMessage string field")
        }
        return string
    }

    mutating func readLengthDelimitedData() throws -> Data {
        let length = try Int(readVarint())
        guard length >= 0, offset + length <= data.count else {
            throw CastError.invalidResponse("Invalid protobuf length-delimited field length")
        }
        let end = offset + length
        let slice = data[offset ..< end]
        offset = end
        return Data(slice)
    }

    mutating func skipField(wireType: CastV2ProtoWireType) throws {
        switch wireType {
        case .varint:
            _ = try readVarint()
        case .lengthDelimited:
            _ = try readLengthDelimitedData()
        case .fixed64:
            try skip(byteCount: 8)
        case .fixed32:
            try skip(byteCount: 4)
        }
    }

    private mutating func skip(byteCount: Int) throws {
        guard offset + byteCount <= data.count else {
            throw CastError.invalidResponse("Unexpected EOF while skipping protobuf field")
        }
        offset += byteCount
    }
}
