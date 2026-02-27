//
//  ChromecastKit
//  SPDX-License-Identifier: Apache-2.0
//  Copyright 2026 Dionysis Karatzas
//

import Foundation
@testable import ChromecastKit

actor CastSessionTestTransport: CastConnectionTransport, CastCommandTransport, CastInboundEventTransport {
    private var connectCount = 0
    private var disconnectCount = 0
    private var sentCommands = [CastEncodedCommand]()
    private var inboundEventContinuations = [UUID: AsyncStream<CastInboundTransportEvent>.Continuation]()
    private var nextSendFailures = [CastNamespace: CastError]()
    private var nextConnectFailures = [CastError]()

    func connect(timeout _: TimeInterval) async throws {
        connectCount += 1
        if nextConnectFailures.isEmpty == false {
            throw nextConnectFailures.removeFirst()
        }
    }

    func disconnect() async {
        disconnectCount += 1
        for continuation in inboundEventContinuations.values {
            continuation.finish()
        }
        inboundEventContinuations.removeAll(keepingCapacity: false)
    }

    func send(_ command: CastEncodedCommand) async throws {
        if let error = nextSendFailures.removeValue(forKey: command.route.namespace) {
            throw error
        }
        sentCommands.append(command)
        try autoReplyBootstrapReceiverStatusIfNeeded(for: command)
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

    func emitInboundEvent(_ event: CastInboundTransportEvent) {
        for continuation in inboundEventContinuations.values {
            continuation.yield(event)
        }
    }

    func commands() -> [CastEncodedCommand] {
        sentCommands
    }

    func connectCallCount() -> Int {
        connectCount
    }

    func lifecycle() -> (connects: Int, disconnects: Int) {
        (connectCount, disconnectCount)
    }

    func failNextSend(matching namespace: CastNamespace, with error: CastError) {
        nextSendFailures[namespace] = error
    }

    func failNextConnect(with error: CastError) {
        nextConnectFailures.append(error)
    }

    private func removeInboundEventContinuation(id: UUID) {
        inboundEventContinuations[id] = nil
    }

    private func autoReplyBootstrapReceiverStatusIfNeeded(for command: CastEncodedCommand) throws {
        guard command.route.namespace == .receiver else {
            return
        }
        guard case let .utf8(payloadUTF8) = command.payload else {
            return
        }

        let json = try JSONDecoder().decode([String: JSONValue].self, from: Data(payloadUTF8.utf8))
        guard json["type"] == .string("GET_STATUS") else {
            return
        }
        guard case let .number(requestID)? = json["requestId"] else {
            return
        }

        let reply = CastInboundTransportEvent.utf8(
            .init(
                route: .init(sourceID: "receiver-0", destinationID: "sender-0", namespace: .receiver),
                payloadUTF8: #"{"type":"RECEIVER_STATUS","requestId":\#(Int(requestID)),"status":{"volume":{"level":0.5,"muted":false}}}"#
            )
        )
        for continuation in inboundEventContinuations.values {
            continuation.yield(reply)
        }
    }
}
