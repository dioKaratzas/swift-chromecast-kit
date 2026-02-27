//
//  ChromecastKit
//  Swift package for Google Cast (Chromecast).
//

import Foundation
import ChromecastKit

extension PlayerModel {
    struct SubtitleTrack: Identifiable, Hashable, Sendable {
        let id: UUID
        let fileURL: URL
        let displayName: String
        let cues: [SubtitleCue]
    }

    struct SubtitleRGBColor: Hashable, Sendable {
        var red: Double
        var green: Double
        var blue: Double

        init(red: Double, green: Double, blue: Double) {
            self.red = min(max(red, 0), 1)
            self.green = min(max(green, 0), 1)
            self.blue = min(max(blue, 0), 1)
        }

        var rgbHex: String {
            let r = Int((red * 255).rounded())
            let g = Int((green * 255).rounded())
            let b = Int((blue * 255).rounded())
            return String(format: "%02X%02X%02X", r, g, b)
        }

        static let white = SubtitleRGBColor(red: 1, green: 1, blue: 1)
        static let black = SubtitleRGBColor(red: 0, green: 0, blue: 0)
    }

    enum SubtitleEdgeStyleOption: String, CaseIterable, Identifiable, Sendable {
        case dropShadow
        case outline
        case none

        var id: Self {
            self
        }

        var title: String {
            switch self {
            case .dropShadow: "Drop Shadow"
            case .outline: "Outline"
            case .none: "None"
            }
        }

        var castEdgeType: CastTextTrackEdgeType {
            switch self {
            case .dropShadow: .dropShadow
            case .outline: .outline
            case .none: .none
            }
        }
    }

    struct LogEntry: Identifiable, Hashable {
        let id = UUID()
        let timestamp: Date
        let message: String
    }

    enum SeekDirection {
        case backward
        case forward
    }
}
