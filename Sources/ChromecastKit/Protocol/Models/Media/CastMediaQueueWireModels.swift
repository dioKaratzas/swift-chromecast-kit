//
//  ChromecastKit
//  Swift package for Google Cast (Chromecast).
//

import Foundation

public extension CastWire.Media {
    /// Wire queue item for `QUEUE_*` requests.
    struct QueueItem: Sendable, Hashable, Codable {
        public let itemId: CastQueueItemID?
        public let media: Information
        public let autoplay: Bool?
        public let startTime: TimeInterval?
        public let preloadTime: TimeInterval?
        public let activeTrackIds: [CastMediaTrackID]?
        public let customData: JSONValue?

        public init(
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

public extension CastWire.Media {
    /// Wire model for `QUEUE_LOAD`.
    struct QueueLoadRequest: Sendable, Hashable, Codable {
        public let type: CastMediaMessageType
        public let items: [QueueItem]
        public let startIndex: Int?
        public let repeatMode: CastQueueRepeatMode?
        public let currentTime: TimeInterval?
        public let customData: JSONValue?

        public init(
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

public extension CastWire.Media {
    /// Shared session-bound queue mutation fields.
    struct QueueMutationContext: Sendable, Hashable, Codable {
        public let mediaSessionId: CastMediaSessionID
        public let currentItemId: CastQueueItemID?
        public let currentItemIndex: Int?
        public let currentTime: TimeInterval?

        public init(
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

public extension CastWire.Media {
    /// Wire model for `QUEUE_INSERT`.
    struct QueueInsertRequest: Sendable, Hashable, Codable {
        public let type: CastMediaMessageType
        public let mediaSessionId: CastMediaSessionID
        public let currentItemId: CastQueueItemID?
        public let currentItemIndex: Int?
        public let currentTime: TimeInterval?
        public let insertBefore: CastQueueItemID?
        public let items: [QueueItem]

        public init(
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

public extension CastWire.Media {
    /// Wire model for `QUEUE_REMOVE`.
    struct QueueRemoveRequest: Sendable, Hashable, Codable {
        public let type: CastMediaMessageType
        public let mediaSessionId: CastMediaSessionID
        public let currentItemId: CastQueueItemID?
        public let currentTime: TimeInterval?
        public let itemIds: [CastQueueItemID]

        public init(
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

public extension CastWire.Media {
    /// Wire model for `QUEUE_REORDER`.
    struct QueueReorderRequest: Sendable, Hashable, Codable {
        public let type: CastMediaMessageType
        public let mediaSessionId: CastMediaSessionID
        public let currentItemId: CastQueueItemID?
        public let currentTime: TimeInterval?
        public let insertBefore: CastQueueItemID?
        public let itemIds: [CastQueueItemID]

        public init(
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

public extension CastWire.Media {
    /// Wire model for `QUEUE_UPDATE`.
    struct QueueUpdateRequest: Sendable, Hashable, Codable {
        public let type: CastMediaMessageType
        public let mediaSessionId: CastMediaSessionID
        public let currentItemId: CastQueueItemID?
        public let currentTime: TimeInterval?
        public let jump: Int?
        public let repeatMode: CastQueueRepeatMode?
        public let items: [QueueItem]?

        public init(
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
