//
//  ChromecastKit
//  SPDX-License-Identifier: Apache-2.0
//  Copyright 2026 Dionysis Karatzas
//

import Foundation
import Testing

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

    let json = try JSONDecoder().decode(
      [String: JSONValue].self, from: Data(command.payloadUTF8.utf8))
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

    let json = try JSONDecoder().decode(
      [String: JSONValue].self, from: Data(command.payloadUTF8.utf8))
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

  @Test("untracked control messages do not inject requestId")
  func untrackedControlMessageOmitsRequestID() async throws {
    let transport = RecordingCommandTransport()
    let dispatcher = CastCommandDispatcher(transport: transport)

    try await dispatcher.sendUntracked(
      namespace: .heartbeat,
      target: .platform,
      payload: CastWire.Heartbeat.Message(type: .ping)
    )

    let command = try #require(await transport.commands().first)
    let json = try JSONDecoder().decode(
      [String: JSONValue].self, from: Data(command.payloadUTF8.utf8))

    #expect(command.route.namespace == .heartbeat)
    #expect(json["type"] == .string("PING"))
    #expect(json["requestId"] == nil)
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
    let sent = try #require(await waitForFirstCommand(on: transport))
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

  @Test("consumeInboundMessage ignores non-representable numeric requestId values")
  func consumeInboundMessageIgnoresNonRepresentableNumericRequestID() async throws {
    let transport = RecordingCommandTransport()
    let dispatcher = CastCommandDispatcher(transport: transport, defaultReplyTimeout: 5)

    let replyTask = Task {
      try await dispatcher.sendAndAwaitReply(
        namespace: .receiver,
        target: .platform,
        payload: CastReceiverPayloadBuilder.getStatus()
      )
    }

    _ = try #require(await waitForFirstCommand(on: transport))

    let consumedHuge = try await dispatcher.consumeInboundMessage(
      .init(
        route: .init(sourceID: "receiver-0", destinationID: "sender-0", namespace: .receiver),
        payloadUTF8: #"{"type":"RECEIVER_STATUS","requestId":1e100}"#
      )
    )
    #expect(!consumedHuge)

    let consumedFractional = try await dispatcher.consumeInboundMessage(
      .init(
        route: .init(sourceID: "receiver-0", destinationID: "sender-0", namespace: .receiver),
        payloadUTF8: #"{"type":"RECEIVER_STATUS","requestId":1.5}"#
      )
    )
    #expect(!consumedFractional)

    replyTask.cancel()
    await #expect(throws: CancellationError.self) {
      _ = try await replyTask.value
    }
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

    for _ in 0..<10 {
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

  @Test("failAllPendingReplies resumes outstanding request waiters immediately")
  func failAllPendingReplies() async throws {
    let transport = RecordingCommandTransport()
    let dispatcher = CastCommandDispatcher(transport: transport, defaultReplyTimeout: 5)

    let replyTask = Task {
      try await dispatcher.sendAndAwaitReply(
        namespace: .receiver,
        target: .platform,
        payload: CastReceiverPayloadBuilder.getStatus()
      )
    }

    for _ in 0..<10 {
      if await transport.commands().isEmpty == false {
        break
      }
      await Task.yield()
    }

    await dispatcher.failAllPendingReplies(with: CastError.disconnected)

    do {
      _ = try await replyTask.value
      Issue.record("Expected pending reply waiter to fail")
    } catch let error as CastError {
      #expect(error == .disconnected)
    }

    let consumed = try await dispatcher.consumeInboundMessage(
      .init(
        route: .init(sourceID: "receiver-0", destinationID: "sender-0", namespace: .receiver),
        payloadUTF8: #"{"type":"RECEIVER_STATUS","requestId":1}"#
      )
    )
    #expect(!consumed)
  }

  @Test("sendAndAwaitReply throws mapped invalid request error replies")
  func sendAndAwaitReplyMapsErrorReplies() async throws {
    let transport = RecordingCommandTransport()
    let dispatcher = CastCommandDispatcher(transport: transport)

    let replyTask = Task {
      try await dispatcher.sendAndAwaitReply(
        namespace: .receiver,
        target: .platform,
        payload: CastReceiverPayloadBuilder.getStatus()
      )
    }

    for _ in 0..<10 {
      if await transport.commands().isEmpty == false {
        break
      }
      await Task.yield()
    }

    _ = try await dispatcher.consumeInboundMessage(
      .init(
        route: .init(sourceID: "receiver-0", destinationID: "sender-0", namespace: .receiver),
        payloadUTF8: #"{"type":"INVALID_REQUEST","requestId":1,"reason":"bad"}"#
      )
    )

    await #expect(throws: CastError.self) {
      _ = try await replyTask.value
    }
  }

  @Test("sendAndAwaitReply maps NOT_ALLOWED and LOAD_FAILED reply variants")
  func sendAndAwaitReplyMapsCommonErrorVariants() async throws {
    let transport = RecordingCommandTransport()
    let dispatcher = CastCommandDispatcher(transport: transport)

    let notAllowedTask = Task {
      try await dispatcher.sendAndAwaitReply(
        namespace: .receiver,
        target: .platform,
        payload: CastReceiverPayloadBuilder.getStatus()
      )
    }
    for _ in 0..<10 {
      if await transport.commands().count >= 1 {
        break
      }
      await Task.yield()
    }
    _ = try await dispatcher.consumeInboundMessage(
      .init(
        route: .init(sourceID: "receiver-0", destinationID: "sender-0", namespace: .receiver),
        payloadUTF8: #"{"type":"NOT_ALLOWED","requestId":1,"message":"denied","code":"403"}"#
      )
    )
    do {
      _ = try await notAllowedTask.value
      Issue.record("Expected NOT_ALLOWED reply to throw")
    } catch let error as CastError {
      #expect(error == .requestFailed(code: 403, message: "denied"))
    }

    let loadFailedTask = Task {
      try await dispatcher.sendAndAwaitReply(
        namespace: .media,
        target: .platform,
        payload: CastReceiverPayloadBuilder.getStatus()
      )
    }
    for _ in 0..<10 {
      if await transport.commands().count >= 2 {
        break
      }
      await Task.yield()
    }
    _ = try await dispatcher.consumeInboundMessage(
      .init(
        route: .init(sourceID: "receiver-0", destinationID: "sender-0", namespace: .media),
        payloadUTF8:
          #"{"type":"LOAD_FAILED","requestId":2,"reason":"load failed","detailedErrorCode":12}"#
      )
    )
    do {
      _ = try await loadFailedTask.value
      Issue.record("Expected LOAD_FAILED reply to throw")
    } catch let error as CastError {
      #expect(error == .loadFailed(code: 12, message: "load failed"))
    }
  }

  @Test("sendAndAwaitReply maps generic *_ERROR reply variants")
  func sendAndAwaitReplyMapsErrorSuffixVariants() async throws {
    let transport = RecordingCommandTransport()
    let dispatcher = CastCommandDispatcher(transport: transport)

    let replyTask = Task {
      try await dispatcher.sendAndAwaitReply(
        namespace: .receiver,
        target: .platform,
        payload: CastReceiverPayloadBuilder.getStatus()
      )
    }
    for _ in 0..<10 {
      if await transport.commands().count >= 1 {
        break
      }
      await Task.yield()
    }

    _ = try await dispatcher.consumeInboundMessage(
      .init(
        route: .init(sourceID: "receiver-0", destinationID: "sender-0", namespace: .receiver),
        payloadUTF8:
          #"{"type":"LAUNCH_ERROR","requestId":1,"message":"app unavailable","code":"101"}"#
      )
    )

    do {
      _ = try await replyTask.value
      Issue.record("Expected LAUNCH_ERROR reply to throw")
    } catch let error as CastError {
      #expect(error == .requestFailed(code: 101, message: "app unavailable"))
    }
  }

  @Test("binary tracked sends inject requestId into json bytes")
  func sendBinaryInjectsRequestID() async throws {
    let transport = RecordingCommandTransport()
    let dispatcher = CastCommandDispatcher(transport: transport)

    let requestID = try await dispatcher.sendBinary(
      namespace: .receiver,
      target: .platform,
      payload: Data(#"{"type":"PING"}"#.utf8)
    )

    #expect(requestID == 1)
    let command = try #require(await transport.commands().first)
    guard case .binary(let bytes) = command.payload else {
      Issue.record("Expected binary command payload")
      return
    }
    let json = try JSONDecoder().decode([String: JSONValue].self, from: bytes)
    #expect(json["type"] == .string("PING"))
    #expect(json["requestId"] == .number(1))
  }

  private func waitForFirstCommand(
    on transport: RecordingCommandTransport,
    timeout: TimeInterval = 0.5
  ) async -> CastEncodedCommand? {
    _ = await TestPolling.waitUntil(timeout: timeout) {
      await transport.commands().isEmpty == false
    }
    return await transport.commands().first
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
