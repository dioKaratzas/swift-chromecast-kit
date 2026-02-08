//
//  ChromecastKit
//  Swift package for Google Cast (Chromecast).
//

@preconcurrency import Network
import Dispatch
import Foundation

/// Internal Cast v2 transport implemented on top of `NWConnection` (TLS over TCP/8009).
///
/// It sends typed Cast commands using the Cast v2 protobuf envelope and emits inbound JSON
/// messages for the current controller/session pipeline. Binary envelopes are decoded at the
/// transport layer but ignored by the JSON-only session runtime for now.
actor NWTLSCastV2Transport: CastConnectionTransport, CastCommandTransport, CastInboundMessageTransport, CastInboundEventTransport {
    private let device: CastDeviceDescriptor
    private let callbackQueue = DispatchQueue(label: "ChromecastKit.Transport.CastV2")
    private let receiveChunkSize: Int

    private var connection: NWConnection?
    private var inboundContinuations = [UUID: AsyncStream<CastInboundMessage>.Continuation]()
    private var inboundEventContinuations = [UUID: AsyncStream<CastInboundTransportEvent>.Continuation]()
    private var readLoopTask: Task<Void, Never>?

    init(device: CastDeviceDescriptor, receiveChunkSize: Int = 64 * 1024) {
        self.device = device
        self.receiveChunkSize = max(1024, receiveChunkSize)
    }

    func inboundMessages() async -> AsyncStream<CastInboundMessage> {
        let id = UUID()
        return AsyncStream { continuation in
            inboundContinuations[id] = continuation
            continuation.onTermination = { [id] _ in
                Task { await self.removeInboundContinuation(id: id) }
            }
        }
    }

    func inboundEvents() async -> AsyncStream<CastInboundTransportEvent> {
        let id = UUID()
        return AsyncStream { continuation in
            inboundEventContinuations[id] = continuation
            continuation.onTermination = { [id] _ in
                Task { await self.removeInboundEventContinuation(id: id) }
            }
        }
    }

    func connect(timeout: TimeInterval) async throws {
        if connection != nil {
            return
        }

        let endpointHost = NWEndpoint.Host(device.host)
        guard let endpointPort = NWEndpoint.Port(rawValue: UInt16(device.port)) else {
            throw CastError.invalidArgument("Invalid Cast port: \(device.port)")
        }

        let parameters = NWParameters.tls
        parameters.includePeerToPeer = false
        let connection = NWConnection(host: endpointHost, port: endpointPort, using: parameters)

        do {
            try await Self.startAndWaitUntilReady(connection, queue: callbackQueue, timeout: timeout)
            self.connection = connection
            startReadLoop(connection)
        } catch {
            connection.cancel()
            throw error is CastError ? error : CastError.connectionFailed(String(describing: error))
        }
    }

    func disconnect() async {
        readLoopTask?.cancel()
        readLoopTask = nil

        connection?.cancel()
        connection = nil
        finishInboundStreams()
    }

    func send(_ command: CastEncodedCommand) async throws {
        guard let connection else {
            throw CastError.disconnected
        }

        let frame = try CastV2FrameCodec.encodeFrame(command: command)
        try await Self.send(frame, on: connection)
    }

    private func startReadLoop(_ connection: NWConnection) {
        readLoopTask?.cancel()
        let actor = self
        readLoopTask = Task {
            await actor.runReadLoop(connection)
        }
    }

    private func runReadLoop(_ connection: NWConnection) async {
        var deframer = CastV2FrameDeframer()

        do {
            while Task.isCancelled == false {
                let chunk = try await Self.receiveChunk(from: connection, maximumLength: receiveChunkSize)

                if chunk.data.isEmpty == false {
                    let bodies = try deframer.append(chunk.data)
                    for body in bodies {
                        do {
                            let message = try CastV2ChannelMessageCodec.decodeTransportMessage(body)
                            switch message.payload {
                            case let .utf8(payloadUTF8):
                                let inbound = CastInboundMessage(route: message.route, payloadUTF8: payloadUTF8)
                                emitInbound(inbound)
                                emitInboundEvent(.utf8(inbound))
                            case let .binary(payloadBinary):
                                emitInboundEvent(.binary(.init(route: message.route, payloadBinary: payloadBinary)))
                            }
                        } catch {
                            // Ignore malformed inbound messages for now; connection remains alive.
                            continue
                        }
                    }
                }

                if chunk.isComplete {
                    emitInboundEvent(.closed)
                    finishInboundStreams()
                    break
                }
            }
        } catch is CancellationError {
            // Expected during explicit disconnect or reconnect.
        } catch {
            let castError = (error as? CastError) ?? .connectionFailed(String(describing: error))
            emitInboundEvent(.failure(castError))
            finishInboundStreams()
        }
    }

    private func emitInbound(_ message: CastInboundMessage) {
        for continuation in inboundContinuations.values {
            continuation.yield(message)
        }
    }

    private func removeInboundContinuation(id: UUID) {
        inboundContinuations[id] = nil
    }

    private func emitInboundEvent(_ event: CastInboundTransportEvent) {
        for continuation in inboundEventContinuations.values {
            continuation.yield(event)
        }
    }

    private func finishInboundStreams() {
        for continuation in inboundContinuations.values {
            continuation.finish()
        }
        inboundContinuations.removeAll(keepingCapacity: false)

        for continuation in inboundEventContinuations.values {
            continuation.finish()
        }
        inboundEventContinuations.removeAll(keepingCapacity: false)
    }

    private func removeInboundEventContinuation(id: UUID) {
        inboundEventContinuations[id] = nil
    }

    private static func startAndWaitUntilReady(
        _ connection: NWConnection,
        queue: DispatchQueue,
        timeout: TimeInterval
    ) async throws {
        let box = NWConnectionStateWaiterBox()

        try await withTaskCancellationHandler {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await withCheckedThrowingContinuation { continuation in
                        box.install(continuation)
                        connection.stateUpdateHandler = { state in
                            switch state {
                            case .ready:
                                box.resume(.success(()))
                            case let .failed(error):
                                box.resume(.failure(CastError.connectionFailed(String(describing: error))))
                            case .cancelled:
                                box.resume(.failure(CastError.disconnected))
                            case .setup, .preparing, .waiting:
                                break
                            @unknown default:
                                break
                            }
                        }
                        connection.start(queue: queue)
                    }
                }

                if timeout > 0 {
                    group.addTask {
                        let ns = UInt64(timeout * 1_000_000_000)
                        try await Task.sleep(nanoseconds: ns)
                        throw CastError.timeout(operation: "connect cast transport")
                    }
                }

                guard let result = try await group.next() else {
                    throw CastError.connectionFailed("Cast transport connect wait ended unexpectedly")
                }
                _ = result
                group.cancelAll()
            }
        } onCancel: {
            box.resume(.failure(CancellationError()))
            connection.cancel()
        }
    }

    private static func send(_ data: Data, on connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: CastError.connectionFailed(String(describing: error)))
                } else {
                    continuation.resume(returning: ())
                }
            })
        }
    }

    private static func receiveChunk(
        from connection: NWConnection,
        maximumLength: Int
    ) async throws -> (data: Data, isComplete: Bool) {
        try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: maximumLength) { data, _, isComplete, error in
                if let error {
                    continuation.resume(throwing: CastError.connectionFailed(String(describing: error)))
                    return
                }
                continuation.resume(returning: (data ?? Data(), isComplete))
            }
        }
    }
}

private final class NWConnectionStateWaiterBox: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, any Error>?
    private var completed = false

    func install(_ continuation: CheckedContinuation<Void, any Error>) {
        lock.lock()
        self.continuation = continuation
        lock.unlock()
    }

    func resume(_ result: Result<Void, any Error>) {
        lock.lock()
        guard completed == false, let continuation else {
            lock.unlock()
            return
        }
        completed = true
        self.continuation = nil
        lock.unlock()

        switch result {
        case .success:
            continuation.resume(returning: ())
        case let .failure(error):
            continuation.resume(throwing: error)
        }
    }
}
