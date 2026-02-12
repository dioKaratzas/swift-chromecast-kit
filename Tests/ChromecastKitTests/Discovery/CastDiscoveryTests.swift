//
//  ChromecastKit
//  Swift package for Google Cast (Chromecast).
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

    func start(configuration _: CastDiscoveryConfiguration) async throws {
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

    private func removeContinuation(id: UUID) {
        continuations[id] = nil
    }
}
