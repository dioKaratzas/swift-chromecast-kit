//
//  ChromecastKit
//  SPDX-License-Identifier: Apache-2.0
//  Copyright 2026 Dionysis Karatzas
//

import Testing
import Foundation
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
        await mediaController.setMediaSessionID(77)
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
        #expect(disableJSON["mediaSessionId"] == .number(77))
        #expect(disableJSON["requestId"] == .number(2))
    }

    @Test("media controller throws without current app transport id")
    func mediaControllerRequiresCurrentTransportID() async throws {
        let transport = RecordingCommandTransport()
        let dispatcher = CastCommandDispatcher(transport: transport)
        let mediaController = CastMediaController(dispatcher: dispatcher)
        let item = try CastMediaItem(
            contentURL: #require(URL(string: "https://example.com/a.mp4")),
            contentType: "video/mp4"
        )

        await #expect(throws: CastError.self) {
            _ = try await mediaController.load(item)
        }
    }

    @Test("media controller sends session-bound playback commands with media session id")
    func mediaControllerPlaybackCommands() async throws {
        let transport = RecordingCommandTransport()
        let dispatcher = CastCommandDispatcher(transport: transport)
        await dispatcher.setCurrentApplicationTransportID("web-42")
        let mediaController = CastMediaController(dispatcher: dispatcher)
        await mediaController.setMediaSessionID(55)

        _ = try await mediaController.play()
        _ = try await mediaController.pause()
        _ = try await mediaController.seek(to: 120, resume: true)
        _ = try await mediaController.setPlaybackRate(1.25)
        _ = try await mediaController.stop()

        let commands = await transport.commands()
        #expect(commands.count == 5)

        let jsons = try commands.map { try decodeJSON($0.payloadUTF8) }
        #expect(jsons[0]["type"] == .string("PLAY"))
        #expect(jsons[1]["type"] == .string("PAUSE"))
        #expect(jsons[2]["type"] == .string("SEEK"))
        #expect(jsons[2]["currentTime"] == .number(120))
        #expect(jsons[2]["resumeState"] == .string("PLAYBACK_START"))
        #expect(jsons[3]["type"] == .string("SET_PLAYBACK_RATE"))
        #expect(jsons[3]["playbackRate"] == .number(1.25))
        #expect(jsons[4]["type"] == .string("STOP"))

        for json in jsons {
            #expect(json["mediaSessionId"] == .number(55))
        }
    }

    @Test("media controller sends queue commands through current app transport")
    func mediaControllerQueueCommands() async throws {
        let transport = RecordingCommandTransport()
        let dispatcher = CastCommandDispatcher(transport: transport)
        await dispatcher.setCurrentApplicationTransportID("web-42")
        let mediaController = CastMediaController(dispatcher: dispatcher)
        await mediaController.setMediaSessionID(55)

        let mediaURL = try #require(URL(string: "https://example.com/movie.mp4"))
        let queueItem = CastQueueItem(media: .init(contentURL: mediaURL, contentType: "video/mp4"))

        _ = try await mediaController.queueLoad(items: [queueItem], options: .init(repeatMode: .all))
        _ = try await mediaController.queueInsert(items: [queueItem], options: .init(insertBeforeItemID: 11))
        _ = try await mediaController.queueRemove(itemIDs: [11, 12])
        _ = try await mediaController.queueReorder(itemIDs: [12, 13], options: .init(insertBeforeItemID: 20))
        _ = try await mediaController.queueUpdate(options: .init(jump: 1))
        _ = try await mediaController.queueNext()
        _ = try await mediaController.queuePrevious()

        let commands = await transport.commands()
        #expect(commands.count == 7)

        let jsons = try commands.map { try decodeJSON($0.payloadUTF8) }
        #expect(jsons[0]["type"] == .string("QUEUE_LOAD"))
        #expect(jsons[0]["repeatMode"] == .string("REPEAT_ALL"))
        #expect(jsons[1]["type"] == .string("QUEUE_INSERT"))
        #expect(jsons[1]["mediaSessionId"] == .number(55))
        #expect(jsons[2]["type"] == .string("QUEUE_REMOVE"))
        #expect(jsons[2]["itemIds"] == .array([.number(11), .number(12)]))
        #expect(jsons[3]["type"] == .string("QUEUE_REORDER"))
        #expect(jsons[3]["insertBefore"] == .number(20))
        #expect(jsons[4]["type"] == .string("QUEUE_UPDATE"))
        #expect(jsons[4]["jump"] == .number(1))
        #expect(jsons[5]["type"] == .string("QUEUE_UPDATE"))
        #expect(jsons[5]["jump"] == .number(1))
        #expect(jsons[6]["type"] == .string("QUEUE_UPDATE"))
        #expect(jsons[6]["jump"] == .number(-1))
    }

    @Test("media controller exposes receiver volume and mute convenience commands")
    func mediaControllerReceiverVolumeConvenience() async throws {
        let transport = RecordingCommandTransport()
        let dispatcher = CastCommandDispatcher(transport: transport)
        let mediaController = CastMediaController(dispatcher: dispatcher)

        _ = try await mediaController.setVolume(level: 0.25)
        _ = try await mediaController.setMuted(true)

        let commands = await transport.commands()
        #expect(commands.count == 2)
        #expect(commands[0].route.namespace == .receiver)
        #expect(commands[0].route.destinationID == "receiver-0")
        #expect(commands[1].route.namespace == .receiver)

        let jsons = try commands.map { try decodeJSON($0.payloadUTF8) }
        #expect(jsons[0]["type"] == .string("SET_VOLUME"))
        #expect(jsons[1]["type"] == .string("SET_VOLUME"))
    }

    @Test("media controller session-bound commands require media session id")
    func mediaControllerRequiresMediaSessionID() async throws {
        let transport = RecordingCommandTransport()
        let dispatcher = CastCommandDispatcher(transport: transport)
        await dispatcher.setCurrentApplicationTransportID("web-42")
        let mediaController = CastMediaController(dispatcher: dispatcher)

        await #expect(throws: CastError.self) {
            _ = try await mediaController.play()
        }
        await #expect(throws: CastError.self) {
            _ = try await mediaController.disableTextTracks()
        }
    }

    @Test("multizone controller sends group status and casting group requests")
    func multizoneControllerCommands() async throws {
        let transport = RecordingCommandTransport()
        let dispatcher = CastCommandDispatcher(transport: transport)
        let stateStore = CastSessionStateStore()
        let multizone = CastMultizoneController(dispatcher: dispatcher, stateStore: stateStore)

        let req1 = try await multizone.getStatus()
        let req2 = try await multizone.getCastingGroups()

        #expect(req1 == 1)
        #expect(req2 == 2)

        let commands = await transport.commands()
        #expect(commands.count == 2)
        #expect(commands[0].route.namespace == .multizone)
        #expect(commands[0].route.destinationID == "receiver-0")
        #expect(commands[1].route.namespace == .multizone)

        let jsons = try commands.map { try decodeJSON($0.payloadUTF8) }
        #expect(jsons[0]["type"] == .string("GET_STATUS"))
        #expect(jsons[1]["type"] == .string("GET_CASTING_GROUPS"))
    }

    private func decodeJSON(_ payloadUTF8: String) throws -> [String: JSONValue] {
        try JSONDecoder().decode([String: JSONValue].self, from: Data(payloadUTF8.utf8))
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
