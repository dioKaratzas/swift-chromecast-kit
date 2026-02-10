//
//  ChromecastKit
//  Swift package for Google Cast (Chromecast).
//

import Foundation
import Testing
@testable import ChromecastKit

@Suite("Cast Session Public API", .serialized)
struct CastSessionPublicAPITests {
    @Test("sendAndAwaitReply returns typed namespace message")
    func sendAndAwaitReply() async throws {
        let transport = PublicSessionTestTransport()
        let runtime = CastSessionRuntime(
            device: .init(id: "device-1", friendlyName: "Living Room", host: "192.168.1.10"),
            transport: transport,
            configuration: .init(heartbeatInterval: 0, autoReconnect: false)
        )
        let session = CastSession(runtime: runtime)

        try await session.connect()

        let replyTask = Task {
            try await session.sendAndAwaitReply(
                namespace: .receiver,
                target: .platform,
                payload: ["type": .string("GET_STATUS")]
            )
        }

        let sent = try #require(await waitForCommand(on: transport, requestID: 2))
        let sentJSON = try JSONDecoder().decode([String: JSONValue].self, from: Data(sent.payloadUTF8.utf8))
        #expect(sent.route.namespace == .receiver)

        // Skip initial bootstrap commands and respond to the GET_STATUS from sendAndAwaitReply.
        let requestID = try #require(sentJSON["requestId"].flatMap(extractRequestID))
        await transport.emitInboundEvent(
            .utf8(
                .init(
                    route: .init(sourceID: "receiver-0", destinationID: "sender-0", namespace: .receiver),
                    payloadUTF8: #"{"type":"RECEIVER_STATUS","requestId":\#(requestID),"status":{"volume":{"level":0.5,"muted":false}}}"#
                )
            )
        )

        let reply = try await replyTask.value
        #expect(reply.namespace == .receiver)
        #expect(try reply.jsonObject()["requestId"] == .number(Double(requestID)))

        await session.disconnect(reason: .requested)
    }

    @Test("namespaceEvents emits binary custom namespace payloads")
    func namespaceEventsBinary() async throws {
        let transport = PublicSessionTestTransport()
        let runtime = CastSessionRuntime(
            device: .init(id: "device-1", friendlyName: "Living Room", host: "192.168.1.10"),
            transport: transport,
            configuration: .init(heartbeatInterval: 0, autoReconnect: false)
        )
        let session = CastSession(runtime: runtime)

        try await session.connect()
        var iterator = await session.namespaceEvents("urn:x-cast:com.example.binary").makeAsyncIterator()

        await transport.emitInboundEvent(
            .binary(
                .init(
                    route: .init(sourceID: "web-42", destinationID: "sender-0", namespace: "urn:x-cast:com.example.binary"),
                    payloadBinary: Data([0xDE, 0xAD])
                )
            )
        )

        let event = try #require(await iterator.next())
        #expect(event.namespace == "urn:x-cast:com.example.binary")
        #expect(event.payloadBinary == Data([0xDE, 0xAD]))

        await session.disconnect(reason: .requested)
    }

    private func waitForCommand(
        on transport: PublicSessionTestTransport,
        requestID: CastRequestID,
        timeout: TimeInterval = 0.5
    ) async -> CastEncodedCommand? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let commands = await transport.commands()
            if let command = commands.first(where: { $0.requestID == requestID }) {
                return command
            }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        return (await transport.commands()).first(where: { $0.requestID == requestID })
    }

    private func extractRequestID(_ value: JSONValue) -> Int? {
        guard case let .number(number) = value else { return nil }
        return Int(number)
    }
}

private actor PublicSessionTestTransport: CastConnectionTransport, CastCommandTransport, CastInboundEventTransport {
    private var connectCount = 0
    private var disconnectCount = 0
    private var sentCommands = [CastEncodedCommand]()
    private var inboundEventContinuations = [UUID: AsyncStream<CastInboundTransportEvent>.Continuation]()

    func connect(timeout _: TimeInterval) async throws {
        connectCount += 1
    }

    func disconnect() async {
        disconnectCount += 1
        for continuation in inboundEventContinuations.values {
            continuation.finish()
        }
        inboundEventContinuations.removeAll(keepingCapacity: false)
    }

    func send(_ command: CastEncodedCommand) async throws {
        sentCommands.append(command)
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

    private func removeInboundEventContinuation(id: UUID) {
        inboundEventContinuations[id] = nil
    }
}
