//
//  ChromecastKit
//  Swift package for Google Cast (Chromecast).
//

import Testing
import Foundation
@testable import ChromecastKit

@Suite("Cast Media Queue Payload Builder")
struct CastMediaQueuePayloadBuilderTests {
    @Test("queue load payload encodes items and options")
    func queueLoadPayload() throws {
        let payload = try CastMediaPayloadBuilder.queueLoad(
            items: [sampleQueueItem()],
            options: .init(startIndex: 0, repeatMode: .all, currentTime: 3)
        )

        let json = try encode(payload)
        #expect(json["type"] == .string("QUEUE_LOAD"))
        #expect(json["startIndex"] == .number(0))
        #expect(json["repeatMode"] == .string("REPEAT_ALL"))
        #expect(json["currentTime"] == .number(3))

        guard case let .array(items)? = json["items"], case let .object(first) = try #require(items.first) else {
            Issue.record("Missing queue items")
            return
        }

        #expect(first["media"] != nil)
    }

    @Test("session-bound queue mutations encode media session id and ids")
    func queueMutationPayloads() throws {
        let sessionID: CastMediaSessionID = 55

        let insert = try CastMediaPayloadBuilder.queueInsert(
            items: [sampleQueueItem()],
            mediaSessionID: sessionID,
            options: .init(currentItemID: 10, insertBeforeItemID: 12)
        )
        let remove = CastMediaPayloadBuilder.queueRemove(
            itemIDs: [10, 11],
            mediaSessionID: sessionID,
            options: .init(currentItemID: 10, currentTime: 8)
        )
        let reorder = CastMediaPayloadBuilder.queueReorder(
            itemIDs: [12, 13],
            mediaSessionID: sessionID,
            options: .init(insertBeforeItemID: 20)
        )
        let update = try CastMediaPayloadBuilder.queueUpdate(
            items: [sampleQueueItem(id: 30)],
            mediaSessionID: sessionID,
            options: .init(currentItemID: 10, jump: 1, repeatMode: .single)
        )

        let insertJSON = try encode(insert)
        let removeJSON = try encode(remove)
        let reorderJSON = try encode(reorder)
        let updateJSON = try encode(update)

        #expect(insertJSON["type"] == .string("QUEUE_INSERT"))
        #expect(insertJSON["mediaSessionId"] == .number(55))
        #expect(insertJSON["currentItemId"] == .number(10))
        #expect(insertJSON["insertBefore"] == .number(12))

        #expect(removeJSON["type"] == .string("QUEUE_REMOVE"))
        #expect(removeJSON["mediaSessionId"] == .number(55))
        #expect(removeJSON["itemIds"] == .array([.number(10), .number(11)]))
        #expect(removeJSON["currentTime"] == .number(8))

        #expect(reorderJSON["type"] == .string("QUEUE_REORDER"))
        #expect(reorderJSON["mediaSessionId"] == .number(55))
        #expect(reorderJSON["itemIds"] == .array([.number(12), .number(13)]))
        #expect(reorderJSON["insertBefore"] == .number(20))

        #expect(updateJSON["type"] == .string("QUEUE_UPDATE"))
        #expect(updateJSON["mediaSessionId"] == .number(55))
        #expect(updateJSON["currentItemId"] == .number(10))
        #expect(updateJSON["jump"] == .number(1))
        #expect(updateJSON["repeatMode"] == .string("REPEAT_SINGLE"))
    }

    private func sampleQueueItem(id: CastQueueItemID? = nil) throws -> CastQueueItem {
        let mediaURL = try #require(URL(string: "https://example.com/movie.mp4"))
        return CastQueueItem(
            itemID: id,
            media: .init(contentURL: mediaURL, contentType: "video/mp4")
        )
    }

    private func encode<T: Encodable & Sendable>(_ value: T) throws -> [String: JSONValue] {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode([String: JSONValue].self, from: data)
    }
}
