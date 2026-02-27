//
//  ChromecastKit
//  SPDX-License-Identifier: Apache-2.0
//  Copyright 2026 Dionysis Karatzas
//

import Testing
import Foundation
@testable import ChromecastKit

@Suite("Cast Discovery Runtime")
struct CastDiscoveryTests {
    @Test("start transitions to running and emits started")
    func startSuccess() async throws {
        let browser = RecordingDiscoveryBrowser()
        let discovery = CastDiscovery(browser: browser)
        var events = await discovery.events().makeAsyncIterator()

        try await discovery.start()

        #expect(await discovery.state() == .running)
        #expect(await browser.startCount() == 1)

        let event = await events.next()
        #expect(event == .started)
    }

    @Test("start failure sets failed state and emits error")
    func startFailure() async throws {
        let browser = RecordingDiscoveryBrowser(startError: CastError.discoveryFailed("mdns failed"))
        let discovery = CastDiscovery(browser: browser)
        var events = await discovery.events().makeAsyncIterator()

        await #expect(throws: CastError.self) {
            try await discovery.start()
        }

        guard case .failed = await discovery.state() else {
            Issue.record("Expected failed discovery state")
            return
        }

        let event = await events.next()
        guard case let .error(error)? = event else {
            Issue.record("Expected error event")
            return
        }
        #expect(error == .discoveryFailed("mdns failed"))
    }

    @Test("device upsert and removal updates snapshot and emits events")
    func deviceUpsertAndRemoval() async {
        let browser = RecordingDiscoveryBrowser()
        let discovery = CastDiscovery(browser: browser)
        var events = await discovery.events().makeAsyncIterator()

        let device = CastDeviceDescriptor(
            id: "device-1",
            friendlyName: "Living Room TV",
            host: "192.168.1.20"
        )
        let updatedDevice = CastDeviceDescriptor(
            id: "device-1",
            friendlyName: "Living Room TV",
            host: "192.168.1.21"
        )

        await discovery.upsertDiscoveredDevice(device)
        await discovery.upsertDiscoveredDevice(updatedDevice)
        await discovery.removeDiscoveredDevice(id: "device-1")

        let snapshot = await discovery.devices()
        #expect(snapshot.isEmpty)

        guard case let .deviceUpserted(first, isNew: firstIsNew)? = await events.next() else {
            Issue.record("Expected first device upsert event")
            return
        }
        #expect(first == device)
        #expect(firstIsNew)

        guard case let .deviceUpserted(second, isNew: secondIsNew)? = await events.next() else {
            Issue.record("Expected second device upsert event")
            return
        }
        #expect(second == updatedDevice)
        #expect(!secondIsNew)

        #expect(await events.next() == .deviceRemoved(id: "device-1"))
    }

    @Test("stop transitions to stopped and emits stopped")
    func stop() async throws {
        let browser = RecordingDiscoveryBrowser()
        let discovery = CastDiscovery(browser: browser)
        var events = await discovery.events().makeAsyncIterator()

        try await discovery.start()
        _ = await events.next()

        await discovery.stop()

        #expect(await discovery.state() == .stopped)
        #expect(await browser.stopCount() == 1)
        #expect(await events.next() == .stopped)
    }

    @Test("restart stops then starts discovery")
    func restart() async throws {
        let browser = RecordingDiscoveryBrowser()
        let discovery = CastDiscovery(browser: browser)

        try await discovery.start()
        try await discovery.restart()

        #expect(await discovery.state() == .running)
        #expect(await browser.startCount() == 2)
        #expect(await browser.stopCount() == 1)
    }

    @Test("browse timeout auto-stops discovery")
    func browseTimeoutStopsDiscovery() async throws {
        let browser = RecordingDiscoveryBrowser()
        let discovery = CastDiscovery(
            configuration: .init(includeGroups: true, browseTimeout: 0.01),
            browser: browser
        )
        var events = await discovery.events().makeAsyncIterator()

        try await discovery.start()
        #expect(await events.next() == .started)

        try await Task.sleep(nanoseconds: 120_000_000)

        #expect(await discovery.state() == .stopped)
        #expect(await browser.stopCount() == 1)
        #expect(await events.next() == .stopped)
    }

    @Test("browser runtime error stops browsing and allows restart")
    func browserRuntimeErrorStopsAndCanRestart() async throws {
        let browser = RecordingDiscoveryBrowser()
        let discovery = CastDiscovery(browser: browser)
        var events = await discovery.events().makeAsyncIterator()

        try await discovery.start()
        #expect(await events.next() == .started)

        await browser.emit(.error(.discoveryFailed("bonjour runtime error")))

        let errorEvent = await events.next()
        guard case let .error(error)? = errorEvent else {
            Issue.record("Expected discovery error event")
            return
        }
        #expect(error == .discoveryFailed("bonjour runtime error"))
        #expect(await discovery.state() == .failed(.discoveryFailed("bonjour runtime error")))
        #expect(await browser.stopCount() == 1)

        try await discovery.start()
        #expect(await discovery.state() == .running)
        #expect(await browser.startCount() == 2)
    }

    @Test("lookup helpers find devices by id and friendly name")
    func deviceLookupHelpers() async {
        let browser = RecordingDiscoveryBrowser()
        let discovery = CastDiscovery(browser: browser)
        let device = CastDeviceDescriptor(
            id: "device-1",
            friendlyName: "Living Room TV",
            host: "192.168.1.20"
        )

        await discovery.upsertDiscoveredDevice(device)

        #expect(await discovery.device(id: "device-1") == device)
        #expect(await discovery.device(named: "Living Room TV") == device)
        #expect(await discovery.device(named: "living room tv") == device)
        #expect(await discovery.device(named: "living room tv", caseInsensitive: false) == nil)
    }

    @Test("waitForDevice returns when matching device is discovered")
    func waitForDeviceByName() async throws {
        let browser = RecordingDiscoveryBrowser()
        let discovery = CastDiscovery(browser: browser)

        let waiter = Task {
            try await discovery.waitForDevice(named: "Kitchen Speaker", timeout: 1)
        }

        await discovery.upsertDiscoveredDevice(
            .init(
                id: "kitchen-1",
                friendlyName: "Kitchen Speaker",
                host: "192.168.1.44"
            )
        )

        let resolved = try await waiter.value
        #expect(resolved.id == "kitchen-1")
    }

    @Test("waitForDevice times out when no matching device arrives")
    func waitForDeviceTimeout() async {
        let browser = RecordingDiscoveryBrowser()
        let discovery = CastDiscovery(browser: browser)

        await #expect(throws: CastError.self) {
            try await discovery.waitForDevice(id: "missing-device", timeout: 0.01)
        }
    }

    @Test("waitForFirstDevice returns existing or first arriving device")
    func waitForFirstDevice() async throws {
        let browser = RecordingDiscoveryBrowser()
        let discovery = CastDiscovery(browser: browser)

        await discovery.upsertDiscoveredDevice(
            .init(id: "living-room", friendlyName: "Living Room", host: "192.168.1.22")
        )
        let existing = try await discovery.waitForFirstDevice(timeout: 0.1)
        #expect(existing.id == "living-room")

        let discovery2 = CastDiscovery(browser: RecordingDiscoveryBrowser())
        let waiter = Task { try await discovery2.waitForFirstDevice(timeout: 1) }
        await discovery2.upsertDiscoveredDevice(
            .init(id: "kitchen", friendlyName: "Kitchen", host: "192.168.1.23")
        )
        let arrived = try await waiter.value
        #expect(arrived.id == "kitchen")
    }

    @Test("manual known-host helpers upsert and remove snapshot devices")
    func manualKnownHostHelpers() async {
        let browser = RecordingDiscoveryBrowser()
        let discovery = CastDiscovery(browser: browser)
        var events = await discovery.events().makeAsyncIterator()

        let manual = await discovery.addKnownHost(
            host: "192.168.1.55",
            friendlyName: "Office Speaker",
            capabilities: [.audio, .multizone]
        )
        #expect(manual.id == "manual:192.168.1.55:8009")
        #expect(await discovery.device(id: manual.id) == manual)

        await discovery.removeKnownDevice(id: manual.id)
        #expect(await discovery.device(id: manual.id) == nil)

        #expect(await events.next() == .deviceUpserted(device: manual, isNew: true))
        #expect(await events.next() == .deviceRemoved(id: manual.id))
    }

    @Test("deduplicates mDNS and SSDP views of the same device by host and preserves richer metadata")
    func deduplicatesDiscoveredDevicesAcrossBackends() async {
        let browser = RecordingDiscoveryBrowser()
        let discovery = CastDiscovery(browser: browser)
        var events = await discovery.events().makeAsyncIterator()

        let mdns = CastDeviceDescriptor(
            id: "mdns-id",
            friendlyName: "Living Room TV",
            host: "192.168.1.20",
            port: 8009,
            modelName: "Chromecast",
            manufacturer: "Google",
            uuid: UUID(uuidString: "12345678-1234-1234-1234-1234567890ab"),
            capabilities: [.video]
        )
        let ssdp = CastDeviceDescriptor(
            id: "ssdp:192.168.1.20:8009",
            friendlyName: "192.168.1.20",
            host: "192.168.1.20",
            port: 8009,
            modelName: nil,
            manufacturer: nil,
            uuid: UUID(uuidString: "12345678-1234-1234-1234-1234567890ab"),
            capabilities: [.video, .multizone]
        )

        await discovery.upsertDiscoveredDevice(mdns)
        await discovery.upsertDiscoveredDevice(ssdp)

        let snapshot = await discovery.devices()
        #expect(snapshot.count == 1)
        let only = snapshot[0]
        #expect(only.id == "mdns-id")
        #expect(only.friendlyName == "Living Room TV")
        #expect(only.capabilities.contains(.multizone) == true)

        _ = await events.next() // first insert
        guard case let .deviceUpserted(device, isNew)? = await events.next() else {
            Issue.record("Expected merged dedupe upsert")
            return
        }
        #expect(isNew == false)
        #expect(device.id == "mdns-id")
        #expect(device.capabilities.contains(.multizone))
    }

    @Test("dedupe by UUID refreshes endpoint host and port from latest descriptor")
    func dedupeRefreshesEndpointFromLatestDescriptor() async {
        let browser = RecordingDiscoveryBrowser()
        let discovery = CastDiscovery(browser: browser)

        let initial = CastDeviceDescriptor(
            id: "mdns-id",
            friendlyName: "Living Room TV",
            host: "192.168.1.20",
            port: 8009,
            modelName: "Chromecast",
            manufacturer: "Google",
            uuid: UUID(uuidString: "12345678-1234-1234-1234-1234567890ab"),
            capabilities: [.video]
        )
        let refreshedEndpoint = CastDeviceDescriptor(
            id: "ssdp:living-room",
            friendlyName: "192.168.1.44",
            host: "192.168.1.44",
            port: 9000,
            modelName: nil,
            manufacturer: nil,
            uuid: UUID(uuidString: "12345678-1234-1234-1234-1234567890ab"),
            capabilities: [.video, .multizone]
        )

        await discovery.upsertDiscoveredDevice(initial)
        await discovery.upsertDiscoveredDevice(refreshedEndpoint)

        let snapshot = await discovery.devices()
        #expect(snapshot.count == 1)
        let only = snapshot[0]
        #expect(only.id == "mdns-id")
        #expect(only.host == "192.168.1.44")
        #expect(only.port == 9000)
        #expect(only.friendlyName == "Living Room TV")
        #expect(only.capabilities.contains(.multizone))
    }
}

private actor RecordingDiscoveryBrowser: CastDiscoveryBrowser {
    private let startError: (any Error)?
    private var startCalls = 0
    private var stopCalls = 0
    private var continuations = [UUID: AsyncStream<CastDiscoveryBrowserEvent>.Continuation]()

    init(startError: (any Error)? = nil) {
        self.startError = startError
    }

    func events() async -> AsyncStream<CastDiscoveryBrowserEvent> {
        let id = UUID()
        return AsyncStream { continuation in
            continuations[id] = continuation
            continuation.onTermination = { [id] _ in
                Task { await self.removeContinuation(id: id) }
            }
        }
    }

    func start(configuration _: CastDiscovery.Configuration) async throws {
        startCalls += 1
        if let startError {
            throw startError
        }
    }

    func stop() async {
        stopCalls += 1
    }

    func startCount() -> Int {
        startCalls
    }

    func stopCount() -> Int {
        stopCalls
    }

    func emit(_ event: CastDiscoveryBrowserEvent) {
        for continuation in continuations.values {
            continuation.yield(event)
        }
    }

    private func removeContinuation(id: UUID) {
        continuations[id] = nil
    }
}
