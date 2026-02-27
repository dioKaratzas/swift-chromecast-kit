//
//  ChromecastKit
//  SPDX-License-Identifier: Apache-2.0
//  Copyright 2026 Dionysis Karatzas
//

import Foundation

enum CastTaskTiming {
    static func nanoseconds(
        from seconds: TimeInterval,
        minimum minimumSeconds: TimeInterval = 0
    ) -> UInt64 {
        let clampedSeconds = max(seconds, minimumSeconds)
        let nanoseconds = clampedSeconds * 1_000_000_000

        guard nanoseconds.isFinite else {
            return UInt64.max
        }
        guard nanoseconds > 0 else {
            return 0
        }
        return UInt64(min(nanoseconds, Double(UInt64.max)))
    }

    static func sleep(for seconds: TimeInterval) async throws {
        try await Task.sleep(nanoseconds: nanoseconds(from: seconds))
    }

    static func sleep(for seconds: TimeInterval, minimum minimumSeconds: TimeInterval) async throws {
        try await Task.sleep(nanoseconds: nanoseconds(from: seconds, minimum: minimumSeconds))
    }
}
