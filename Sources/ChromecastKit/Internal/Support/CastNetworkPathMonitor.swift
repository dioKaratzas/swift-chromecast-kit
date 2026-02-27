//
//  ChromecastKit
//  Swift package for Google Cast (Chromecast).
//

import Foundation

#if canImport(Network)
    import Network
#endif

enum CastNetworkPathStatus: String, Sendable {
    case satisfied
    case unsatisfied
    case requiresConnection
    case unknown
}

protocol CastNetworkPathMonitoring: Sendable {
    func status() async -> CastNetworkPathStatus
    func waitForReachable(timeout: TimeInterval?) async -> Bool
}

actor CastSystemNetworkPathMonitor: CastNetworkPathMonitoring {
    private var statusValue: CastNetworkPathStatus
    private var continuations = [UUID: AsyncStream<CastNetworkPathStatus>.Continuation]()

    #if canImport(Network)
        private let monitor: NWPathMonitor?
        private let queue: DispatchQueue
    #endif

    init() {
        #if canImport(Network)
            self.statusValue = .unknown
            self.monitor = NWPathMonitor()
            self.queue = DispatchQueue(label: "ChromecastKit.CastNetworkPathMonitor")
            monitor?.pathUpdateHandler = { [weak self] path in
                Task { await self?.handle(path.status) }
            }
            monitor?.start(queue: queue)
        #else
            self.statusValue = .satisfied
        #endif
    }

    deinit {
        #if canImport(Network)
            monitor?.cancel()
        #endif
    }

    func status() -> CastNetworkPathStatus {
        statusValue
    }

    func waitForReachable(timeout: TimeInterval?) async -> Bool {
        if statusValue == .satisfied {
            return true
        }

        let stream = updates()
        return await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                var iterator = stream.makeAsyncIterator()
                while let status = await iterator.next() {
                    if status == .satisfied {
                        return true
                    }
                    if Task.isCancelled {
                        return false
                    }
                }
                return false
            }

            if let timeout, timeout > 0 {
                group.addTask {
                    do {
                        try await CastTaskTiming.sleep(for: timeout)
                    } catch {
                        return false
                    }
                    return false
                }
            }

            let result = await group.next() ?? false
            group.cancelAll()
            return result
        }
    }

    private func updates() -> AsyncStream<CastNetworkPathStatus> {
        let id = UUID()
        return AsyncStream { continuation in
            continuations[id] = continuation
            continuation.onTermination = { [id] _ in
                Task { await self.removeContinuation(id: id) }
            }
        }
    }

    private func removeContinuation(id: UUID) {
        continuations[id] = nil
    }

    #if canImport(Network)
        private func handle(_ status: NWPath.Status) {
            let mappedStatus: CastNetworkPathStatus
            switch status {
            case .satisfied:
                mappedStatus = .satisfied
            case .unsatisfied:
                mappedStatus = .unsatisfied
            case .requiresConnection:
                mappedStatus = .requiresConnection
            @unknown default:
                mappedStatus = .unknown
            }

            statusValue = mappedStatus
            for continuation in continuations.values {
                continuation.yield(mappedStatus)
            }
        }
    #endif
}
