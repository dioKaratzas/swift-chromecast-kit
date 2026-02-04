//
//  ChromecastKit
//  Swift package for Google Cast (Chromecast).
//

import Testing
import Foundation
@testable import ChromecastKit

@Suite("Cast Session Runtime")
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
        let session = CastSession(device: device, transport: transport)
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

    @Test("inbound statuses update snapshot and enable media session-bound commands")
    func statusProcessingAndCommands() async throws {
        let transport = TestSessionTransport()
        let device = CastDeviceDescriptor(
            id: "device-1",
            friendlyName: "Living Room",
            host: "192.168.1.10",
            port: 8009
        )
        let session = CastSession(device: device, transport: transport)

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

    private func nextConnectionEvent(
        _ iterator: inout AsyncStream<CastConnectionEvent>.AsyncIterator
    ) async throws -> CastConnectionEvent {
        guard let event = await iterator.next() else {
            throw CastError.invalidResponse("Missing connection event")
        }
        return event
    }
}

private actor TestSessionTransport: CastConnectionTransport, CastCommandTransport {
    private(set) var connectCount = 0
    private(set) var disconnectCount = 0
    private var sentCommands = [CastEncodedCommand]()

    func connect(timeout _: TimeInterval) async throws {
        connectCount += 1
    }

    func disconnect() async {
        disconnectCount += 1
    }

    func send(_ command: CastEncodedCommand) async throws {
        sentCommands.append(command)
    }

    func commands() -> [CastEncodedCommand] {
        sentCommands
    }

    func lifecycle() -> (connects: Int, disconnects: Int) {
        (connectCount, disconnectCount)
    }
}
