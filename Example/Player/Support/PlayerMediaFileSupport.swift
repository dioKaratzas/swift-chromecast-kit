//
//  ChromecastKit
//  SPDX-License-Identifier: Apache-2.0
//  Copyright 2026 Dionysis Karatzas
//

import Foundation

enum PlayerMediaFileSupport {
    static func inferredContentType(for mediaURL: URL) -> String {
        switch mediaURL.pathExtension.lowercased() {
        case "mp4", "m4v":
            return "video/mp4"
        case "mov":
            return "video/quicktime"
        case "webm":
            return "video/webm"
        case "mp3":
            return "audio/mpeg"
        case "m4a":
            return "audio/mp4"
        case "aac":
            return "audio/aac"
        case "wav":
            return "audio/wav"
        default:
            return "application/octet-stream"
        }
    }

    static func isPlayableMediaFile(_ url: URL) -> Bool {
        switch url.pathExtension.lowercased() {
        case "mp4", "m4v", "mov", "webm", "mp3", "m4a", "aac", "wav":
            return true
        default:
            return false
        }
    }

    static func detectLocalIPv4Address() -> String? {
        var ifaddrPointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPointer) == 0, let first = ifaddrPointer else {
            return nil
        }
        defer { freeifaddrs(ifaddrPointer) }

        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let current = pointer {
            let interface = current.pointee
            pointer = interface.ifa_next

            let flags = Int32(interface.ifa_flags)
            let isUp = (flags & IFF_UP) != 0
            let isLoopback = (flags & IFF_LOOPBACK) != 0
            guard isUp, isLoopback == false else {
                continue
            }

            guard let address = interface.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_INET) else {
                continue
            }

            var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                address,
                socklen_t(address.pointee.sa_len),
                &hostBuffer,
                socklen_t(hostBuffer.count),
                nil,
                0,
                NI_NUMERICHOST
            )

            if result == 0 {
                let candidate = String(cString: hostBuffer)
                if candidate.hasPrefix("169.254.") == false {
                    return candidate
                }
            }
        }

        return nil
    }
}
