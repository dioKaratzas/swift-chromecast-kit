//
//  ChromecastKit
//  SPDX-License-Identifier: Apache-2.0
//  Copyright 2026 Dionysis Karatzas
//

import Foundation
import ChromecastKit

extension ShowcaseAppModel {
    enum DetailTab: String, CaseIterable, Identifiable {
        case overview
        case receiver
        case media
        case localFiles
        case namespace

        var id: Self {
            self
        }

        var title: String {
            switch self {
            case .overview: "Session"
            case .receiver: "Receiver"
            case .media: "Media"
            case .localFiles: "Local Files"
            case .namespace: "Namespaces"
            }
        }

        var systemImage: String {
            switch self {
            case .overview: "dot.radiowaves.left.and.right"
            case .receiver: "tv"
            case .media: "play.rectangle"
            case .localFiles: "externaldrive"
            case .namespace: "chevron.left.forwardslash.chevron.right"
            }
        }
    }

    enum NamespaceTargetChoice: String, CaseIterable, Identifiable {
        case currentApplication
        case platform
        case transport

        var id: Self {
            self
        }

        var title: String {
            switch self {
            case .currentApplication: "Current App"
            case .platform: "Platform"
            case .transport: "Transport"
            }
        }
    }

    enum SubtitleStylePreset: String, CaseIterable, Identifiable {
        case none
        case highContrast
        case karaoke

        var id: Self {
            self
        }

        var title: String {
            switch self {
            case .none: "None"
            case .highContrast: "High Contrast"
            case .karaoke: "Large Yellow"
            }
        }

        var castStyle: CastTextTrackStyle? {
            switch self {
            case .none:
                nil
            case .highContrast:
                .init(
                    backgroundColorRGBAHex: "#000000AA",
                    foregroundColorRGBAHex: "#FFFFFFFF",
                    edgeType: .dropShadow,
                    edgeColorRGBAHex: "#000000FF",
                    fontScale: 1,
                    fontGenericFamily: .sansSerif
                )
            case .karaoke:
                .init(
                    backgroundColorRGBAHex: "#00000066",
                    foregroundColorRGBAHex: "#FFFF00FF",
                    edgeType: .outline,
                    edgeColorRGBAHex: "#000000FF",
                    fontScale: 1.25,
                    fontStyle: .bold,
                    fontGenericFamily: .sansSerif
                )
            }
        }
    }

    struct LogEntry: Identifiable, Hashable {
        let id = UUID()
        let timestamp: Date
        let category: String
        let message: String
    }

    struct NamespaceLogEntry: Identifiable, Hashable {
        let id = UUID()
        let timestamp: Date
        let namespace: String
        let sourceID: String
        let destinationID: String
        let summary: String
        let payloadPreview: String
        let isBinary: Bool
    }
}
