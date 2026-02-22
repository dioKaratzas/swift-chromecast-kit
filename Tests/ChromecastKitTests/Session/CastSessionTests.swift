//
//  ChromecastKit
//  Swift package for Google Cast (Chromecast).
//

import Testing
import Foundation
@testable import ChromecastKit

@Suite("Cast Session Runtime", .serialized)
struct CastSessionTests {
    @Test("connect and disconnect proxy connection lifecycle and events")
    func lifecycle() async throws {
        let transport = TestSessionTransport()
        let device = CastDeviceDescriptor(
            id: "device-1",
            friendlyName: "Living Room",
            host: "192.168.1.10",
            port: 8009
        )
        let session = CastSessionRuntime(device: device, transport: transport)
        var events = await session.connectionEvents().makeAsyncIterator()

        try await session.connect()
        #expect(await session.connectionState() == .connected)
        #expect(try await nextConnectionEvent(&events) == .connected)

        await session.disconnect(reason: .requested)
        #expect(await session.connectionState() == .disconnected)
        #expect(try await nextConnectionEvent(&events) == .disconnected(reason: .requested))

        let lifecycle = await transport.lifecycle()
        #expect(lifecycle.connects == 1)
        #expect(lifecycle.disconnects == 1)
    }

    @Test("connect bootstraps platform connection and receiver status")
    func connectBootstrapsPlatformNamespaces() async throws {
        let transport = TestSessionTransport()
        let device = CastDeviceDescriptor(
            id: "device-1",
            friendlyName: "Living Room",
            host: "192.168.1.10",
            port: 8009
        )
        let session = CastSessionRuntime(
            device: device,
            transport: transport,
            configuration: .init(heartbeatInterval: 0)
        )

        try await session.connect()

        let commands = await transport.commands()
        #expect(commands.count == 2)

        let connect = try #require(commands.first)
        let connectJSON = try JSONDecoder().decode([String: JSONValue].self, from: Data(connect.payloadUTF8.utf8))
        #expect(connect.route.namespace == .connection)
        #expect(connect.route.destinationID == "receiver-0")
        #expect(connectJSON["type"] == .string("CONNECT"))
        #expect(connectJSON["requestId"] == nil)

        let getStatus = try #require(commands.last)
        let getStatusJSON = try JSONDecoder().decode([String: JSONValue].self, from: Data(getStatus.payloadUTF8.utf8))
        #expect(getStatus.route.namespace == .receiver)
        #expect(getStatusJSON["type"] == .string("GET_STATUS"))
        #expect(getStatusJSON["requestId"] == .number(1))

        await session.disconnect(reason: .requested)
    }

    @Test("inbound statuses update snapshot and enable media session-bound commands")
    func statusProcessingAndCommands() async throws {
        let transport = TestSessionTransport()
        let device = CastDeviceDescriptor(
            id: "device-1",
            friendlyName: "Living Room",
            host: "192.168.1.10",
            port: 8009
        )
        let session = CastSessionRuntime(device: device, transport: transport)

        let receiverMessage = CastInboundMessage(
            route: .init(sourceID: "receiver-0", destinationID: "sender-0", namespace: .receiver),
            payloadUTF8: #"""
            {"type":"RECEIVER_STATUS","status":{"volume":{"level":0.5,"muted":false},"applications":[{"appId":"CC1AD845","displayName":"Default Media Receiver","sessionId":"SESSION-1","transportId":"web-42","statusText":"Ready","namespaces":[{"name":"urn:x-cast:com.google.cast.media"}]}],"isStandBy":false,"isActiveInput":true}}
            """#
        )
        let mediaMessage = CastInboundMessage(
            route: .init(sourceID: "web-42", destinationID: "sender-0", namespace: .media),
            payloadUTF8: #"""
            {"type":"MEDIA_STATUS","status":[{"mediaSessionId":55,"playerState":"PLAYING","currentTime":12,"playbackRate":1,"supportedMediaCommands":4098,"volume":{"level":0.7,"muted":false},"activeTrackIds":[3],"media":{"contentId":"https://example.com/movie.mp4","contentType":"video/mp4","streamType":"BUFFERED","duration":120,"metadata":{"metadataType":0,"title":"Movie"}}}]}
            """#
        )

        #expect(try await session.applyInboundMessage(receiverMessage))
        #expect(try await session.applyInboundMessage(mediaMessage))

        let snapshot = await session.snapshot()
        #expect(snapshot.receiverStatus?.app?.transportID == "web-42")
        #expect(snapshot.mediaStatus?.mediaSessionID == 55)
        #expect(snapshot.mediaStatus?.playerState == .playing)

        _ = try await session.media.play()

        let command = try #require(await transport.commands().last)
        let json = try JSONDecoder().decode([String: JSONValue].self, from: Data(command.payloadUTF8.utf8))
        #expect(command.route.namespace == .media)
        #expect(command.route.destinationID == "web-42")
        #expect(json["type"] == .string("PLAY"))
        #expect(json["mediaSessionId"] == .number(55))
    }

    @Test("receiver status bootstraps active app transport connection and media status request")
    func receiverStatusBootstrapsAppTransport() async throws {
        let transport = TestSessionTransport()
        let device = CastDeviceDescriptor(
            id: "device-1",
            friendlyName: "Living Room",
            host: "192.168.1.10",
            port: 8009
        )
        let session = CastSessionRuntime(
            device: device,
            transport: transport,
            configuration: .init(heartbeatInterval: 0)
        )

        let receiverMessage = CastInboundMessage(
            route: .init(sourceID: "receiver-0", destinationID: "sender-0", namespace: .receiver),
            payloadUTF8: #"""
            {"type":"RECEIVER_STATUS","status":{"volume":{"level":0.5,"muted":false},"applications":[{"appId":"CC1AD845","displayName":"Default Media Receiver","sessionId":"SESSION-1","transportId":"web-42","statusText":"Ready","namespaces":[{"name":"urn:x-cast:com.google.cast.media"}]}]}}
            """#
        )

        #expect(try await session.applyInboundMessage(receiverMessage))

        let commands = await transport.commands()
        #expect(commands.count == 2)

        let appConnect = try #require(commands.first)
        let appConnectJSON = try JSONDecoder().decode([String: JSONValue].self, from: Data(appConnect.payloadUTF8.utf8))
        #expect(appConnect.route.namespace == .connection)
        #expect(appConnect.route.destinationID == "web-42")
        #expect(appConnectJSON["type"] == .string("CONNECT"))
        #expect(appConnectJSON["requestId"] == nil)

        let mediaGetStatus = try #require(commands.last)
        let mediaGetStatusJSON = try JSONDecoder().decode(
            [String: JSONValue].self,
            from: Data(mediaGetStatus.payloadUTF8.utf8)
        )
        #expect(mediaGetStatus.route.namespace == .media)
        #expect(mediaGetStatus.route.destinationID == "web-42")
        #expect(mediaGetStatusJSON["type"] == .string("GET_STATUS"))
        #expect(mediaGetStatusJSON["requestId"] == .number(1))
    }

    @Test("receiver status app bootstrap failure emits error and disconnects")
    func receiverStatusAppBootstrapFailureTriggersRecovery() async throws {
        let transport = TestSessionTransport()
        let device = CastDeviceDescriptor(
            id: "device-1",
            friendlyName: "Living Room",
            host: "192.168.1.10",
            port: 8009
        )
        let session = CastSessionRuntime(
            device: device,
            transport: transport,
            configuration: .init(heartbeatInterval: 0, autoReconnect: false)
        )
        var events = await session.connectionEvents().makeAsyncIterator()

        try await session.connect()
        _ = try await nextConnectionEvent(&events) // connected

        await transport.failNextSend(matching: .media, with: .connectionFailed("media bootstrap failed"))
        let handled = try await session.applyInboundMessage(
            .init(
                route: .init(sourceID: "receiver-0", destinationID: "sender-0", namespace: .receiver),
                payloadUTF8: #"""
                {"type":"RECEIVER_STATUS","status":{"volume":{"level":0.5,"muted":false},"applications":[{"appId":"CC1AD845","displayName":"Default Media Receiver","sessionId":"SESSION-1","transportId":"web-42","statusText":"Ready","namespaces":[{"name":"urn:x-cast:com.google.cast.media"}]}]}}
                """#
            )
        )

        #expect(handled)
        let errorEvent = try await nextConnectionEvent(&events)
        let disconnectedEvent = try await nextConnectionEvent(&events)
        guard case let .error(error) = errorEvent else {
            Issue.record("Expected error event")
            return
        }
        #expect(error == .connectionFailed("media bootstrap failed"))
        #expect(disconnectedEvent == .disconnected(reason: .networkError))
        #expect(await session.connectionState() == .disconnected)
    }

    @Test("heartbeat ping messages are answered with pong")
    func heartbeatPingRespondsWithPong() async throws {
        let transport = TestSessionTransport()
        let device = CastDeviceDescriptor(
            id: "device-1",
            friendlyName: "Living Room",
            host: "192.168.1.10",
            port: 8009
        )
        let session = CastSessionRuntime(
            device: device,
            transport: transport,
            configuration: .init(heartbeatInterval: 0)
        )

        let handled = try await session.applyInboundMessage(
            .init(
                route: .init(sourceID: "receiver-0", destinationID: "sender-0", namespace: .heartbeat),
                payloadUTF8: #"{"type":"PING"}"#
            )
        )

        #expect(handled)
        let command = try #require(await transport.commands().first)
        let json = try JSONDecoder().decode([String: JSONValue].self, from: Data(command.payloadUTF8.utf8))
        #expect(command.route.namespace == .heartbeat)
        #expect(command.route.destinationID == "receiver-0")
        #expect(json["type"] == .string("PONG"))
        #expect(json["requestId"] == nil)
    }

    @Test("heartbeat timeout disconnects when auto reconnect is disabled")
    func heartbeatTimeoutDisconnectsWithoutReconnect() async throws {
        let transport = TestSessionTransport()
        let device = CastDeviceDescriptor(
            id: "device-1",
            friendlyName: "Living Room",
            host: "192.168.1.10",
            port: 8009
        )
        let session = CastSessionRuntime(
            device: device,
            transport: transport,
            configuration: .init(heartbeatInterval: 0.01, autoReconnect: false)
        )

        try await session.connect()
        try await Task.sleep(nanoseconds: 450_000_000)

        #expect(await session.connectionState() == .disconnected)
        let lifecycle = await transport.lifecycle()
        #expect(lifecycle.connects == 1)
        #expect(lifecycle.disconnects >= 1)
    }

    @Test("bootstrap command failure disconnects and emits error")
    func bootstrapFailureDisconnectsSession() async throws {
        let transport = TestSessionTransport()
        await transport.failNextSend(
            matching: .receiver,
            with: .connectionFailed("bootstrap get status failed")
        )
        let device = CastDeviceDescriptor(
            id: "device-1",
            friendlyName: "Living Room",
            host: "192.168.1.10",
            port: 8009
        )
        let session = CastSessionRuntime(
            device: device,
            transport: transport,
            configuration: .init(heartbeatInterval: 0, autoReconnect: false)
        )
        var events = await session.connectionEvents().makeAsyncIterator()

        await #expect(throws: CastError.self) {
            try await session.connect()
        }

        _ = try await nextConnectionEvent(&events) // connected
        let errorEvent = try await nextConnectionEvent(&events)
        let disconnectedEvent = try await nextConnectionEvent(&events)

        guard case let .error(error) = errorEvent else {
            Issue.record("Expected error event")
            return
        }
        #expect(error == .connectionFailed("bootstrap get status failed"))
        #expect(disconnectedEvent == .disconnected(reason: .networkError))
        #expect(await session.connectionState() == .disconnected)
    }

    @Test("heartbeat send failure triggers network recovery when auto reconnect is disabled")
    func heartbeatSendFailureTriggersRecovery() async throws {
        let transport = TestSessionTransport()
        let device = CastDeviceDescriptor(
            id: "device-1",
            friendlyName: "Living Room",
            host: "192.168.1.10",
            port: 8009
        )
        let session = CastSessionRuntime(
            device: device,
            transport: transport,
            configuration: .init(heartbeatInterval: 0.01, autoReconnect: false)
        )
        var events = await session.connectionEvents().makeAsyncIterator()

        try await session.connect()
        _ = try await nextConnectionEvent(&events) // connected

        await transport.failNextSend(matching: .heartbeat, with: .connectionFailed("heartbeat send failed"))
        try await Task.sleep(nanoseconds: 150_000_000)

        let errorEvent = try await nextConnectionEvent(&events)
        let disconnectedEvent = try await nextConnectionEvent(&events)

        guard case let .error(error) = errorEvent else {
            Issue.record("Expected error event")
            return
        }
        #expect(error == .connectionFailed("heartbeat send failed"))
        #expect(disconnectedEvent == .disconnected(reason: .networkError))
        #expect(await session.connectionState() == .disconnected)
    }

    @Test("custom namespace messages are emitted to namespace subscribers")
    func customNamespaceMessagesStream() async throws {
        let transport = TestSessionTransport()
        let device = CastDeviceDescriptor(
            id: "device-1",
            friendlyName: "Living Room",
            host: "192.168.1.10",
            port: 8009
        )
        let session = CastSessionRuntime(
            device: device,
            transport: transport,
            configuration: .init(heartbeatInterval: 0)
        )
        var iterator = await session
            .namespaceMessages(namespace: CastNamespace("urn:x-cast:com.example.custom"))
            .makeAsyncIterator()

        let inbound = CastInboundMessage(
            route: .init(
                sourceID: "web-42",
                destinationID: "sender-0",
                namespace: "urn:x-cast:com.example.custom"
            ),
            payloadUTF8: #"{"type":"CUSTOM","value":1}"#
        )

        #expect(try await !(session.applyInboundMessage(inbound)))
        let streamed = try #require(await iterator.next())
        #expect(streamed == inbound)
    }

    @Test("custom binary namespace messages are emitted to namespace event subscribers")
    func customBinaryNamespaceEventsStream() async throws {
        let transport = TestSessionTransport()
        let device = CastDeviceDescriptor(
            id: "device-1",
            friendlyName: "Living Room",
            host: "192.168.1.10",
            port: 8009
        )
        let session = CastSessionRuntime(
            device: device,
            transport: transport,
            configuration: .init(heartbeatInterval: 0)
        )
        try await session.connect()
        var iterator = await session
            .namespaceEvents(namespace: CastNamespace("urn:x-cast:com.example.binary"))
            .makeAsyncIterator()

        await transport.emitInboundEvent(
            .binary(
                .init(
                    route: .init(
                        sourceID: "web-42",
                        destinationID: "sender-0",
                        namespace: "urn:x-cast:com.example.binary"
                    ),
                    payloadBinary: Data([0x01, 0x02, 0x03])
                )
            )
        )

        let streamed = try #require(await iterator.next())
        guard case let .binary(message) = streamed else {
            Issue.record("Expected binary namespace event")
            return
        }
        #expect(message.payloadBinary == Data([0x01, 0x02, 0x03]))

        await session.disconnect(reason: .requested)
    }

    @Test("transport closed event disconnects and auto reconnects when enabled")
    func transportClosedAutoReconnects() async throws {
        let transport = TestSessionTransport()
        let device = CastDeviceDescriptor(
            id: "device-1",
            friendlyName: "Living Room",
            host: "192.168.1.10",
            port: 8009
        )
        let session = CastSessionRuntime(
            device: device,
            transport: transport,
            configuration: .init(heartbeatInterval: 0, autoReconnect: true)
        )
        var events = await session.connectionEvents().makeAsyncIterator()

        try await session.connect()
        _ = try await nextConnectionEvent(&events) // .connected
        await transport.emitInboundEvent(.closed)

        let first = try await nextConnectionEvent(&events)
        let second = try await nextConnectionEvent(&events)
        #expect(first == .disconnected(reason: .remoteClosed))
        #expect(second == .connected)

        let lifecycle = await transport.lifecycle()
        #expect(lifecycle.connects >= 2)
        #expect(lifecycle.disconnects >= 1)

        await session.disconnect(reason: .requested)
    }

    @Test("auto reconnect retries after transient reconnect connect failure")
    func autoReconnectRetriesAfterConnectFailure() async throws {
        let transport = TestSessionTransport()
        let device = CastDeviceDescriptor(
            id: "device-1",
            friendlyName: "Living Room",
            host: "192.168.1.10",
            port: 8009
        )
        let session = CastSessionRuntime(
            device: device,
            transport: transport,
            configuration: .init(heartbeatInterval: 0, autoReconnect: true, reconnectRetryDelay: 0.01)
        )
        var events = await session.connectionEvents().makeAsyncIterator()

        try await session.connect()
        _ = try await nextConnectionEvent(&events) // connected

        await transport.failNextConnect(with: .connectionFailed("transient reconnect failure"))
        await transport.emitInboundEvent(.closed)

        let first = try await nextConnectionEvent(&events)
        let second = try await nextConnectionEvent(&events)
        let third = try await nextConnectionEvent(&events)

        #expect(first == .disconnected(reason: .remoteClosed))
        guard case let .error(error) = second else {
            Issue.record("Expected reconnect error event")
            return
        }
        #expect(error == .connectionFailed("transient reconnect failure"))
        #expect(third == .connected)

        let lifecycle = await transport.lifecycle()
        #expect(lifecycle.connects >= 3) // initial + failed retry + successful retry

        await session.disconnect(reason: .requested)
    }

    @Test("transport failure emits connection error and disconnect when auto reconnect is disabled")
    func transportFailureEmitsErrorAndDisconnects() async throws {
        let transport = TestSessionTransport()
        let device = CastDeviceDescriptor(
            id: "device-1",
            friendlyName: "Living Room",
            host: "192.168.1.10",
            port: 8009
        )
        let session = CastSessionRuntime(
            device: device,
            transport: transport,
            configuration: .init(heartbeatInterval: 0, autoReconnect: false)
        )
        var events = await session.connectionEvents().makeAsyncIterator()

        try await session.connect()
        _ = try await nextConnectionEvent(&events) // connected

        await transport.emitInboundEvent(.failure(.connectionFailed("socket error")))

        let errorEvent = try await nextConnectionEvent(&events)
        let disconnectedEvent = try await nextConnectionEvent(&events)

        guard case let .error(error) = errorEvent else {
            Issue.record("Expected error event")
            return
        }
        #expect(error == .connectionFailed("socket error"))
        #expect(disconnectedEvent == .disconnected(reason: .networkError))
        #expect(await session.connectionState() == .disconnected)
    }

    private func nextConnectionEvent(
        _ iterator: inout AsyncStream<CastConnection.Event>.AsyncIterator
    ) async throws -> CastConnection.Event {
        guard let event = await iterator.next() else {
            throw CastError.invalidResponse("Missing connection event")
        }
        return event
    }
}

private actor TestSessionTransport: CastConnectionTransport, CastCommandTransport, CastInboundEventTransport {
    private(set) var connectCount = 0
    private(set) var disconnectCount = 0
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
