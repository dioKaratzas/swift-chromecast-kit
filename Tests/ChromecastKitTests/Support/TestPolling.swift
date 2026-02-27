//
//  ChromecastKit
//  SPDX-License-Identifier: Apache-2.0
//  Copyright 2026 Dionysis Karatzas
//

import Foundation

enum TestPolling {
    static let defaultIntervalNanoseconds: UInt64 = 1_000_000

    static func waitUntil(
        timeout: TimeInterval,
        intervalNanoseconds: UInt64 = defaultIntervalNanoseconds,
        condition: () async -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await condition() {
                return true
            }
            try? await Task.sleep(nanoseconds: intervalNanoseconds)
        }
        return await condition()
    }
}
