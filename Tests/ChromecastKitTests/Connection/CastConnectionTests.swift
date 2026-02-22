//
//  ChromecastKit
//  Swift package for Google Cast (Chromecast).
//

import Testing
import Foundation
@testable import ChromecastKit

@Suite("Cast Connection Runtime")
struct CastConnectionTests {
    @Test("connect transitions to connected and emits event")
    func connectSuccess() async throws {
        let connection = CastConnection(transport: TestSuccessTransport())
        var iterator = await connection.events().makeAsyncIterator()

        try await connection.connect()

        #expect(await connection.state() == .connected)
        let event = try await nextEvent(&iterator)
        #expect(event == .connected)
    }

    @Test("reconnect emits reconnected event")
    func reconnectSuccess() async throws {
        let connection = CastConnection(transport: TestSuccessTransport())
        var iterator = await connection.events().makeAsyncIterator()

        try await connection.connect()
        _ = try await nextEvent(&iterator) // initial connected

        try await connection.reconnect()

        #expect(await connection.state() == .connected)
        let event = try await nextEvent(&iterator)
        #expect(event == .reconnected)
    }

    @Test("disconnect emits requested reason")
    func disconnectEmitsReason() async throws {
        let connection = CastConnection(transport: TestSuccessTransport())
        var iterator = await connection.events().makeAsyncIterator()

        try await connection.connect()
        _ = try await nextEvent(&iterator)
        await connection.disconnect(reason: .requested)

        #expect(await connection.state() == .disconnected)
        let event = try await nextEvent(&iterator)
        #expect(event == .disconnected(reason: .requested))
    }

    @Test("connect failure sets failed state and emits error")
    func connectFailure() async {
        let connection = CastConnection(transport: TestFailingTransport())
        var iterator = await connection.events().makeAsyncIterator()

        await #expect(throws: CastError.self) {
            try await connection.connect()
        }

        guard case .failed = await connection.state() else {
            Issue.record("Expected failed state")
            return
        }

        let event = try? await nextEvent(&iterator)
        guard case let .error(error)? = event else {
            Issue.record("Expected error event")
            return
        }

        guard case .connectionFailed = error else {
            Issue.record("Expected connectionFailed error")
            return
        }
    }

    private func nextEvent(
        _ iterator: inout AsyncStream<CastConnection.Event>.AsyncIterator
    ) async throws -> CastConnection.Event {
        guard let event = await iterator.next() else {
            throw CastError.invalidResponse("Missing event")
        }
        return event
    }
}

private struct TestSuccessTransport: CastConnectionTransport {
    func connect(timeout _: TimeInterval) async throws {}
    func disconnect() async {}
}

private struct TestFailingTransport: CastConnectionTransport {
    enum Failure: Error, Sendable { case boom }

    func connect(timeout _: TimeInterval) async throws {
        throw Failure.boom
    }

    func disconnect() async {}
}
