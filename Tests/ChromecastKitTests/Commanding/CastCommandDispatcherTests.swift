//
//  ChromecastKit
//  Swift package for Google Cast (Chromecast).
//

import Testing
import Foundation
@testable import ChromecastKit

@Suite("Cast Command Dispatcher")
struct CastCommandDispatcherTests {
    @Test("injects request id and routes receiver command to platform")
    func receiverPlatformCommandRouting() async throws {
        let transport = RecordingCommandTransport()
        let dispatcher = CastCommandDispatcher(transport: transport)

        let requestID = try await dispatcher.send(
            namespace: .receiver,
            target: .platform,
            payload: CastReceiverPayloadBuilder.getStatus()
        )

        #expect(requestID == 1)
        let commands = await transport.commands()
        #expect(commands.count == 1)

        let command = try #require(commands.first)
        #expect(command.requestID == 1)
        #expect(command.route.namespace == .receiver)
        #expect(command.route.destinationID == "receiver-0")

        let json = try JSONDecoder().decode([String: JSONValue].self, from: Data(command.payloadUTF8.utf8))
        #expect(json["type"] == .string("GET_STATUS"))
        #expect(json["requestId"] == .number(1))
    }

    @Test("current application target requires transport id")
    func currentApplicationRequiresTransportID() async {
        let transport = RecordingCommandTransport()
        let dispatcher = CastCommandDispatcher(transport: transport)

        await #expect(throws: CastError.self) {
            _ = try await dispatcher.send(
                namespace: .media,
                target: .currentApplication,
                payload: CastMediaPayloadBuilder.disableTextTracks()
            )
        }

        let commands = await transport.commands()
        #expect(commands.isEmpty)
    }

    @Test("routes current application target to configured transport id")
    func currentApplicationRouting() async throws {
        let transport = RecordingCommandTransport()
        let dispatcher = CastCommandDispatcher(transport: transport)
        await dispatcher.setCurrentApplicationTransportID("web-9")

        let requestID = try await dispatcher.send(
            namespace: .media,
            target: .currentApplication,
            payload: CastMediaPayloadBuilder.enableTextTrack(trackID: 2)
        )

        #expect(requestID == 1)
        let command = try #require(await transport.commands().first)
        #expect(command.route.destinationID == "web-9")
        #expect(command.route.namespace == .media)

        let json = try JSONDecoder().decode([String: JSONValue].self, from: Data(command.payloadUTF8.utf8))
        #expect(json["type"] == .string("EDIT_TRACKS_INFO"))
        #expect(json["activeTrackIds"] == .array([.number(2)]))
        #expect(json["requestId"] == .number(1))
    }

    @Test("request ids increment across sends")
    func requestIDIncrements() async throws {
        let transport = RecordingCommandTransport()
        let dispatcher = CastCommandDispatcher(transport: transport)

        _ = try await dispatcher.send(
            namespace: .receiver,
            target: .platform,
            payload: CastReceiverPayloadBuilder.getStatus()
        )
        _ = try await dispatcher.send(
            namespace: .receiver,
            target: .platform,
            payload: CastReceiverPayloadBuilder.getStatus()
        )

        let commands = await transport.commands()
        #expect(commands.map(\.requestID) == [1, 2])
    }

    @Test("sendAndAwaitReply resumes when matching requestId inbound message is consumed")
    func sendAndAwaitReplyCorrelation() async throws {
        let transport = RecordingCommandTransport()
        let dispatcher = CastCommandDispatcher(transport: transport)

        let replyTask = Task {
            try await dispatcher.sendAndAwaitReply(
                namespace: .receiver,
                target: .platform,
                payload: CastReceiverPayloadBuilder.getStatus()
            )
        }

        // Ensure the command has been sent and requestId assigned.
        var command: CastEncodedCommand?
        for _ in 0 ..< 10 {
            command = await transport.commands().first
            if command != nil {
                break
            }
            await Task.yield()
        }
        let sent = try #require(command)
        #expect(sent.requestID == 1)

        let consumed = try await dispatcher.consumeInboundMessage(
            .init(
                route: .init(sourceID: "receiver-0", destinationID: "sender-0", namespace: .receiver),
                payloadUTF8: #"{"type":"RECEIVER_STATUS","requestId":1}"#
            )
        )

        #expect(consumed)
        let reply = try await replyTask.value
        #expect(reply.route.namespace == .receiver)
        #expect(reply.payloadUTF8 == #"{"type":"RECEIVER_STATUS","requestId":1}"#)
    }

    @Test("consumeInboundMessage ignores payloads without matching requestId")
    func consumeInboundMessageNoMatch() async throws {
        let transport = RecordingCommandTransport()
        let dispatcher = CastCommandDispatcher(transport: transport)

        let consumed = try await dispatcher.consumeInboundMessage(
            .init(
                route: .init(sourceID: "receiver-0", destinationID: "sender-0", namespace: .receiver),
                payloadUTF8: #"{"type":"RECEIVER_STATUS","requestId":999}"#
            )
        )

        #expect(!consumed)
    }

    @Test("sendAndAwaitReply times out when no reply arrives")
    func sendAndAwaitReplyTimeout() async {
        let transport = RecordingCommandTransport()
        let dispatcher = CastCommandDispatcher(transport: transport, defaultReplyTimeout: 0.01)

        await #expect(throws: CastError.self) {
            _ = try await dispatcher.sendAndAwaitReply(
                namespace: .receiver,
                target: .platform,
                payload: CastReceiverPayloadBuilder.getStatus()
            )
        }
    }

    @Test("sendAndAwaitReply cancellation removes pending waiter")
    func sendAndAwaitReplyCancellation() async throws {
        let transport = RecordingCommandTransport()
        let dispatcher = CastCommandDispatcher(transport: transport, defaultReplyTimeout: 5)

        let replyTask = Task {
            try await dispatcher.sendAndAwaitReply(
                namespace: .receiver,
                target: .platform,
                payload: CastReceiverPayloadBuilder.getStatus()
            )
        }

        for _ in 0 ..< 10 {
            if await transport.commands().isEmpty == false {
                break
            }
            await Task.yield()
        }

        replyTask.cancel()

        await #expect(throws: CancellationError.self) {
            _ = try await replyTask.value
        }

        let consumed = try await dispatcher.consumeInboundMessage(
            .init(
                route: .init(sourceID: "receiver-0", destinationID: "sender-0", namespace: .receiver),
                payloadUTF8: #"{"type":"RECEIVER_STATUS","requestId":1}"#
            )
        )

        #expect(!consumed)
    }
}

private actor RecordingCommandTransport: CastCommandTransport {
    private var sentCommands = [CastEncodedCommand]()

    func send(_ command: CastEncodedCommand) async throws {
        sentCommands.append(command)
    }

    func commands() -> [CastEncodedCommand] {
        sentCommands
    }
}
