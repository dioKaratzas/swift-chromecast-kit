//
//  ChromecastKit
//  SPDX-License-Identifier: Apache-2.0
//  Copyright 2026 Dionysis Karatzas
//

import Foundation

/// Logging verbosity for `ChromecastKit` runtime diagnostics.
///
/// The default `.error` keeps framework logging low-noise while still reporting
/// actionable failures. Use `.debug` or `.trace` for temporary troubleshooting.
public enum ChromecastKitLogLevel: Int, CaseIterable, Sendable, Hashable, Codable {
    /// Disable framework logs.
    case none = 0
    /// Emit only errors.
    case error = 1
    /// Emit warnings and errors.
    case warning = 2
    /// Emit informational milestones, warnings, and errors.
    case info = 3
    /// Emit debug diagnostics in addition to info-level logs.
    case debug = 4
    /// Emit the most verbose diagnostics.
    case trace = 5

    func allows(_ level: ChromecastKitLogLevel) -> Bool {
        self != .none && rawValue >= level.rawValue
    }
}
