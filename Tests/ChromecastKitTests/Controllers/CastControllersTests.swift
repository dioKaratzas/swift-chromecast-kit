//
//  ChromecastKit
//  Swift package for Google Cast (Chromecast).
//

import Foundation
import Testing
@testable import ChromecastKit

@Suite("Cast Controllers")
struct CastControllersTests {
    @Test("receiver controller sends typed receiver commands through dispatcher")
    func receiverControllerCommands() async throws {
        let transport = RecordingCommandTransport()
        let dispatcher = CastCommandDispatcher(transport: transport)
        let receiver = CastReceiverController(dispatcher: dispatcher)

        let req1 = try await receiver.setVolume(level: 0.4)
        let req2 = try await receiver.launch(appID: "CC1AD845")

        #expect(req1 == 1)
        #expect(req2 == 2)

        let commands = await transport.commands()
        #expect(commands.count == 2)

        let firstJSON = try decodeJSON(commands[0].payloadUTF8)
        let secondJSON = try decodeJSON(commands[1].payloadUTF8)

        #expect(commands[0].route.namespace == .receiver)
        #expect(firstJSON["type"] == .string("SET_VOLUME"))
        #expect(secondJSON["type"] == .string("LAUNCH"))
        #expect(secondJSON["appId"] == .string("CC1AD845"))
    }

    @Test("media controller sends load and subtitle commands to current app transport")
    func mediaControllerCommands() async throws {
        let transport = RecordingCommandTransport()
        let dispatcher = CastCommandDispatcher(transport: transport)
        await dispatcher.setCurrentApplicationTransportID("web-42")
        let mediaController = CastMediaController(dispatcher: dispatcher)

        let mediaURL = try #require(URL(string: "https://example.com/movie.mp4"))
        let subtitleURL = try #require(URL(string: "https://example.com/en.vtt"))
        let item = CastMediaItem(
            contentURL: mediaURL,
            contentType: "video/mp4",
            textTracks: [.subtitleVTT(id: 1, name: "English", languageCode: "en-US", url: subtitleURL)]
        )

        let req1 = try await mediaController.load(item, options: .init(activeTextTrackIDs: [1]))
        let req2 = try await mediaController.disableTextTracks()

        #expect(req1 == 1)
        #expect(req2 == 2)

        let commands = await transport.commands()
        #expect(commands.count == 2)
        #expect(commands[0].route.namespace == .media)
        #expect(commands[0].route.destinationID == "web-42")
        #expect(commands[1].route.destinationID == "web-42")

        let loadJSON = try decodeJSON(commands[0].payloadUTF8)
        let disableJSON = try decodeJSON(commands[1].payloadUTF8)

        #expect(loadJSON["type"] == .string("LOAD"))
        #expect(loadJSON["requestId"] == .number(1))
        #expect(disableJSON["type"] == .string("EDIT_TRACKS_INFO"))
        #expect(disableJSON["activeTrackIds"] == .array([]))
        #expect(disableJSON["requestId"] == .number(2))
    }

    @Test("media controller throws without current app transport id")
    func mediaControllerRequiresCurrentTransportID() async {
        let transport = RecordingCommandTransport()
        let dispatcher = CastCommandDispatcher(transport: transport)
        let mediaController = CastMediaController(dispatcher: dispatcher)
        let item = CastMediaItem(
            contentURL: URL(string: "https://example.com/a.mp4")!,
            contentType: "video/mp4"
        )

        await #expect(throws: CastError.self) {
            _ = try await mediaController.load(item)
        }
    }

    private func decodeJSON(_ payloadUTF8: String) throws -> [String: JSONValue] {
        try JSONDecoder().decode([String: JSONValue].self, from: Data(payloadUTF8.utf8))
    }
}

private actor RecordingCommandTransport: CastCommandTransport {
    private var sentCommands: [CastEncodedCommand] = []

    func send(_ command: CastEncodedCommand) async throws {
        sentCommands.append(command)
    }

    func commands() -> [CastEncodedCommand] {
        sentCommands
    }
}

