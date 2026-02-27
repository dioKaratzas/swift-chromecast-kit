//
//  ChromecastKit
//  SPDX-License-Identifier: Apache-2.0
//  Copyright 2026 Dionysis Karatzas
//

import Foundation

/// Shared ISO-8601 date parse/format helper used by Cast payload/status mapping.
///
/// Reuses a single formatter instance and serializes access through a lock.
enum CastISO8601Coding {
  private static let lock = NSLock()
  private nonisolated(unsafe) static let formatter = ISO8601DateFormatter()

  static func parse(_ value: String) -> Date? {
    lock.lock()
    defer { lock.unlock() }
    return formatter.date(from: value)
  }

  static func format(_ date: Date) -> String {
    lock.lock()
    defer { lock.unlock() }
    return formatter.string(from: date)
  }
}
