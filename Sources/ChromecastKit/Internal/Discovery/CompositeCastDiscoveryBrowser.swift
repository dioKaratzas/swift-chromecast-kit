//
//  ChromecastKit
//  Swift package for Google Cast (Chromecast).
//

import Foundation

/// Aggregates multiple internal discovery backends behind the same browser contract.
///
/// The public `CastDiscovery` actor performs deduplication and state ownership, so this
/// composite simply forwards backend events.
actor CompositeCastDiscoveryBrowser: CastDiscoveryBrowser {
    // MARK: State

    private let mdnsBrowser: any CastDiscoveryBrowser
    private let ssdpBrowser: any CastDiscoveryBrowser

    private var eventContinuations = [UUID: AsyncStream<CastDiscoveryBrowserEvent>.Continuation]()
    private var backendTasks = [Task<Void, Never>]()
    private var isRunning = false

    // MARK: Initialization

    init(
        mdnsBrowser: any CastDiscoveryBrowser = NWDNSSDDiscoveryBrowser(),
        ssdpBrowser: any CastDiscoveryBrowser = SSDPCastDiscoveryBrowser()
    ) {
        self.mdnsBrowser = mdnsBrowser
        self.ssdpBrowser = ssdpBrowser
    }

    // MARK: CastDiscoveryBrowser

    func events() async -> AsyncStream<CastDiscoveryBrowserEvent> {
        let id = UUID()
        return AsyncStream { continuation in
            eventContinuations[id] = continuation
            continuation.onTermination = { [id] _ in
                Task { await self.removeContinuation(id: id) }
            }
        }
    }

    func start(configuration: CastDiscoveryConfiguration) async throws {
        guard isRunning == false else {
            return
        }
        isRunning = true

        startForwardingTask(for: mdnsBrowser)

        do {
            try await mdnsBrowser.start(configuration: configuration)
        } catch {
            await stop()
            throw error
        }

        if configuration.enableSSDPFallback {
            startForwardingTask(for: ssdpBrowser)
            do {
                try await ssdpBrowser.start(configuration: configuration)
            } catch {
                // SSDP is best-effort fallback. Emit an error event but keep mDNS running.
                emit(error as? CastError ?? .discoveryFailed(String(describing: error)))
            }
        }
    }

    func stop() async {
        guard isRunning else {
            return
        }
        isRunning = false

        for task in backendTasks {
            task.cancel()
        }
        backendTasks.removeAll(keepingCapacity: false)

        await mdnsBrowser.stop()
        await ssdpBrowser.stop()
    }

    // MARK: Private Helpers

    private func startForwardingTask(for browser: any CastDiscoveryBrowser) {
        let task = Task {
            let stream = await browser.events()
            for await event in stream {
                self.forward(event)
            }
        }
        backendTasks.append(task)
    }

    private func forward(_ event: CastDiscoveryBrowserEvent) {
        for continuation in eventContinuations.values {
            continuation.yield(event)
        }
    }

    private func emit(_ error: CastError) {
        forward(.error(error))
    }

    private func removeContinuation(id: UUID) {
        eventContinuations[id] = nil
    }
}
