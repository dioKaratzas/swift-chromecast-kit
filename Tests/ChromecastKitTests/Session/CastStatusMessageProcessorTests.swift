//
//  ChromecastKit
//  Swift package for Google Cast (Chromecast).
//

import Testing
import Foundation
@testable import ChromecastKit

@Suite("Cast Status Message Processor")
struct CastStatusMessageProcessorTests {
    @Test("receiver status updates state and current app transport routing")
    func receiverStatusUpdatesRouting() async throws {
        let transport = RecordingCommandTransport()
        let dispatcher = CastCommandDispatcher(transport: transport)
        let mediaController = CastMediaController(dispatcher: dispatcher)
        let stateStore = CastSessionStateStore()
        let processor = CastStatusMessageProcessor(
            stateStore: stateStore,
            dispatcher: dispatcher,
            mediaController: mediaController
        )

        let message = CastInboundMessage(
            route: .init(sourceID: "receiver-0", destinationID: "sender-0", namespace: .receiver),
            payloadUTF8: #"""
            {"type":"RECEIVER_STATUS","status":{"volume":{"level":0.4,"muted":false},"applications":[{"appId":"CC1AD845","displayName":"Default Media Receiver","sessionId":"SESSION-1","transportId":"web-42","statusText":"Ready","namespaces":[{"name":"urn:x-cast:com.google.cast.media"}]}],"isStandBy":false,"isActiveInput":true}}
            """#
        )

        let handled = try await processor.apply(message)
        #expect(handled)

        let receiverStatus = try #require(await stateStore.receiverStatus())
        #expect(receiverStatus.volume.level == 0.4)
        #expect(receiverStatus.app?.appID == "CC1AD845")
        #expect(receiverStatus.app?.transportID == "web-42")
        #expect(receiverStatus.app?.sessionID == "SESSION-1")
        #expect(receiverStatus.app?.namespaces == ["urn:x-cast:com.google.cast.media"])

        _ = try await mediaController.getStatus()

        let command = try #require(await transport.commands().last)
        #expect(command.route.namespace == .media)
        #expect(command.route.destinationID == "web-42")
    }

    @Test("media status updates typed state and primes media session commands")
    func mediaStatusUpdatesMediaControllerSession() async throws {
        let transport = RecordingCommandTransport()
        let dispatcher = CastCommandDispatcher(transport: transport)
        let mediaController = CastMediaController(dispatcher: dispatcher)
        let stateStore = CastSessionStateStore()
        let processor = CastStatusMessageProcessor(
            stateStore: stateStore,
            dispatcher: dispatcher,
            mediaController: mediaController
        )

        await dispatcher.setCurrentApplicationTransportID("web-42")

        let message = CastInboundMessage(
            route: .init(sourceID: "web-42", destinationID: "sender-0", namespace: .media),
            payloadUTF8: #"""
            {"type":"MEDIA_STATUS","status":[{"mediaSessionId":55,"playerState":"PLAYING","currentTime":12,"playbackRate":1,"supportedMediaCommands":4098,"volume":{"level":0.7,"muted":false},"activeTrackIds":[3],"currentItemId":10,"loadingItemId":11,"repeatMode":"REPEAT_ALL","media":{"contentId":"https://example.com/movie.mp4","contentType":"video/mp4","streamType":"BUFFERED","duration":120,"metadata":{"metadataType":0,"title":"Movie","subtitle":"Demo","images":[{"url":"https://example.com/poster.jpg"}]},"tracks":[{"trackId":3,"type":"TEXT","name":"English","language":"en-US","trackContentId":"https://example.com/en.vtt","trackContentType":"text/vtt","subtype":"SUBTITLES"}]}}]}
            """#
        )

        let handled = try await processor.apply(message)
        #expect(handled)

        let mediaStatus = try #require(await stateStore.mediaStatus())
        #expect(mediaStatus.mediaSessionID == 55)
        #expect(mediaStatus.playerState == .playing)
        #expect(mediaStatus.currentTime == 12)
        #expect(mediaStatus.volume.level == 0.7)
        #expect(mediaStatus.activeTextTrackIDs == [3])
        #expect(mediaStatus.queueCurrentItemID == 10)
        #expect(mediaStatus.queueLoadingItemID == 11)
        #expect(mediaStatus.queueRepeatMode == .all)
        #expect(mediaStatus.contentType == "video/mp4")
        #expect(
            try mediaStatus.metadata == .generic(
                title: "Movie",
                subtitle: "Demo",
                images: [.init(url: #require(URL(string: "https://example.com/poster.jpg")))]
            )
        )
        #expect(mediaStatus.textTracks.first?.id == 3)

        _ = try await mediaController.play()

        let command = try #require(await transport.commands().last)
        let json = try JSONDecoder().decode([String: JSONValue].self, from: Data(command.payloadUTF8.utf8))
        #expect(command.route.destinationID == "web-42")
        #expect(json["type"] == .string("PLAY"))
        #expect(json["mediaSessionId"] == .number(55))
    }

    @Test("non status messages are ignored")
    func ignoresNonStatusMessages() async throws {
        let transport = RecordingCommandTransport()
        let dispatcher = CastCommandDispatcher(transport: transport)
        let mediaController = CastMediaController(dispatcher: dispatcher)
        let stateStore = CastSessionStateStore()
        let processor = CastStatusMessageProcessor(
            stateStore: stateStore,
            dispatcher: dispatcher,
            mediaController: mediaController
        )

        let handled = try await processor.apply(
            .init(
                route: .init(sourceID: "receiver-0", destinationID: "sender-0", namespace: .receiver),
                payloadUTF8: #"{"type":"GET_STATUS"}"#
            )
        )

        #expect(!handled)
        #expect(await stateStore.snapshot() == .init())
    }

    @Test("receiver status without applications clears current app transport routing")
    func receiverStatusWithoutApplicationsClearsRouting() async throws {
        let transport = RecordingCommandTransport()
        let dispatcher = CastCommandDispatcher(transport: transport)
        let mediaController = CastMediaController(dispatcher: dispatcher)
        let stateStore = CastSessionStateStore()
        let processor = CastStatusMessageProcessor(
            stateStore: stateStore,
            dispatcher: dispatcher,
            mediaController: mediaController
        )

        _ = try await processor.apply(
            .init(
                route: .init(sourceID: "receiver-0", destinationID: "sender-0", namespace: .receiver),
                payloadUTF8: #"""
                {"type":"RECEIVER_STATUS","status":{"volume":{"level":0.5,"muted":false},"applications":[{"appId":"CC1AD845","displayName":"Default Media Receiver","transportId":"web-42"}]}}
                """#
            )
        )
        _ = try await mediaController.getStatus()
        #expect(
            try JSONDecoder().decode(
                [String: JSONValue].self,
                from: Data(#require(await transport.commands().last).payloadUTF8.utf8)
            )["type"] == .string("GET_STATUS")
        )

        let handled = try await processor.apply(
            .init(
                route: .init(sourceID: "receiver-0", destinationID: "sender-0", namespace: .receiver),
                payloadUTF8: #"{"type":"RECEIVER_STATUS","status":{"volume":{"level":0.2,"muted":true},"applications":[]}}"#
            )
        )
        #expect(handled)

        let receiverStatus = try #require(await stateStore.receiverStatus())
        #expect(receiverStatus.app == nil)
        #expect(receiverStatus.volume.muted)

        await #expect(throws: CastError.self) {
            _ = try await mediaController.getStatus()
        }
    }

    @Test("receiver status missing volume level clears receiver status and routing")
    func receiverStatusMissingVolumeLevelClearsState() async throws {
        let transport = RecordingCommandTransport()
        let dispatcher = CastCommandDispatcher(transport: transport)
        let mediaController = CastMediaController(dispatcher: dispatcher)
        let stateStore = CastSessionStateStore()
        let processor = CastStatusMessageProcessor(
            stateStore: stateStore,
            dispatcher: dispatcher,
            mediaController: mediaController
        )

        _ = try await processor.apply(
            .init(
                route: .init(sourceID: "receiver-0", destinationID: "sender-0", namespace: .receiver),
                payloadUTF8: #"""
                {"type":"RECEIVER_STATUS","status":{"volume":{"level":0.5,"muted":false},"applications":[{"appId":"CC1AD845","displayName":"Default Media Receiver","transportId":"web-42"}]}}
                """#
            )
        )

        let handled = try await processor.apply(
            .init(
                route: .init(sourceID: "receiver-0", destinationID: "sender-0", namespace: .receiver),
                payloadUTF8: #"{"type":"RECEIVER_STATUS","status":{"volume":{"muted":false}}}"#
            )
        )

        #expect(handled)
        #expect(await stateStore.receiverStatus() == nil)
        await #expect(throws: CastError.self) {
            _ = try await mediaController.getStatus()
        }
    }

    @Test("empty media status array clears media state and media session id")
    func emptyMediaStatusClearsMediaState() async throws {
        let transport = RecordingCommandTransport()
        let dispatcher = CastCommandDispatcher(transport: transport)
        let mediaController = CastMediaController(dispatcher: dispatcher)
        let stateStore = CastSessionStateStore()
        let processor = CastStatusMessageProcessor(
            stateStore: stateStore,
            dispatcher: dispatcher,
            mediaController: mediaController
        )

        await dispatcher.setCurrentApplicationTransportID("web-42")

        _ = try await processor.apply(
            .init(
                route: .init(sourceID: "web-42", destinationID: "sender-0", namespace: .media),
                payloadUTF8: #"{"type":"MEDIA_STATUS","status":[{"mediaSessionId":55,"playerState":"PAUSED","currentTime":1.5,"volume":{"level":1,"muted":false}}]}"#
            )
        )
        #expect(await (stateStore.mediaStatus())?.mediaSessionID == 55)

        let handled = try await processor.apply(
            .init(
                route: .init(sourceID: "web-42", destinationID: "sender-0", namespace: .media),
                payloadUTF8: #"{"type":"MEDIA_STATUS","status":[]}"#
            )
        )

        #expect(handled)
        #expect(await stateStore.mediaStatus() == nil)
        await #expect(throws: CastError.self) {
            _ = try await mediaController.play()
        }
    }

    @Test("media status with unknown metadata type remains handled and omits metadata")
    func mediaStatusUnknownMetadataType() async throws {
        let transport = RecordingCommandTransport()
        let dispatcher = CastCommandDispatcher(transport: transport)
        let mediaController = CastMediaController(dispatcher: dispatcher)
        let stateStore = CastSessionStateStore()
        let processor = CastStatusMessageProcessor(
            stateStore: stateStore,
            dispatcher: dispatcher,
            mediaController: mediaController
        )

        let handled = try await processor.apply(
            .init(
                route: .init(sourceID: "web-42", destinationID: "sender-0", namespace: .media),
                payloadUTF8: #"""
                {"type":"MEDIA_STATUS","status":[{"mediaSessionId":88,"playerState":"PLAYING","currentTime":3,"volume":{"level":0.8,"muted":false},"media":{"contentId":"https://example.com/a.mp4","contentType":"video/mp4","streamType":"BUFFERED","metadata":{"metadataType":999,"title":"Ignored"}}}]}
                """#
            )
        )

        #expect(handled)
        let status = try #require(await stateStore.mediaStatus())
        #expect(status.mediaSessionID == 88)
        #expect(status.metadata == nil)
        #expect(status.contentType == "video/mp4")
    }

    @Test("multizone messages update members and casting groups state")
    func multizoneMessagesUpdateState() async throws {
        let transport = RecordingCommandTransport()
        let dispatcher = CastCommandDispatcher(transport: transport)
        let mediaController = CastMediaController(dispatcher: dispatcher)
        let stateStore = CastSessionStateStore()
        let processor = CastStatusMessageProcessor(
            stateStore: stateStore,
            dispatcher: dispatcher,
            mediaController: mediaController
        )

        let statusHandled = try await processor.apply(
            .init(
                route: .init(sourceID: "receiver-0", destinationID: "sender-0", namespace: .multizone),
                payloadUTF8: #"""
                {"type":"MULTIZONE_STATUS","status":{"devices":[{"deviceId":"a","name":"Kitchen"},{"deviceId":"b","name":"Office"}]}}
                """#
            )
        )
        #expect(statusHandled)

        let groupsHandled = try await processor.apply(
            .init(
                route: .init(sourceID: "receiver-0", destinationID: "sender-0", namespace: .multizone),
                payloadUTF8: #"""
                {"type":"CASTING_GROUPS","groups":[{"deviceId":"group-1","name":"Downstairs"}]}
                """#
            )
        )
        #expect(groupsHandled)

        let removedHandled = try await processor.apply(
            .init(
                route: .init(sourceID: "receiver-0", destinationID: "sender-0", namespace: .multizone),
                payloadUTF8: #"{"type":"DEVICE_REMOVED","deviceId":"b"}"#
            )
        )
        #expect(removedHandled)

        let status = try #require(await stateStore.multizoneStatus())
        #expect(status.members.map(\.id) == ["a"])
        #expect(status.members.map(\.name) == ["Kitchen"])
        #expect(status.castingGroups == [.init(id: "group-1", name: "Downstairs")])
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
