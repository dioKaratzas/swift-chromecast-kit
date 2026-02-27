//
//  ChromecastKit
//  SPDX-License-Identifier: Apache-2.0
//  Copyright 2026 Dionysis Karatzas
//

import Testing
import Foundation
@testable import ChromecastKit

@Suite("Cast Session Policy Models")
struct CastSessionPolicyTests {
    @Test("reconnect policy normalizes invalid init values")
    func reconnectPolicyNormalization() {
        let policy = CastSession.ReconnectPolicy(
            backoffStrategy: .exponential,
            initialDelay: -1,
            maxDelay: -5,
            multiplier: 0.4,
            jitterFactor: 2.5,
            maxAttempts: -10,
            waitsForReachableNetworkPath: true,
            networkPathWaitTimeout: -3
        )

        #expect(policy.initialDelay == 0)
        #expect(policy.maxDelay == 0)
        #expect(policy.multiplier == 1)
        #expect(policy.jitterFactor == 1)
        #expect(policy.maxAttempts == 0)
        #expect(policy.networkPathWaitTimeout == 0)
    }

    @Test("fixed retry delay returns constant values and ignores random unit when jitter is zero")
    func fixedRetryDelay() {
        let policy = CastSession.ReconnectPolicy.fixed(delay: 2, jitterFactor: 0)

        #expect(policy.retryDelay(forAttempt: 0, randomUnit: 0.2) == 0)
        #expect(policy.retryDelay(forAttempt: 1, randomUnit: 0.0) == 2)
        #expect(policy.retryDelay(forAttempt: 3, randomUnit: 1.0) == 2)
    }

    @Test("exponential retry delay applies clamping and jitter bounds")
    func exponentialRetryDelayJitterAndClamp() {
        let policy = CastSession.ReconnectPolicy.exponential(
            initialDelay: 1,
            maxDelay: 4,
            multiplier: 2,
            jitterFactor: 0.25,
            maxAttempts: nil,
            waitsForReachableNetworkPath: true
        )

        // attempt 1 => base 1; random 0 => -25% jitter
        #expect(policy.retryDelay(forAttempt: 1, randomUnit: 0) == 0.75)

        // attempt 1 => base 1; random 0.5 => center (no jitter)
        #expect(policy.retryDelay(forAttempt: 1, randomUnit: 0.5) == 1)

        // attempt 4 => base 8, clamped to 4; random 1 => +25% jitter
        #expect(policy.retryDelay(forAttempt: 4, randomUnit: 1) == 5)
    }

    @Test("configuration reconnectRetryDelay mirrors resolved reconnect policy")
    func configurationReconnectAliasUsesPolicy() {
        let fixed = CastSession.ReconnectPolicy.fixed(delay: 5)
        let configuration = CastSession.Configuration(reconnectRetryDelay: 1, reconnectPolicy: fixed)

        #expect(configuration.reconnectPolicy.initialDelay == 5)
        #expect(configuration.reconnectRetryDelay == 5)
    }

    @Test("configuration derives exponential policy from reconnectRetryDelay when policy is omitted")
    func configurationReconnectAliasWithoutPolicy() {
        let configuration = CastSession.Configuration(reconnectRetryDelay: 3, reconnectPolicy: nil)

        #expect(configuration.reconnectPolicy.backoffStrategy == .exponential)
        #expect(configuration.reconnectPolicy.initialDelay == 3)
        #expect(configuration.reconnectRetryDelay == 3)
    }
}
