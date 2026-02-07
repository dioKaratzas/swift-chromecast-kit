//
//  ChromecastKit
//  Swift package for Google Cast (Chromecast).
//

import Foundation
import Observation
import ChromecastKit

@MainActor
@Observable
final class DiscoveryFeatureModel {
    enum Phase: Equatable {
        case idle
        case starting
        case running
        case failed(String)

        var title: String {
            switch self {
            case .idle: return "Idle"
            case .starting: return "Starting"
            case .running: return "Running"
            case let .failed(message): return "Failed: \(message)"
            }
        }

        var isRunning: Bool {
            if case .running = self {
                return true
            }
            return false
        }
    }

    struct EventLogEntry: Identifiable, Equatable {
        let id = UUID()
        let timestamp: Date
        let message: String
    }

    private let discovery: CastDiscovery
    private var eventTask: Task<Void, Never>?
    private var startTask: Task<Void, Never>?

    var phase = Phase.idle
    var devices = [CastDeviceDescriptor]()
    var latestError: String?
    var eventLog = [EventLogEntry]()

    init(discovery: CastDiscovery = CastDiscovery()) {
        self.discovery = discovery
    }

    func onAppear() {
        startEventListenerIfNeeded()
        guard phase == .idle else {
            return
        }
        startDiscovery()
    }

    func startDiscovery() {
        startEventListenerIfNeeded()
        startTask?.cancel()
        startTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            self.phase = .starting
            do {
                try await self.discovery.start()
                await self.reloadSnapshot()
                self.appendEvent("Discovery started")
            } catch {
                let message = Self.message(for: error)
                self.latestError = message
                self.phase = .failed(message)
                self.appendEvent("Start failed: \(message)")
            }
        }
    }

    func stopDiscovery() {
        startTask?.cancel()
        startTask = nil
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            await self.discovery.stop()
            await self.reloadSnapshot()
            self.phase = .idle
            self.appendEvent("Discovery stopped")
        }
    }

    func clearDiscoveredDevices() {
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            await self.discovery.clearDevices()
            await self.reloadSnapshot()
            self.appendEvent("Cleared device snapshot")
        }
    }

    func refreshSnapshot() {
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            await self.reloadSnapshot()
            self.appendEvent("Snapshot refreshed")
        }
    }

    private func startEventListenerIfNeeded() {
        guard eventTask == nil else {
            return
        }

        eventTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            let stream = await self.discovery.events()
            for await event in stream {
                await self.handle(event)
            }
        }
    }

    private func handle(_ event: CastDiscoveryEvent) async {
        switch event {
        case .started:
            phase = .running
            latestError = nil
        case .stopped:
            if case .failed = phase {} else {
                phase = .idle
            }
        case let .deviceUpserted(device, isNew):
            await reloadSnapshot()
            appendEvent("\(isNew ? "Found" : "Updated"): \(device.friendlyName) @ \(device.host):\(device.port)")
        case let .deviceRemoved(id):
            await reloadSnapshot()
            appendEvent("Removed: \(id.rawValue)")
        case let .error(error):
            let message = Self.message(for: error)
            latestError = message
            phase = .failed(message)
            appendEvent("Error: \(message)")
        }
    }

    private func reloadSnapshot() async {
        devices = await discovery.devices()

        switch await discovery.state() {
        case .running:
            phase = .running
        case .starting:
            phase = .starting
        case .stopped:
            if case .failed = phase {
                // Keep explicit failure state until the user restarts or clears.
            } else {
                phase = .idle
            }
        case let .failed(error):
            let message = Self.message(for: error)
            latestError = message
            phase = .failed(message)
        }
    }

    private func appendEvent(_ message: String) {
        eventLog.insert(.init(timestamp: .now, message: message), at: 0)
        if eventLog.count > 200 {
            eventLog.removeLast(eventLog.count - 200)
        }
    }

    private static func message(for error: any Error) -> String {
        if let castError = error as? CastError {
            return String(describing: castError)
        }
        return String(describing: error)
    }
}
