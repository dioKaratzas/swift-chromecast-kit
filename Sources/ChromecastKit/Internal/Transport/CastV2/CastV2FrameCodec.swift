//
//  ChromecastKit
//  Swift package for Google Cast (Chromecast).
//

import Foundation

/// Length-prefixed frame codec used by Cast v2 sockets.
///
/// Each protobuf `CastMessage` frame is prefixed by a 4-byte big-endian payload length.
enum CastV2FrameCodec {
    static let defaultMaxFrameSize = 1024 * 1024

    static func encodeFrame(command: CastEncodedCommand) throws -> Data {
        let message = try CastV2ChannelMessageCodec.encode(command: command)
        return try encodeFrameBody(message)
    }

    static func encodeFrame(route: CastMessageRoute, payloadUTF8: String) throws -> Data {
        let message = try CastV2ChannelMessageCodec.encode(route: route, payloadUTF8: payloadUTF8)
        return try encodeFrameBody(message)
    }

    static func encodeFrameBody(_ body: Data) throws -> Data {
        guard body.count <= Int(UInt32.max) else {
            throw CastError.invalidArgument("Cast frame too large to encode")
        }

        var framed = Data(capacity: 4 + body.count)
        var length = UInt32(body.count).bigEndian
        withUnsafeBytes(of: &length) { framed.append(contentsOf: $0) }
        framed.append(body)
        return framed
    }

    static func decodeFrame(_ frame: Data, maxFrameSize: Int = defaultMaxFrameSize) throws -> CastInboundMessage {
        let body = try decodeFrameBody(frame, maxFrameSize: maxFrameSize)
        return try CastV2ChannelMessageCodec.decode(body)
    }

    static func decodeFrameBody(_ frame: Data, maxFrameSize: Int = defaultMaxFrameSize) throws -> Data {
        guard frame.count >= 4 else {
            throw CastError.invalidResponse("Cast frame shorter than 4-byte length prefix")
        }

        let declaredLength = Int(
            readBigEndianUInt32(frame[frame.startIndex ..< frame.index(frame.startIndex, offsetBy: 4)])
        )

        guard declaredLength >= 0 else {
            throw CastError.invalidResponse("Negative Cast frame length")
        }
        guard declaredLength <= maxFrameSize else {
            throw CastError.invalidResponse("Cast frame exceeds max supported size")
        }
        guard frame.count == 4 + declaredLength else {
            throw CastError.invalidResponse("Cast frame length prefix does not match payload size")
        }

        return Data(frame.dropFirst(4))
    }
}

/// Incremental deframer for Cast v2 stream transports.
///
/// Append raw bytes from the socket and pull complete protobuf frame bodies as they arrive.
struct CastV2FrameDeframer: Sendable {
    private let maxFrameSize: Int
    private var buffer = [UInt8]()

    init(maxFrameSize: Int = CastV2FrameCodec.defaultMaxFrameSize) {
        self.maxFrameSize = maxFrameSize
    }

    mutating func append(_ chunk: Data) throws -> [Data] {
        guard chunk.isEmpty == false else {
            return []
        }

        buffer.append(contentsOf: chunk)
        var frames = [Data]()

        while true {
            guard buffer.count >= 4 else {
                break
            }

            let declaredLength = Int(readBigEndianUInt32(buffer[0], buffer[1], buffer[2], buffer[3]))

            guard declaredLength <= maxFrameSize else {
                buffer.removeAll(keepingCapacity: false)
                throw CastError.invalidResponse("Cast frame exceeds max supported size")
            }

            let totalLength = 4 + declaredLength
            guard buffer.count >= totalLength else {
                break
            }

            frames.append(Data(buffer[4 ..< totalLength]))
            buffer.removeFirst(totalLength)
        }

        return frames
    }

    mutating func clear() {
        buffer.removeAll(keepingCapacity: false)
    }
}

private func readBigEndianUInt32(_ bytes: Data.SubSequence) -> UInt32 {
    guard bytes.count == 4 else {
        return 0
    }
    var value: UInt32 = 0
    for byte in bytes {
        value = (value << 8) | UInt32(byte)
    }
    return value
}

private func readBigEndianUInt32(_ b0: UInt8, _ b1: UInt8, _ b2: UInt8, _ b3: UInt8) -> UInt32 {
    (UInt32(b0) << 24) | (UInt32(b1) << 16) | (UInt32(b2) << 8) | UInt32(b3)
}
