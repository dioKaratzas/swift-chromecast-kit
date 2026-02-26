# Media Playback, Queues, and Tracks

## Overview

``CastMediaController`` provides the standard Cast media-channel commands for:

- load/playback control
- seek and playback rate
- text tracks and text track styling
- queue load/insert/remove/reorder/update

Use it through a connected ``CastSession``:

```swift
let session = CastSession(device: device)
try await session.connect()
try await session.launchDefaultMediaReceiver()
```

## Loading Media

Use ``CastMediaItem`` for typed media payloads:

```swift
let item = CastMediaItem.video(
    url: URL(string: "https://example.com/video.mp4")!,
    title: "Demo",
    subtitle: "ChromecastKit"
)

try await session.media.load(item)
```

Advanced load options are available via ``CastMediaController/LoadOptions``:

- autoplay
- start time
- active text track IDs
- custom JSON payload (`JSONValue`)

## Playback Control

Standard media commands:

- ``CastMediaController/getStatus()``
- ``CastMediaController/play()``
- ``CastMediaController/pause()``
- ``CastMediaController/stop()``
- ``CastMediaController/seek(to:resume:)``
- ``CastMediaController/setPlaybackRate(_:)``

```swift
try await session.media.getStatus()
try await session.media.play()
try await session.media.seek(to: 42)
```

## Subtitles / Text Tracks

Create track definitions with ``CastTextTrack`` and attach them to a ``CastMediaItem``.

```swift
let track = CastTextTrack.subtitleVTT(
    id: 1,
    name: "English",
    languageCode: "en",
    url: URL(string: "https://example.com/subtitles.vtt")!
)

let item = CastMediaItem.video(
    url: URL(string: "https://example.com/video.mp4")!,
    title: "Movie",
    textTracks: [track]
)

try await session.media.load(item, options: .init(activeTextTrackIDs: [track.id]))
```

Update active tracks or styling later:

- ``CastMediaController/enableTextTrack(id:)``
- ``CastMediaController/disableTextTracks()``
- ``CastMediaController/setTextTrackStyle(_:)``

```swift
try await session.media.setTextTrackStyle(
    .init(
        backgroundColorRGBAHex: "#000000AA",
        foregroundColorRGBAHex: "#FFFFFFFF",
        edgeType: .dropShadow,
        edgeColorRGBAHex: "#000000FF"
    )
)
```

## Queue Operations

Use ``CastQueueItem`` and queue methods on ``CastMediaController``:

- ``CastMediaController/queueLoad(items:options:)``
- ``CastMediaController/queueInsert(items:options:)``
- ``CastMediaController/queueRemove(itemIDs:options:)``
- ``CastMediaController/queueReorder(itemIDs:options:)``
- ``CastMediaController/queueUpdate(items:options:)``
- ``CastMediaController/queueNext()``
- ``CastMediaController/queuePrevious()``

```swift
let items = [
    CastQueueItem(media: .video(url: URL(string: "https://example.com/1.mp4")!, title: "One")),
    CastQueueItem(media: .video(url: URL(string: "https://example.com/2.mp4")!, title: "Two")),
]

try await session.media.queueLoad(items: items, options: .init(repeatMode: .all))
```

## Reading Media Status

Read the latest status from the session:

```swift
if let media = await session.mediaStatus() {
    print(media.playerState)
    print(media.adjustedCurrentTime)
    print(media.supportedCommands.contains(.seek))
}
```

``CastMediaStatus`` reflects the latest parsed media-channel state and includes:

- player state / idle reason
- timing and playback rate
- volume
- media metadata
- text tracks / active tracks
- queue status fields

