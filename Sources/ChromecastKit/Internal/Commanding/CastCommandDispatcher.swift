//
//  ChromecastKit
//  Swift package for Google Cast (Chromecast).
//

import Foundation

struct CastEncodedCommand: Sendable, Hashable {
    let requestID: CastRequestID
    let route: CastMessageRoute
    let payloadUTF8: String
}

protocol CastCommandTransport: Sendable {
    func send(_ command: CastEncodedCommand) async throws
}

/// One-shot request/reply waiter stored by request ID.
///
/// The dispatcher actor owns lifecycle and ensures each continuation is resumed exactly once.
private struct PendingReply {
    let requestID: CastRequestID
    let operation: String
    let continuation: CheckedContinuation<CastInboundMessage, any Error>
    var timeoutTask: Task<Void, Never>?
}

/// Actor responsible for route resolution, request ID assignment, and payload encoding.
///
/// This layer sits between high-level controllers and the eventual socket/protobuf transport.
/// It keeps transport concerns out of controller APIs while preserving typed payload models.
actor CastCommandDispatcher {
    private let transport: any CastCommandTransport
    private let defaultReplyTimeout: TimeInterval
    private var requestIDs = CastRequestIDGenerator()
    private var sourceID: CastEndpointID
    private var currentApplicationTransportID: CastTransportID?
    private var pendingReplies = [CastRequestID: PendingReply]()

    init(
        transport: any CastCommandTransport,
        sourceID: CastEndpointID = "sender-0",
        defaultReplyTimeout: TimeInterval = 10
    ) {
        self.transport = transport
        self.sourceID = sourceID
        self.defaultReplyTimeout = defaultReplyTimeout
    }

    func setSourceID(_ sourceID: CastEndpointID) {
        self.sourceID = sourceID
    }

    func setCurrentApplicationTransportID(_ transportID: CastTransportID?) {
        currentApplicationTransportID = transportID
    }

    @discardableResult
    func send<Payload: Encodable & Sendable>(
        namespace: CastNamespace,
        target: CastMessageTarget,
        payload: Payload
    ) async throws -> CastRequestID {
        let command = try makeEncodedCommand(namespace: namespace, target: target, payload: payload)
        try await transport.send(command)
        return command.requestID
    }

    /// Sends a command without injecting `requestId`.
    ///
    /// Used for Cast transport-control namespaces such as connection and heartbeat.
    func sendUntracked<Payload: Encodable & Sendable>(
        namespace: CastNamespace,
        target: CastMessageTarget,
        payload: Payload
    ) async throws {
        let command = try makeEncodedCommand(
            namespace: namespace,
            target: target,
            payload: payload,
            includeRequestID: false
        )
        try await transport.send(command)
    }

    /// Sends a command and suspends until an inbound message with the same `requestId` arrives.
    ///
    /// This powers request/response correlation independently from message-type-specific parsing.
    func sendAndAwaitReply<Payload: Encodable & Sendable>(
        namespace: CastNamespace,
        target: CastMessageTarget,
        payload: Payload,
        timeout: TimeInterval? = nil
    ) async throws -> CastInboundMessage {
        let command = try makeEncodedCommand(namespace: namespace, target: target, payload: payload)
        let transport = self.transport
        let replyTimeout = timeout ?? defaultReplyTimeout
        let operation = "cast request reply"

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                registerPendingReply(
                    .init(
                        requestID: command.requestID,
                        operation: operation,
                        continuation: continuation,
                        timeoutTask: nil
                    ),
                    timeout: replyTimeout
                )

                Task {
                    do {
                        try await transport.send(command)
                    } catch {
                        self.failPendingReply(
                            requestID: command.requestID,
                            error: error is CastError ? error : CastError.connectionFailed(String(describing: error))
                        )
                    }
                }
            }
        } onCancel: {
            Task {
                await self.cancelPendingReply(requestID: command.requestID)
            }
        }
    }

    /// Attempts to resolve a pending request/reply waiter from an inbound message.
    ///
    /// Returns `true` when the message matched a pending request and resumed its waiter.
    @discardableResult
    func consumeInboundMessage(_ message: CastInboundMessage) throws -> Bool {
        guard let requestID = try extractRequestID(from: message.payloadUTF8),
              let pendingReply = pendingReplies.removeValue(forKey: requestID) else {
            return false
        }

        pendingReply.timeoutTask?.cancel()
        pendingReply.continuation.resume(returning: message)
        return true
    }

    private func registerPendingReply(_ pendingReply: PendingReply, timeout: TimeInterval) {
        pendingReplies[pendingReply.requestID] = pendingReply

        guard timeout > 0 else {
            return
        }

        let timeoutTask = Task { [requestID = pendingReply.requestID] in
            let ns = UInt64(max(0, timeout) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: ns)
            guard !Task.isCancelled else {
                return
            }
            self.timeoutPendingReply(requestID: requestID)
        }

        pendingReplies[pendingReply.requestID]?.timeoutTask = timeoutTask
    }

    private func timeoutPendingReply(requestID: CastRequestID) {
        guard let pendingReply = pendingReplies.removeValue(forKey: requestID) else {
            return
        }
        pendingReply.timeoutTask?.cancel()
        pendingReply.continuation.resume(throwing: CastError.timeout(operation: pendingReply.operation))
    }

    private func cancelPendingReply(requestID: CastRequestID) {
        guard let pendingReply = pendingReplies.removeValue(forKey: requestID) else {
            return
        }
        pendingReply.timeoutTask?.cancel()
        pendingReply.continuation.resume(throwing: CancellationError())
    }

    private func failPendingReply(requestID: CastRequestID, error: any Error) {
        guard let pendingReply = pendingReplies.removeValue(forKey: requestID) else {
            return
        }
        pendingReply.timeoutTask?.cancel()
        pendingReply.continuation.resume(throwing: error)
    }

    private func makeEncodedCommand<Payload: Encodable & Sendable>(
        namespace: CastNamespace,
        target: CastMessageTarget,
        payload: Payload,
        includeRequestID: Bool = true
    ) throws -> CastEncodedCommand {
        let route = try resolveRoute(namespace: namespace, target: target)
        let requestID: CastRequestID = includeRequestID ? requestIDs.next() : 0
        let payloadUTF8 = try encodePayloadUTF8(
            payload,
            requestID: requestID,
            route: route,
            includeRequestID: includeRequestID
        )
        return .init(requestID: requestID, route: route, payloadUTF8: payloadUTF8)
    }

    private func resolveRoute(
        namespace: CastNamespace,
        target: CastMessageTarget
    ) throws -> CastMessageRoute {
        let destinationID: CastEndpointID

        switch target {
        case .platform:
            destinationID = "receiver-0"
        case let .transport(id):
            destinationID = .init(id.rawValue)
        case .currentApplication:
            guard let currentApplicationTransportID else {
                throw CastError.noActiveMediaSession
            }
            destinationID = .init(currentApplicationTransportID.rawValue)
        }

        return CastMessageRoute(
            sourceID: sourceID,
            destinationID: destinationID,
            namespace: namespace
        )
    }

    private func encodePayloadUTF8<Payload: Encodable & Sendable>(
        _ payload: Payload,
        requestID: CastRequestID,
        route: CastMessageRoute,
        includeRequestID: Bool
    ) throws -> String {
        let outbound = CastOutboundMessage(route: route, payload: payload)
        let encoded = try CastMessageJSONCodec.encodePayload(outbound)
        guard includeRequestID else {
            return encoded
        }

        var object = try CastMessageJSONCodec.decodePayload([String: JSONValue].self, from: encoded)
        object["requestId"] = .number(Double(requestID.rawValue))
        return try encodeJSONObject(object)
    }

    private func encodeJSONObject(_ object: [String: JSONValue]) throws -> String {
        let data = try JSONEncoder().encode(object)
        guard let string = String(data: data, encoding: .utf8) else {
            throw CastError.invalidResponse("Failed to encode JSON object payload")
        }
        return string
    }

    private func extractRequestID(from payloadUTF8: String) throws -> CastRequestID? {
        let object = try CastMessageJSONCodec.decodePayload([String: JSONValue].self, from: payloadUTF8)
        guard let value = object["requestId"] else {
            return nil
        }

        switch value {
        case let .number(number):
            return .init(Int(number))
        case let .string(string):
            guard let int = Int(string) else {
                return nil
            }
            return .init(int)
        default:
            return nil
        }
    }
}
