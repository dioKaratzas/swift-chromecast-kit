import Foundation

struct SubtitleCue: Sendable, Hashable {
    let start: TimeInterval
    let end: TimeInterval
    let text: String
}

enum WebVTTParser {
    static func parse(from fileURL: URL) throws -> [SubtitleCue] {
        guard fileURL.isFileURL else {
            throw ParseError.invalidInput("Subtitle file must be local")
        }

        let text = try String(contentsOf: fileURL, encoding: .utf8)
        return try parse(text: text)
    }

    static func parse(text: String) throws -> [SubtitleCue] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let blocks = normalized.components(separatedBy: "\n\n")

        var cues = [SubtitleCue]()
        cues.reserveCapacity(blocks.count)

        for rawBlock in blocks {
            let lines = rawBlock
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }

            guard lines.isEmpty == false else {
                continue
            }

            if lines[0].uppercased().hasPrefix("WEBVTT") {
                continue
            }
            if lines[0].hasPrefix("NOTE") || lines[0].hasPrefix("STYLE") || lines[0].hasPrefix("REGION") {
                continue
            }

            let timingLineIndex: Int
            if lines[0].contains("-->") {
                timingLineIndex = 0
            } else if lines.count > 1, lines[1].contains("-->") {
                timingLineIndex = 1
            } else {
                continue
            }

            let timingLine = lines[timingLineIndex]
            let cueTextLines = lines[(timingLineIndex + 1) ..< lines.count]
                .filter { $0.isEmpty == false }

            guard let (start, end) = parseTimingLine(timingLine), cueTextLines.isEmpty == false else {
                continue
            }

            let cueText = cueTextLines
                .joined(separator: "\n")
                .replacingOccurrences(of: "<br>", with: "\n")
                .replacingOccurrences(of: "<br/>", with: "\n")
                .replacingOccurrences(of: "<br />", with: "\n")

            cues.append(.init(start: start, end: end, text: cueText))
        }

        return cues.sorted { lhs, rhs in
            if lhs.start == rhs.start {
                return lhs.end < rhs.end
            }
            return lhs.start < rhs.start
        }
    }

    private static func parseTimingLine(_ line: String) -> (TimeInterval, TimeInterval)? {
        let segments = line.components(separatedBy: "-->")
        guard segments.count == 2 else {
            return nil
        }

        let startToken = segments[0].trimmingCharacters(in: .whitespaces)
        let endToken = segments[1]
            .trimmingCharacters(in: .whitespaces)
            .split(separator: " ", omittingEmptySubsequences: true)
            .first
            .map(String.init)

        guard let endToken,
              let startTime = parseTimestamp(startToken),
              let endTime = parseTimestamp(endToken),
              endTime >= startTime else {
            return nil
        }

        return (startTime, endTime)
    }

    private static func parseTimestamp(_ token: String) -> TimeInterval? {
        let sanitized = token
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")

        let parts = sanitized.split(separator: ":", omittingEmptySubsequences: false)
        if parts.count == 3 {
            guard let hours = Double(parts[0]),
                  let minutes = Double(parts[1]),
                  let seconds = Double(parts[2]) else {
                return nil
            }
            return (hours * 3600) + (minutes * 60) + seconds
        }

        if parts.count == 2 {
            guard let minutes = Double(parts[0]),
                  let seconds = Double(parts[1]) else {
                return nil
            }
            return (minutes * 60) + seconds
        }

        return nil
    }

    enum ParseError: Error {
        case invalidInput(String)
    }
}
