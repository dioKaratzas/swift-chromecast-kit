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
