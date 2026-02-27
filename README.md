# ChromecastKit

[![Test](https://github.com/dioKaratzas/swift-chromecast-kit/actions/workflows/test.yml/badge.svg)](https://github.com/dioKaratzas/swift-chromecast-kit/actions/workflows/test.yml)
[![Latest Release](https://img.shields.io/github/v/release/dioKaratzas/swift-chromecast-kit?display_name=tag)](https://github.com/dioKaratzas/swift-chromecast-kit/releases)
[![Platforms](https://img.shields.io/badge/platforms-iOS%2013%2B%20%7C%20macOS%2010.15%2B-blue)](https://github.com/dioKaratzas/swift-chromecast-kit/blob/main/Package.swift)
[![Swift](https://img.shields.io/badge/swift-6.0-orange)](https://www.swift.org)

ChromecastKit is a production-focused Swift sender SDK for Google Cast (Chromecast), built around typed APIs, modern concurrency, and reliable session behavior.

`ChromecastKit` includes:
- device discovery (`mDNS`/Bonjour, optional SSDP fallback, manual known hosts)
- Cast v2 transport and session lifecycle (`CastSession`)
- receiver/media/multizone controllers (`session.receiver`, `session.media`, `session.multizone`)
- YouTube MDX quick-play and queue actions (`CastYouTubeController`)
- subtitles/text tracks and queue APIs for default media receiver flows
- custom namespace messaging for advanced integrations
- two macOS example apps in `./Example` (`Player` and `Showcase`; scheme: `Showcase-macOS`)

### At a Glance

| Area | What you get |
|---|---|
| API design | Strongly typed `Sendable` models and Swift-native APIs |
| Runtime reliability | Reconnect policy controls (backoff, jitter, retry caps, network-path-aware behavior) |
| Observability | Runtime log/metric/trace hooks for reconnect lifecycle events |
| Extensibility | Custom namespaces, binary payload support, app-controller protocols |
| Example coverage | `Player` for focused flows and `Showcase` for broad SDK surface exploration |

ChromecastKit is a sender/control SDK. It does not host media or subtitles. App-specific/private protocol logic stays in optional controller layers (for example `CastYouTubeController`), while receiver/media/multizone control remains concrete built-in functionality.

## Documentation

- DocC reference: [diokaratzas.github.io/ChromecastKit](https://diokaratzas.github.io/ChromecastKit/documentation/chromecastkit/)

### README Categories

| Category | Jump to section |
|---|---|
| Getting started | [Installation](#installation), [Quick Start](#quick-start) |
| Runtime and reliability | [Recovery Policy (Reconnect)](#recovery-policy-reconnect), [Observability Hooks](#observability-hooks) |
| Playback and tracks | [Subtitles (WebVTT)](#subtitles-webvtt), [Queues](#queues), [Receiver Controls (Work With Any App)](#receiver-controls-work-with-any-app) |
| Discovery and network behavior | [Discovery Strategies](#discovery-strategies) |
| Advanced integrations | [Custom Namespaces (Advanced)](#custom-namespaces-advanced), [YouTube (MDX Quick Play / Queue Actions)](#youtube-mdx-quick-play--queue-actions) |
| Groups and multizone | [Multizone / Speaker Groups](#multizone--speaker-groups) |
| Example apps | [Example Apps](#example-apps) |

## Why Teams Choose ChromecastKit

- Swift Concurrency-first runtime (`actor` isolation, `AsyncStream`, structured async workflows)
- Typed APIs instead of dictionary-heavy callsites (`Sendable` models, strong IDs, concrete controllers)
- Production reconnect controls (exponential backoff, jitter, retry limits, network-path-aware recovery)
- Built-in runtime observability (structured logs, metrics, traces for reconnect lifecycle events)
- Advanced extension points for app-specific protocols (custom namespaces and controller protocols)
- Two example apps to accelerate adoption: `Player` for focused flows and `Showcase` for full-surface integration patterns

## Installation

Add the package to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/dioKaratzas/swift-chromecast-kit.git", from: "0.1.0")
]
```

Then add the product to your target:

```swift
.target(
    name: "MyApp",
    dependencies: [
        .product(name: "ChromecastKit", package: "swift-chromecast-kit")
    ]
)
```

Requirements:
- Swift tools `6.0+`
- iOS `13+`
- macOS `10.15+`

## Quick Start

### 1. Discover a Device

```swift
import ChromecastKit

let discovery = CastDiscovery()
try await discovery.start()

let device = try await discovery.waitForFirstDevice(timeout: 10)
print(device.friendlyName, device.host, device.port)
```

### 2. Connect and Launch the Default Media Receiver

```swift
let session = CastSession(device: device)
try await session.connect()

try await session.launchDefaultMediaReceiver()
_ = try await session.waitForApp(.defaultMediaReceiver, timeout: 6)
```

### 3. Load Media

```swift
let item = CastMediaItem.video(
    url: URL(string: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4")!,
    title: "Big Buck Bunny",
    subtitle: "ChromecastKit demo"
)

try await session.media.load(item)
```

### 4. Control Playback

```swift
try await session.media.play()
try await session.media.pause()
try await session.media.seek(to: 30)
try await session.media.setPlaybackRate(1.25)
```

### 5. Inspect Session State

```swift
let snapshot = await session.snapshot()
print(snapshot.receiverStatus?.app?.displayName as Any)
print(snapshot.mediaStatus?.playerState as Any)

for await event in await session.connectionEvents() {
    print("connection:", event)
}
```

## Recovery Policy (Reconnect)

Tune retry behavior with `ReconnectPolicy`:

```swift
let session = CastSession(
    device: device,
    configuration: .init(
        autoReconnect: true,
        reconnectPolicy: .exponential(
            initialDelay: 1,
            maxDelay: 30,
            multiplier: 2,
            jitterFactor: 0.2,
            maxAttempts: nil,
            waitsForReachableNetworkPath: true
        ),
        stateRestorationPolicy: .receiverAndMedia
    )
)
```

Use `stateRestorationPolicy` to control reconnect bootstrap behavior:
- `.receiverOnly` restores receiver state only
- `.receiverAndMedia` restores receiver + media/app transport state

## Observability Hooks

Attach structured runtime diagnostics:

```swift
let session = CastSession(
    device: device,
    observability: .init(
        onLog: { event in
            print("[\(event.level.rawValue)] \(event.code): \(event.message)")
        },
        onMetric: { event in
            print("metric \(event.name)=\(event.value) \(event.unit)")
        },
        onTrace: { event in
            print("trace \(event.name) \(event.phase.rawValue) \(event.traceID)")
        }
    )
)
```

Runtime observability currently focuses on recovery/reconnect lifecycle paths.

## Subtitles (WebVTT)

Chromecast default media receivers expect subtitle tracks as WebVTT (`.vtt`) in most common flows.

```swift
let subtitles = CastTextTrack.subtitleVTT(
    id: 1,
    name: "English",
    languageCode: "en",
    url: URL(string: "https://example.com/subtitles/movie-en.vtt")!
)

let item = CastMediaItem.video(
    url: URL(string: "https://example.com/video.mp4")!,
    title: "Movie",
    textTracks: [subtitles]
)

try await session.media.load(
    item,
    options: .init(activeTextTrackIDs: [subtitles.id])
)
```

Important subtitle hosting requirements:
- `text/vtt` content type
- URL reachable by the Chromecast device
- CORS enabled (commonly required for text track loading)
- avoid `localhost` unless the Chromecast can resolve/reach it

The Example apps include a local-file demo (with an app-only embedded HTTP server) for local testing.
That helper is not part of the `ChromecastKit` package API.

## Queues

```swift
let first = CastQueueItem(
    media: .video(url: URL(string: "https://example.com/ep1.mp4")!, title: "Episode 1")
)
let second = CastQueueItem(
    media: .video(url: URL(string: "https://example.com/ep2.mp4")!, title: "Episode 2")
)

try await session.media.queueLoad(
    items: [first, second],
    options: .init(repeatMode: .all)
)

try await session.media.queueNext()
```

## Receiver Controls (Work With Any App)

Receiver-level controls generally work even when the active app is not the Default Media Receiver:

```swift
try await session.receiver.getStatus()
try await session.receiver.setVolume(level: 0.35)
try await session.receiver.setMuted(false)
```

Note:
- receiver status and volume/mute control work broadly
- generic media status/playback control depends on the active app supporting `urn:x-cast:com.google.cast.media`

## Multizone / Speaker Groups

```swift
try await session.multizone.getStatus()
try await session.multizone.getCastingGroups()

let status = await session.multizone.status()
print(status?.members.count as Any)
```

## Custom Namespaces (Advanced)

`ChromecastKit` exposes low-level custom namespace APIs for app-specific integrations:

```swift
let namespace = CastNamespace("urn:x-cast:com.example.echo")

try await session.sendUntracked(
    namespace: namespace,
    payload: ["type": .string("PING")]
)

for await event in await session.namespaceEvents(namespace) {
    print(event.namespace, event.payloadUTF8 as Any)
}
```

You can also register a handler object:

```swift
struct EchoHandler: CastSessionNamespaceHandler {
    let namespace: CastNamespace? = "urn:x-cast:com.example.echo"

    func handle(event: CastSession.NamespaceEvent, in session: CastSession) async {
        print("event:", event)
    }
}

let token = await session.registerNamespaceHandler(EchoHandler())
await session.unregisterNamespaceHandler(token)
```

For reusable app integrations, the SDK also exposes controller protocols:
- `CastSessionController`
- `CastAppController`
- `CastQuickPlayController`

Built-in controllers (`session.receiver`, `session.media`, `session.multizone`) remain concrete and ergonomic.

## YouTube (MDX Quick Play / Queue Actions)

`ChromecastKit` includes a concrete `CastYouTubeController` that follows the same high-level approach as `pychromecast`:

1. use the Cast YouTube MDX namespace to obtain a `screenId`
2. use YouTube MDX web requests (lounge token + bind + queue/play actions) to start or queue videos

```swift
let youtube = CastYouTubeController()

// Play immediately (replaces YouTube queue)
try await youtube.quickPlay(
    .init(videoID: "dQw4w9WgXcQ"),
    in: session
)

// Or enqueue instead
try await youtube.quickPlay(
    .init(videoID: "BaW_jenozKc", enqueue: true),
    in: session
)
```

You can also refresh/read the YouTube MDX session status (`screenId`):

```swift
let status = try await youtube.refreshSessionStatus(in: session)
print(status.screenID as Any)
```

Responsibility split (important):
- `CastYouTubeController`: YouTube-specific MDX quick-play and queue actions
- `session.receiver`: volume / mute / unmute (device-level)
- `session.media`: generic play / pause / seek / rate when the active app supports `com.google.cast.media`

This means a YouTube flow commonly starts with `CastYouTubeController`, then uses `session.receiver` and `session.media` for ongoing controls.

## Discovery Strategies

By default, discovery uses Bonjour (`_googlecast._tcp`).

You can enable SSDP fallback (useful on some networks) and manual host entries:

```swift
let discovery = CastDiscovery(
    configuration: .init(includeGroups: true, enableSSDPFallback: true)
)

let manual = await discovery.addKnownHost(host: "192.168.1.50", friendlyName: "Office TV")
print(manual.id)
```

## Example Apps

Location:
- `./Example` (`Player` and `Showcase` apps; Showcase runs via the `Showcase-macOS` scheme)

Run locally:
1. Open `./Example/Example.xcodeproj` in Xcode.
2. Select the `Player` or `Showcase-macOS` scheme.
3. Build and run on macOS.

Coverage:
- discovery and device selection
- session connect/disconnect/reconnect
- receiver controls
- media load/playback/subtitles/queue commands
- YouTube MDX quick-play / queue actions (plus guidance on receiver/media control split)
- local file casting (app-only local HTTP hosting for demo use)
- namespace inspection and custom messages
- multizone status queries

## License

Apache-2.0. See [`LICENSE`](./LICENSE).

Copyright 2026 Dionysis Karatzas.
