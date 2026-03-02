//
//  ChromecastKit
//  SPDX-License-Identifier: Apache-2.0
//  Copyright 2026 Dionysis Karatzas
//

import OSLog
import Foundation

enum ChromecastKitLogCategory: String, Sendable {
    case discovery
    case session
    case transport
    case command
}

struct ChromecastKitDiagnosticsLogger: Sendable {
    private static let subsystem = "com.swift-chromecast-kit"

    private var level: ChromecastKitLogLevel
    private let category: String
    private let osLog: OSLog

    init(
        level: ChromecastKitLogLevel,
        category: ChromecastKitLogCategory
    ) {
        self.level = level
        self.category = category.rawValue
        self.osLog = OSLog(
            subsystem: Self.subsystem,
            category: category.rawValue
        )
    }

    mutating func setLevel(_ level: ChromecastKitLogLevel) {
        self.level = level
    }

    func trace(_ message: @autoclosure () -> String) {
        guard level.allows(.trace) else {
            return
        }
        emit(.trace, message())
    }

    func debug(_ message: @autoclosure () -> String) {
        guard level.allows(.debug) else {
            return
        }
        emit(.debug, message())
    }

    func info(_ message: @autoclosure () -> String) {
        guard level.allows(.info) else {
            return
        }
        emit(.info, message())
    }

    func warning(_ message: @autoclosure () -> String) {
        guard level.allows(.warning) else {
            return
        }
        emit(.warning, message())
    }

    func error(_ message: @autoclosure () -> String) {
        guard level.allows(.error) else {
            return
        }
        emit(.error, message())
    }

    private func emit(_ logLevel: ChromecastKitLogLevel, _ text: String) {
        if #available(iOS 14, macOS 11, *) {
            let logger = Logger(
                subsystem: Self.subsystem,
                category: category
            )
            switch logLevel {
            case .trace:
                logger.debug("[trace] \(text, privacy: .public)")
            case .debug:
                logger.debug("\(text, privacy: .public)")
            case .info:
                logger.info("\(text, privacy: .public)")
            case .warning:
                logger.notice("\(text, privacy: .public)")
            case .error:
                logger.error("\(text, privacy: .public)")
            case .none:
                break
            }
            return
        }

        let type: OSLogType
        let normalized: String
        switch logLevel {
        case .trace:
            type = .debug
            normalized = "[trace] \(text)"
        case .debug:
            type = .debug
            normalized = text
        case .info:
            type = .info
            normalized = text
        case .warning:
            type = .default
            normalized = "[warning] \(text)"
        case .error:
            type = .error
            normalized = text
        case .none:
            return
        }

        os_log("%{public}@", log: osLog, type: type, normalized)
    }
}
