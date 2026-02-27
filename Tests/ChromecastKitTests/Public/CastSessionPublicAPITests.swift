//
//  ChromecastKit
//  SPDX-License-Identifier: Apache-2.0
//  Copyright 2026 Dionysis Karatzas
//

import Testing
import Foundation
@testable import ChromecastKit

@Suite("Cast Session Public API", .serialized)
struct CastSessionPublicAPITests {
    @Test("sendAndAwaitReply returns typed namespace message")
    func sendAndAwaitReply() async throws {
        let transport = CastSessionTestTransport()
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
        let transport = CastSessionTestTransport()
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
        let transport = CastSessionTestTransport()
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
        let transport = CastSessionTestTransport()
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

    @Test("session controller registry receives lifecycle and namespace events")
    func sessionControllerRegistry() async throws {
        let transport = CastSessionTestTransport()
        let runtime = CastSessionRuntime(
            device: .init(id: "device-1", friendlyName: "Living Room", host: "192.168.1.10"),
            transport: transport,
            configuration: .init(heartbeatInterval: 0, autoReconnect: false)
        )
        let session = CastSession(runtime: runtime)
        let controller = RecordingSessionController(namespace: "urn:x-cast:com.example.echo")

        let token = await session.registerController(controller)
        #expect(await controller.didRegisterCount() == 1)

        try await session.connect()

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

        let namespaceCount = try #require(
            await waitForSessionControllerValue(on: controller, keyPath: \.namespaceEventCount, atLeast: 1)
        )
        #expect(namespaceCount >= 1)

        let connectionCount = try #require(
            await waitForSessionControllerValue(on: controller, keyPath: \.connectionEventCount, atLeast: 1)
        )
        #expect(connectionCount >= 1)

        let stateCount = try #require(
            await waitForSessionControllerValue(on: controller, keyPath: \.stateEventCount, atLeast: 1)
        )
        #expect(stateCount >= 1)

        await session.unregisterController(token)
        #expect(await controller.willUnregisterCount() == 1)

        await session.disconnect(reason: .requested)
    }

    @Test("registerControllers registers multiple controllers in order")
    func registerControllersBatch() async {
        let transport = CastSessionTestTransport()
        let runtime = CastSessionRuntime(
            device: .init(id: "device-1", friendlyName: "Living Room", host: "192.168.1.10"),
            transport: transport,
            configuration: .init(heartbeatInterval: 0, autoReconnect: false)
        )
        let session = CastSession(runtime: runtime)
        let first = RecordingSessionController(namespace: "urn:x-cast:com.example.one")
        let second = RecordingSessionController(namespace: "urn:x-cast:com.example.two")

        let tokens = await session.registerControllers([first, second])
        #expect(tokens.count == 2)
        #expect(tokens[0] != tokens[1])
        #expect(await first.didRegisterCount() == 1)
        #expect(await second.didRegisterCount() == 1)

        await session.unregisterControllers(tokens)
        #expect(await first.willUnregisterCount() == 1)
        #expect(await second.willUnregisterCount() == 1)
    }

    @Test("unregisterNamespaceHandler cleans up controller token registrations")
    func unregisterNamespaceHandlerWithControllerToken() async throws {
        let transport = CastSessionTestTransport()
        let runtime = CastSessionRuntime(
            device: .init(id: "device-1", friendlyName: "Living Room", host: "192.168.1.10"),
            transport: transport,
            configuration: .init(heartbeatInterval: 0, autoReconnect: false)
        )
        let session = CastSession(runtime: runtime)
        let controller = RecordingSessionController(namespace: "urn:x-cast:com.example.echo")

        let token = await session.registerController(controller)
        #expect(await controller.didRegisterCount() == 1)

        await session.unregisterNamespaceHandler(token)
        #expect(await controller.willUnregisterCount() == 1)

        try await session.connect()
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
        try? await Task.sleep(nanoseconds: 50_000_000)

        let counts = await controller.counts()
        #expect(counts.namespaceEventCount == 0)
        #expect(counts.connectionEventCount == 0)
        #expect(counts.stateEventCount == 0)

        await session.disconnect(reason: .requested)
    }

    @Test("waitForApp returns active app when receiver status reports transport ready")
    func waitForApp() async throws {
        let transport = CastSessionTestTransport()
        let runtime = CastSessionRuntime(
            device: .init(id: "device-1", friendlyName: "Living Room", host: "192.168.1.10"),
            transport: transport,
            configuration: .init(heartbeatInterval: 0, autoReconnect: false)
        )
        let session = CastSession(runtime: runtime)
        try await session.connect()

        Task {
            try? await Task.sleep(nanoseconds: 50_000_000)
            await transport.emitInboundEvent(
                .utf8(
                    .init(
                        route: .init(sourceID: "receiver-0", destinationID: "sender-0", namespace: .receiver),
                        payloadUTF8: #"""
                        {"type":"RECEIVER_STATUS","status":{"volume":{"level":0.5,"muted":false},"applications":[{"appId":"CC1AD845","displayName":"Default Media Receiver","sessionId":"SESSION-1","transportId":"web-42","namespaces":[{"name":"urn:x-cast:com.google.cast.media"}]}]}}
                        """#
                    )
                )
            )
        }

        let app = try await session.waitForApp(.defaultMediaReceiver, timeout: 1)
        #expect(app?.appID == .defaultMediaReceiver)
        #expect(app?.transportID == "web-42")

        await session.disconnect(reason: .requested)
    }

    @Test("waitForNamespace returns true when active app reports support")
    func waitForNamespace() async throws {
        let transport = CastSessionTestTransport()
        let runtime = CastSessionRuntime(
            device: .init(id: "device-1", friendlyName: "Living Room", host: "192.168.1.10"),
            transport: transport,
            configuration: .init(heartbeatInterval: 0, autoReconnect: false)
        )
        let session = CastSession(runtime: runtime)
        try await session.connect()

        Task {
            try? await Task.sleep(nanoseconds: 50_000_000)
            await transport.emitInboundEvent(
                .utf8(
                    .init(
                        route: .init(sourceID: "receiver-0", destinationID: "sender-0", namespace: .receiver),
                        payloadUTF8: #"""
                        {"type":"RECEIVER_STATUS","status":{"volume":{"level":0.5,"muted":false},"applications":[{"appId":"233637DE","displayName":"YouTube","sessionId":"SESSION-1","transportId":"yt-1","namespaces":[{"name":"urn:x-cast:com.google.youtube.mdx"}]}]}}
                        """#
                    )
                )
            )
        }

        let supported = try await session.waitForNamespace(.youtubeMDX, inApp: .youtube, timeout: 1)
        #expect(supported)

        await session.disconnect(reason: .requested)
    }

    @Test("waitForNamespace returns false on timeout when namespace never appears")
    func waitForNamespaceTimeout() async throws {
        let transport = CastSessionTestTransport()
        let runtime = CastSessionRuntime(
            device: .init(id: "device-1", friendlyName: "Living Room", host: "192.168.1.10"),
            transport: transport,
            configuration: .init(heartbeatInterval: 0, autoReconnect: false)
        )
        let session = CastSession(runtime: runtime)
        try await session.connect()

        let supported = try await session.waitForNamespace(
            .youtubeMDX,
            inApp: .youtube,
            timeout: 0.05,
            pollInterval: 0.01
        )
        #expect(supported == false)

        await session.disconnect(reason: .requested)
    }

    @Test("waitForNamespace respects task cancellation")
    func waitForNamespaceCancellation() async throws {
        let transport = CastSessionTestTransport()
        let runtime = CastSessionRuntime(
            device: .init(id: "device-1", friendlyName: "Living Room", host: "192.168.1.10"),
            transport: transport,
            configuration: .init(heartbeatInterval: 0, autoReconnect: false)
        )
        let session = CastSession(runtime: runtime)
        try await session.connect()

        let task = Task {
            try await session.waitForNamespace(.youtubeMDX, inApp: .youtube, timeout: 5, pollInterval: 0.25)
        }

        try? await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()

        do {
            _ = try await task.value
            #expect(Bool(false), "Expected waitForNamespace to throw CancellationError after task cancellation")
        } catch {
            #expect(error is CancellationError)
        }

        await session.disconnect(reason: .requested)
    }

    @Test("waitForApp respects task cancellation")
    func waitForAppCancellation() async throws {
        let transport = CastSessionTestTransport()
        let runtime = CastSessionRuntime(
            device: .init(id: "device-1", friendlyName: "Living Room", host: "192.168.1.10"),
            transport: transport,
            configuration: .init(heartbeatInterval: 0, autoReconnect: false)
        )
        let session = CastSession(runtime: runtime)
        try await session.connect()

        let task = Task {
            try await session.waitForApp(.youtube, timeout: 5, pollInterval: 0.25)
        }

        try? await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()

        do {
            _ = try await task.value
            #expect(Bool(false), "Expected waitForApp to throw CancellationError after task cancellation")
        } catch {
            #expect(error is CancellationError)
        }

        await session.disconnect(reason: .requested)
    }

    @Test("connectIfNeeded avoids duplicate connect when already connected")
    func connectIfNeededIsIdempotent() async throws {
        let transport = CastSessionTestTransport()
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
        let transport = CastSessionTestTransport()
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

    @Test("youtube controller skeleton exposes stable app-specific API")
    func youtubeControllerSkeleton() async {
        let controller = CastYouTubeController()
        #expect(controller.namespace == .youtubeMDX)
        #expect(controller.appID == .youtube)
        #expect(controller.launchPolicy == .launchIfNeeded)
        #expect(await controller.status().screenID == nil)
    }

    @Test("youtube controller refreshSessionStatus captures mdx screen id")
    func youtubeControllerRefreshSessionStatus() async throws {
        let transport = CastSessionTestTransport()
        let runtime = CastSessionRuntime(
            device: .init(id: "device-1", friendlyName: "Living Room", host: "192.168.1.10"),
            transport: transport,
            configuration: .init(heartbeatInterval: 0, autoReconnect: false)
        )
        let session = CastSession(runtime: runtime)
        let controller = CastYouTubeController(launchPolicy: .manual)

        try await session.connect()
        await emitYouTubeReceiverReadyStatus(on: transport)
        let ready = await waitForYouTubeReceiverReady(on: session)
        #expect(ready)

        let task = Task {
            try await controller.refreshSessionStatus(in: session, timeout: 1)
        }

        let command = try #require(
            await waitForCommand(on: transport, namespace: .youtubeMDX),
            "Expected getMdxSessionStatus command"
        )
        let json = try JSONDecoder().decode([String: JSONValue].self, from: Data(command.payloadUTF8.utf8))
        #expect(json["type"] == .string("getMdxSessionStatus"))

        await emitYouTubeMDXSessionStatus(on: transport, screenID: "screen-123")

        let status = try await task.value
        #expect(status.screenID == "screen-123")
        #expect(await controller.status().screenID == "screen-123")

        await session.disconnect(reason: .requested)
    }

    @Test("youtube controller quickPlay uses pychromecast-style MDX web flow")
    func youtubeControllerQuickPlayUsesMDXWebSession() async throws {
        let transport = CastSessionTestTransport()
        let runtime = CastSessionRuntime(
            device: .init(id: "device-1", friendlyName: "Living Room", host: "192.168.1.10"),
            transport: transport,
            configuration: .init(heartbeatInterval: 0, autoReconnect: false)
        )
        let session = CastSession(runtime: runtime)

        let httpClient = RecordingYouTubeHTTPClient(
            responses: [
                .success(
                    .init(
                        statusCode: 200,
                        body: Data(#"{"screens":[{"loungeToken":"LOUNGE-1"}]}"#.utf8)
                    )
                ),
                .success(
                    .init(
                        statusCode: 200,
                        body: Data(#"["noop",["c","SID-1",""],["S","GSESSION-1"]]"#.utf8)
                    )
                ),
                .success(
                    .init(
                        statusCode: 200,
                        body: Data("OK".utf8)
                    )
                ),
            ]
        )
        let controller = CastYouTubeController(
            launchPolicy: .manual,
            requestTimeout: 10,
            httpClient: httpClient
        )

        try await session.connect()
        await emitYouTubeReceiverReadyStatus(on: transport)
        let ready = await waitForYouTubeReceiverReady(on: session)
        #expect(ready)

        let task = Task {
            try await controller.quickPlay(
                .init(videoID: "dQw4w9WgXcQ"),
                in: session,
                timeout: 2
            )
        }

        _ = try #require(
            await waitForCommand(on: transport, namespace: .youtubeMDX),
            "Expected getMdxSessionStatus command"
        )
        await emitYouTubeMDXSessionStatus(on: transport, screenID: "screen-abc")

        try await task.value

        let requests = await httpClient.requests()
        #expect(requests.count == 3)

        let loungeTokenRequest = requests[0]
        #expect(
            loungeTokenRequest.url.absoluteString == "https://www.youtube.com/api/lounge/pairing/get_lounge_token_batch"
        )
        #expect(loungeTokenRequest.form["screen_ids"] == "screen-abc")

        let bindRequest = requests[1]
        #expect(bindRequest.url.absoluteString == "https://www.youtube.com/api/lounge/bc/bind")
        #expect(bindRequest.query.contains(.init(name: "RID", value: "0")))
        #expect(bindRequest.query.contains(.init(name: "VER", value: "8")))
        #expect(bindRequest.query.contains(.init(name: "CVER", value: "1")))
        #expect(bindRequest.headers["X-YouTube-LoungeId-Token"] == "LOUNGE-1")

        let setPlaylistRequest = requests[2]
        #expect(setPlaylistRequest.url.absoluteString == "https://www.youtube.com/api/lounge/bc/bind")
        #expect(setPlaylistRequest.query.contains(.init(name: "SID", value: "SID-1")))
        #expect(setPlaylistRequest.query.contains(.init(name: "gsessionid", value: "GSESSION-1")))
        #expect(setPlaylistRequest.query.contains(.init(name: "RID", value: "1")))
        #expect(setPlaylistRequest.form["req0__sc"] == "setPlaylist")
        #expect(setPlaylistRequest.form["req0_videoId"] == "dQw4w9WgXcQ")
        #expect(setPlaylistRequest.form["req0_currentTime"] == "0")
        #expect(setPlaylistRequest.form["count"] == "1")

        await session.disconnect(reason: .requested)
    }

    @Test("youtube controller quickPlay rebinds and retries session request on 404")
    func youtubeControllerQuickPlayRebindsAndRetriesOn404() async throws {
        let transport = CastSessionTestTransport()
        let runtime = CastSessionRuntime(
            device: .init(id: "device-1", friendlyName: "Living Room", host: "192.168.1.10"),
            transport: transport,
            configuration: .init(heartbeatInterval: 0, autoReconnect: false)
        )
        let session = CastSession(runtime: runtime)

        let httpClient = RecordingYouTubeHTTPClient(
            responses: [
                .success(
                    .init(
                        statusCode: 200,
                        body: Data(#"{"screens":[{"loungeToken":"LOUNGE-1"}]}"#.utf8)
                    )
                ),
                .success(
                    .init(
                        statusCode: 200,
                        body: Data(#"["noop",["c","SID-1",""],["S","GSESSION-1"]]"#.utf8)
                    )
                ),
                .success(
                    .init(
                        statusCode: 404,
                        body: Data("Session expired".utf8)
                    )
                ),
                .success(
                    .init(
                        statusCode: 200,
                        body: Data(#"["noop",["c","SID-2",""],["S","GSESSION-2"]]"#.utf8)
                    )
                ),
                .success(
                    .init(
                        statusCode: 200,
                        body: Data("OK".utf8)
                    )
                ),
            ]
        )
        let controller = CastYouTubeController(
            launchPolicy: .manual,
            requestTimeout: 10,
            httpClient: httpClient
        )

        try await session.connect()
        await emitYouTubeReceiverReadyStatus(on: transport)
        let ready = await waitForYouTubeReceiverReady(on: session)
        #expect(ready)

        let task = Task {
            try await controller.quickPlay(
                .init(videoID: "dQw4w9WgXcQ"),
                in: session,
                timeout: 2
            )
        }

        _ = try #require(
            await waitForCommand(on: transport, namespace: .youtubeMDX),
            "Expected getMdxSessionStatus command"
        )
        await emitYouTubeMDXSessionStatus(on: transport, screenID: "screen-xyz")

        try await task.value

        let requests = await httpClient.requests()
        #expect(requests.count == 5)

        let firstSessionRequest = requests[2]
        #expect(firstSessionRequest.query.contains(.init(name: "SID", value: "SID-1")))
        #expect(firstSessionRequest.query.contains(.init(name: "gsessionid", value: "GSESSION-1")))

        let retriedSessionRequest = requests[4]
        #expect(retriedSessionRequest.query.contains(.init(name: "SID", value: "SID-2")))
        #expect(retriedSessionRequest.query.contains(.init(name: "gsessionid", value: "GSESSION-2")))

        await session.disconnect(reason: .requested)
    }

    private func waitForCommand(
        on transport: CastSessionTestTransport,
        requestID: CastRequestID,
        timeout: TimeInterval = 0.5
    ) async -> CastEncodedCommand? {
        _ = await TestPolling.waitUntil(timeout: timeout) {
            let commands = await transport.commands()
            return commands.contains(where: { $0.requestID == requestID })
        }
        return await transport.commands().first(where: { $0.requestID == requestID })
    }

    private func waitForCommand(
        on transport: CastSessionTestTransport,
        namespace: CastNamespace,
        timeout: TimeInterval = 0.5
    ) async -> CastEncodedCommand? {
        _ = await TestPolling.waitUntil(timeout: timeout) {
            let commands = await transport.commands()
            return commands.contains(where: { $0.route.namespace == namespace })
        }
        return await transport.commands().last(where: { $0.route.namespace == namespace })
    }

    private func emitYouTubeReceiverReadyStatus(on transport: CastSessionTestTransport) async {
        await transport.emitInboundEvent(
            .utf8(
                .init(
                    route: .init(sourceID: "receiver-0", destinationID: "sender-0", namespace: .receiver),
                    payloadUTF8: #"{"type":"RECEIVER_STATUS","status":{"volume":{"level":0.5,"muted":false},"applications":[{"appId":"233637DE","displayName":"YouTube","sessionId":"SESSION-1","transportId":"yt-1","namespaces":[{"name":"urn:x-cast:com.google.youtube.mdx"}]}]}}"#
                )
            )
        )
    }

    private func emitYouTubeMDXSessionStatus(on transport: CastSessionTestTransport, screenID: String) async {
        await transport.emitInboundEvent(
            .utf8(
                .init(
                    route: .init(sourceID: "yt-1", destinationID: "sender-0", namespace: .youtubeMDX),
                    payloadUTF8: #"{"type":"mdxSessionStatus","data":{"screenId":"\#(screenID)"}}"#
                )
            )
        )
    }

    private func waitForYouTubeReceiverReady(
        on session: CastSession,
        timeout: TimeInterval = 0.5
    ) async -> Bool {
        await TestPolling.waitUntil(timeout: timeout) {
            if let app = await session.receiverStatus()?.app,
               app.appID == .youtube,
               app.transportID != nil,
               app.namespaces.contains(CastNamespace.youtubeMDX.rawValue) {
                return true
            }
            return false
        }
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
        _ = await TestPolling.waitUntil(timeout: timeout) {
            await handler.events().count >= count
        }
        return await handler.events().count
    }

    private func waitForSessionControllerValue(
        on controller: RecordingSessionController,
        keyPath: KeyPath<RecordingSessionController.CountsSnapshot, Int>,
        atLeast count: Int,
        timeout: TimeInterval = 0.75
    ) async -> Int? {
        _ = await TestPolling.waitUntil(timeout: timeout) {
            let snapshot = await controller.counts()
            return snapshot[keyPath: keyPath] >= count
        }
        let snapshot = await controller.counts()
        return snapshot[keyPath: keyPath]
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

private actor RecordingSessionController: CastSessionController {
    struct CountsSnapshot: Sendable {
        var didRegisterCount = 0
        var willUnregisterCount = 0
        var namespaceEventCount = 0
        var connectionEventCount = 0
        var stateEventCount = 0
    }

    let namespace: CastNamespace?
    private var countsSnapshot = CountsSnapshot()

    init(namespace: CastNamespace?) {
        self.namespace = namespace
    }

    func didRegister(in _: CastSession) async {
        countsSnapshot.didRegisterCount += 1
    }

    func willUnregister(from _: CastSession) async {
        countsSnapshot.willUnregisterCount += 1
    }

    func handle(event _: CastSession.NamespaceEvent, in _: CastSession) async {
        countsSnapshot.namespaceEventCount += 1
    }

    func handle(connectionEvent _: CastSession.ConnectionEvent, in _: CastSession) async {
        countsSnapshot.connectionEventCount += 1
    }

    func handle(stateEvent _: CastSession.StateEvent, in _: CastSession) async {
        countsSnapshot.stateEventCount += 1
    }

    func counts() -> CountsSnapshot {
        countsSnapshot
    }

    func didRegisterCount() -> Int {
        countsSnapshot.didRegisterCount
    }

    func willUnregisterCount() -> Int {
        countsSnapshot.willUnregisterCount
    }
}

private actor RecordingYouTubeHTTPClient: CastYouTubeHTTPClient {
    private var queuedResponses: [Result<CastYouTubeHTTPResponse, any Error>]
    private var recordedRequests = [CastYouTubeHTTPRequest]()

    init(responses: [Result<CastYouTubeHTTPResponse, any Error>]) {
        queuedResponses = responses
    }

    func post(_ request: CastYouTubeHTTPRequest, timeout _: TimeInterval) async throws -> CastYouTubeHTTPResponse {
        recordedRequests.append(request)
        guard queuedResponses.isEmpty == false else {
            throw CastError.invalidResponse("No queued fake YouTube HTTP response")
        }
        let next = queuedResponses.removeFirst()
        return try next.get()
    }

    func requests() -> [CastYouTubeHTTPRequest] {
        recordedRequests
    }
}
