//
//  ChromecastKit
//  Swift package for Google Cast (Chromecast).
//

import Testing
import Foundation
@testable import ChromecastKit

@Suite("SSDP Discovery Browser Backend Cache")
struct SSDPCastDiscoveryBrowserTests {
    @Test("registry expires only entries whose cache max-age has elapsed")
    func registryExpiry() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let urlA = try #require(URL(string: "http://192.168.1.10:8008/ssdp/device-desc.xml"))
        let urlB = try #require(URL(string: "http://192.168.1.11:8008/ssdp/device-desc.xml"))

        var registry = SSDPCastDiscoveryBrowser.KnownLocationRegistry()
        registry.upsert(locationURL: urlA, deviceID: "a", cacheMaxAge: 10, now: now)
        registry.upsert(locationURL: urlB, deviceID: "b", cacheMaxAge: 30, now: now)

        let firstExpired = registry.expire(now: now.addingTimeInterval(15))
        #expect(firstExpired == ["a"])
        #expect(Set(registry.entries.keys) == [urlB])

        let secondExpired = registry.expire(now: now.addingTimeInterval(31))
        #expect(secondExpired == ["b"])
        #expect(registry.entries.isEmpty)
    }

    @Test("registry keeps entries without cache max-age until explicit removal")
    func registryKeepsNonExpiringEntries() throws {
        let now = Date(timeIntervalSince1970: 2_000)
        let url = try #require(URL(string: "http://192.168.1.12:8008/ssdp/device-desc.xml"))

        var registry = SSDPCastDiscoveryBrowser.KnownLocationRegistry()
        registry.upsert(locationURL: url, deviceID: "c", cacheMaxAge: nil, now: now)

        let expired = registry.expire(now: now.addingTimeInterval(10_000))
        #expect(expired.isEmpty)
        #expect(registry.entries[url]?.deviceID == "c")
    }

    @Test("registry refresh replaces expiry deadline for same location")
    func registryRefreshExtendsExpiry() throws {
        let now = Date(timeIntervalSince1970: 3_000)
        let url = try #require(URL(string: "http://192.168.1.13:8008/ssdp/device-desc.xml"))

        var registry = SSDPCastDiscoveryBrowser.KnownLocationRegistry()
        registry.upsert(locationURL: url, deviceID: "d", cacheMaxAge: 5, now: now)
        registry.upsert(locationURL: url, deviceID: "d", cacheMaxAge: 20, now: now.addingTimeInterval(1))

        let earlyExpired = registry.expire(now: now.addingTimeInterval(8))
        #expect(earlyExpired.isEmpty)
        #expect(registry.entries[url] != nil)

        let lateExpired = registry.expire(now: now.addingTimeInterval(25))
        #expect(lateExpired == ["d"])
        #expect(registry.entries.isEmpty)
    }
}
