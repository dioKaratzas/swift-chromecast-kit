//
//  ChromecastKit
//  SPDX-License-Identifier: Apache-2.0
//  Copyright 2026 Dionysis Karatzas
//

import Foundation

extension CastWire.Media {
    /// Wire queue item for `QUEUE_*` requests.
    struct QueueItem: Sendable, Hashable, Codable {
        let itemId: CastQueueItemID?
        let media: Information
        let autoplay: Bool?
        let startTime: TimeInterval?
        let preloadTime: TimeInterval?
        let activeTrackIds: [CastMediaTrackID]?
        let customData: JSONValue?

        init(
            itemId: CastQueueItemID? = nil,
            media: Information,
            autoplay: Bool? = nil,
            startTime: TimeInterval? = nil,
            preloadTime: TimeInterval? = nil,
            activeTrackIds: [CastMediaTrackID]? = nil,
            customData: JSONValue? = nil
        ) {
            self.itemId = itemId
            self.media = media
            self.autoplay = autoplay
            self.startTime = startTime
            self.preloadTime = preloadTime
            self.activeTrackIds = activeTrackIds
            self.customData = customData
        }
    }
}

extension CastWire.Media {
    /// Wire model for `QUEUE_LOAD`.
    struct QueueLoadRequest: Sendable, Hashable, Codable {
        let type: CastMediaMessageType
        let items: [QueueItem]
        let startIndex: Int?
        let repeatMode: CastQueueRepeatMode?
        let currentTime: TimeInterval?
        let customData: JSONValue?

        init(
            type: CastMediaMessageType = .queueLoad,
            items: [QueueItem],
            startIndex: Int? = nil,
            repeatMode: CastQueueRepeatMode? = nil,
            currentTime: TimeInterval? = nil,
            customData: JSONValue? = nil
        ) {
            self.type = type
            self.items = items
            self.startIndex = startIndex
            self.repeatMode = repeatMode
            self.currentTime = currentTime
            self.customData = customData
        }
    }
}

extension CastWire.Media {
    /// Shared session-bound queue mutation fields.
    struct QueueMutationContext: Sendable, Hashable, Codable {
        let mediaSessionId: CastMediaSessionID
        let currentItemId: CastQueueItemID?
        let currentItemIndex: Int?
        let currentTime: TimeInterval?

        init(
            mediaSessionId: CastMediaSessionID,
            currentItemId: CastQueueItemID? = nil,
            currentItemIndex: Int? = nil,
            currentTime: TimeInterval? = nil
        ) {
            self.mediaSessionId = mediaSessionId
            self.currentItemId = currentItemId
            self.currentItemIndex = currentItemIndex
            self.currentTime = currentTime
        }
    }
}

extension CastWire.Media {
    /// Wire model for `QUEUE_INSERT`.
    struct QueueInsertRequest: Sendable, Hashable, Codable {
        let type: CastMediaMessageType
        let mediaSessionId: CastMediaSessionID
        let currentItemId: CastQueueItemID?
        let currentItemIndex: Int?
        let currentTime: TimeInterval?
        let insertBefore: CastQueueItemID?
        let items: [QueueItem]

        init(
            type: CastMediaMessageType = .queueInsert,
            mediaSessionId: CastMediaSessionID,
            currentItemId: CastQueueItemID? = nil,
            currentItemIndex: Int? = nil,
            currentTime: TimeInterval? = nil,
            insertBefore: CastQueueItemID? = nil,
            items: [QueueItem]
        ) {
            self.type = type
            self.mediaSessionId = mediaSessionId
            self.currentItemId = currentItemId
            self.currentItemIndex = currentItemIndex
            self.currentTime = currentTime
            self.insertBefore = insertBefore
            self.items = items
        }
    }
}

extension CastWire.Media {
    /// Wire model for `QUEUE_REMOVE`.
    struct QueueRemoveRequest: Sendable, Hashable, Codable {
        let type: CastMediaMessageType
        let mediaSessionId: CastMediaSessionID
        let currentItemId: CastQueueItemID?
        let currentTime: TimeInterval?
        let itemIds: [CastQueueItemID]

        init(
            type: CastMediaMessageType = .queueRemove,
            mediaSessionId: CastMediaSessionID,
            currentItemId: CastQueueItemID? = nil,
            currentTime: TimeInterval? = nil,
            itemIds: [CastQueueItemID]
        ) {
            self.type = type
            self.mediaSessionId = mediaSessionId
            self.currentItemId = currentItemId
            self.currentTime = currentTime
            self.itemIds = itemIds
        }
    }
}

extension CastWire.Media {
    /// Wire model for `QUEUE_REORDER`.
    struct QueueReorderRequest: Sendable, Hashable, Codable {
        let type: CastMediaMessageType
        let mediaSessionId: CastMediaSessionID
        let currentItemId: CastQueueItemID?
        let currentTime: TimeInterval?
        let insertBefore: CastQueueItemID?
        let itemIds: [CastQueueItemID]

        init(
            type: CastMediaMessageType = .queueReorder,
            mediaSessionId: CastMediaSessionID,
            currentItemId: CastQueueItemID? = nil,
            currentTime: TimeInterval? = nil,
            insertBefore: CastQueueItemID? = nil,
            itemIds: [CastQueueItemID]
        ) {
            self.type = type
            self.mediaSessionId = mediaSessionId
            self.currentItemId = currentItemId
            self.currentTime = currentTime
            self.insertBefore = insertBefore
            self.itemIds = itemIds
        }
    }
}

extension CastWire.Media {
    /// Wire model for `QUEUE_UPDATE`.
    struct QueueUpdateRequest: Sendable, Hashable, Codable {
        let type: CastMediaMessageType
        let mediaSessionId: CastMediaSessionID
        let currentItemId: CastQueueItemID?
        let currentTime: TimeInterval?
        let jump: Int?
        let repeatMode: CastQueueRepeatMode?
        let items: [QueueItem]?

        init(
            type: CastMediaMessageType = .queueUpdate,
            mediaSessionId: CastMediaSessionID,
            currentItemId: CastQueueItemID? = nil,
            currentTime: TimeInterval? = nil,
            jump: Int? = nil,
            repeatMode: CastQueueRepeatMode? = nil,
            items: [QueueItem]? = nil
        ) {
            self.type = type
            self.mediaSessionId = mediaSessionId
            self.currentItemId = currentItemId
            self.currentTime = currentTime
            self.jump = jump
            self.repeatMode = repeatMode
            self.items = items
        }
    }
}
