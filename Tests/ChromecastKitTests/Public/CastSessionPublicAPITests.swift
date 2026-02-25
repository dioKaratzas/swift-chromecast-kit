//
//  ChromecastKit
//  Swift package for Google Cast (Chromecast).
//

import Testing
import Foundation
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
                    route: .init(
                        sourceID: "web-42",
                        destinationID: "sender-0",
                        namespace: "urn:x-cast:com.example.binary"
                    ),
                    payloadBinary: Data([0xDE, 0xAD])
                )
            )
        )

        let event = try #require(await iterator.next())
        #expect(event.namespace == "urn:x-cast:com.example.binary")
        #expect(event.payloadBinary == Data([0xDE, 0xAD]))

        await session.disconnect(reason: .requested)
    }

    @Test("namespaceEvents decodes binary JSON payloads when bytes are UTF-8")
    func namespaceEventsBinaryJSONDecode() async throws {
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
                    route: .init(
                        sourceID: "web-42",
                        destinationID: "sender-0",
                        namespace: "urn:x-cast:com.example.binary"
                    ),
                    payloadBinary: Data(#"{"type":"CUSTOM","value":7}"#.utf8)
                )
            )
        )

        let event = try #require(await iterator.next())
        let json = try event.jsonObject()
        #expect(json["type"] == .string("CUSTOM"))
        #expect(json["value"] == .number(7))

        await session.disconnect(reason: .requested)
    }

    @Test("namespace handler registry routes filtered custom events")
    func namespaceHandlerRegistry() async throws {
        let transport = PublicSessionTestTransport()
        let runtime = CastSessionRuntime(
            device: .init(id: "device-1", friendlyName: "Living Room", host: "192.168.1.10"),
            transport: transport,
            configuration: .init(heartbeatInterval: 0, autoReconnect: false)
        )
        let session = CastSession(runtime: runtime)
        let handler = RecordingNamespaceHandler(namespace: "urn:x-cast:com.example.echo")

        try await session.connect()
        let token = await session.registerNamespaceHandler(handler)

        await transport.emitInboundEvent(
            .utf8(
                .init(
                    route: .init(
                        sourceID: "web-42",
                        destinationID: "sender-0",
                        namespace: "urn:x-cast:com.example.echo"
                    ),
                    payloadUTF8: #"{"type":"PING"}"#
                )
            )
        )
        await transport.emitInboundEvent(
            .utf8(
                .init(
                    route: .init(
                        sourceID: "web-42",
                        destinationID: "sender-0",
                        namespace: "urn:x-cast:com.example.other"
                    ),
                    payloadUTF8: #"{"type":"IGNORE"}"#
                )
            )
        )

        let handled = try #require(await waitForHandledCount(on: handler, count: 1))
        #expect(handled == 1)
        let events = await handler.events()
        #expect(events.count == 1)
        #expect(events.first?.namespace == "urn:x-cast:com.example.echo")

        await session.unregisterNamespaceHandler(token)
        await transport.emitInboundEvent(
            .utf8(
                .init(
                    route: .init(
                        sourceID: "web-42",
                        destinationID: "sender-0",
                        namespace: "urn:x-cast:com.example.echo"
                    ),
                    payloadUTF8: #"{"type":"PING2"}"#
                )
            )
        )

        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(await handler.events().count == 1)
        await session.disconnect(reason: .requested)
    }

    @Test("connectIfNeeded avoids duplicate connect when already connected")
    func connectIfNeededIsIdempotent() async throws {
        let transport = PublicSessionTestTransport()
        let runtime = CastSessionRuntime(
            device: .init(id: "device-1", friendlyName: "Living Room", host: "192.168.1.10"),
            transport: transport,
            configuration: .init(heartbeatInterval: 0, autoReconnect: false)
        )
        let session = CastSession(runtime: runtime)

        try await session.connectIfNeeded()
        try await session.connectIfNeeded()

        #expect(await transport.connectCallCount() == 1)
        await session.disconnect(reason: .requested)
    }

    @Test("launchDefaultMediaReceiver sends receiver launch with built-in app id")
    func launchDefaultMediaReceiver() async throws {
        let transport = PublicSessionTestTransport()
        let runtime = CastSessionRuntime(
            device: .init(id: "device-1", friendlyName: "Living Room", host: "192.168.1.10"),
            transport: transport,
            configuration: .init(heartbeatInterval: 0, autoReconnect: false)
        )
        let session = CastSession(runtime: runtime)

        try await session.connect()
        _ = try await session.launchDefaultMediaReceiver()

        let launchCommand = try #require(await (transport.commands()).last)
        #expect(launchCommand.route.namespace == .receiver)
        #expect(launchCommand.route.destinationID == "receiver-0")
        let json = try JSONDecoder().decode([String: JSONValue].self, from: Data(launchCommand.payloadUTF8.utf8))
        #expect(json["type"] == .string("LAUNCH"))
        #expect(json["appId"] == .string(CastAppID.defaultMediaReceiver.rawValue))

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
        return await (transport.commands()).first(where: { $0.requestID == requestID })
    }

    private func extractRequestID(_ value: JSONValue) -> Int? {
        guard case let .number(number) = value else {
            return nil
        }
        return Int(number)
    }

    private func waitForHandledCount(
        on handler: RecordingNamespaceHandler,
        count: Int,
        timeout: TimeInterval = 0.5
    ) async -> Int? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let current = await handler.events().count
            if current >= count {
                return current
            }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        return await handler.events().count
    }
}

private actor RecordingNamespaceHandler: CastSessionNamespaceHandler {
    let namespace: CastNamespace?
    private var handledEvents = [CastSession.NamespaceEvent]()

    init(namespace: CastNamespace?) {
        self.namespace = namespace
    }

    func handle(event: CastSession.NamespaceEvent, in _: CastSession) async {
        handledEvents.append(event)
    }

    func events() -> [CastSession.NamespaceEvent] {
        handledEvents
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
