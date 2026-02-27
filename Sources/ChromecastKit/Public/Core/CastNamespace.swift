//
//  ChromecastKit
//  SPDX-License-Identifier: Apache-2.0
//  Copyright 2026 Dionysis Karatzas
//

import Foundation

/// Cast protocol namespace identifier.
///
/// Use the built-in constants for platform/media channels, or construct custom namespaces
/// such as `CastNamespace("urn:x-cast:com.example.myapp")` for advanced integrations.
public struct CastNamespace: RawRepresentable, ExpressibleByStringLiteral, Sendable, Hashable, Codable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.rawValue = value
    }

    /// Cast transport connection namespace (`tp.connection`).
    public static let connection = Self("urn:x-cast:com.google.cast.tp.connection")
    /// Cast heartbeat namespace (`tp.heartbeat`).
    public static let heartbeat = Self("urn:x-cast:com.google.cast.tp.heartbeat")
    /// Cast platform receiver namespace.
    public static let receiver = Self("urn:x-cast:com.google.cast.receiver")
    /// Default Media Receiver namespace.
    public static let media = Self("urn:x-cast:com.google.cast.media")
    /// Cast multizone namespace used by speaker groups.
    public static let multizone = Self("urn:x-cast:com.google.cast.multizone")
    /// YouTube MDX namespace (app-specific).
    public static let youtubeMDX = Self("urn:x-cast:com.google.youtube.mdx")
}

extension CastNamespace {
    var isCoreChromecastNamespace: Bool {
        switch self {
        case .connection, .heartbeat, .receiver, .media, .multizone:
            true
        default:
            false
        }
    }
}
