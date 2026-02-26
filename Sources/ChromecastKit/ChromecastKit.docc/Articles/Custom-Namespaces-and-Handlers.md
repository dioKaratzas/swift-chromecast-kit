# Custom Namespaces and Handlers

## Overview

Many Cast apps use custom namespaces beyond the standard receiver/media channels.

`ChromecastKit` supports this through:

- ``CastNamespace`` for typed namespace identifiers
- direct send APIs on ``CastSession``
- inbound namespace streams (UTF-8 and binary)
- handler registration via ``CastSessionNamespaceHandler``
- higher-level controller protocols (``CastSessionController``, ``CastAppController``, ``CastQuickPlayController``)

This is the extension point used for future app-specific controllers.

## Sending JSON Payloads

Send a JSON object (`[String: JSONValue]`) to a custom namespace:

```swift
let namespace = CastNamespace("urn:x-cast:com.example.echo")

try await session.sendUntracked(
    namespace: namespace,
    payload: [
        "type": .string("PING"),
        "value": .number(1)
    ]
)
```

If you need request/reply correlation, use:

- ``CastSession/send(namespace:target:payload:)``
- ``CastSession/sendAndAwaitReply(namespace:target:payload:timeout:)``

```swift
let reply = try await session.sendAndAwaitReply(
    namespace: namespace,
    payload: ["type": .string("GET_STATUS")]
)

print(try reply.jsonObject())
```

## Namespace Targets

Custom messages can be addressed to:

- current app transport (`.currentApplication`)
- platform (`.platform`)
- explicit transport ID (`.transport(_)`)

See ``CastSession/NamespaceTarget``.

## Receiving Namespace Messages

### UTF-8 Convenience Stream

Use ``CastSession/namespaceMessages(_:)`` when you only care about UTF-8 payloads:

```swift
for await message in await session.namespaceMessages(namespace) {
    print(message.payloadUTF8)
}
```

### UTF-8 + Binary Stream

Use ``CastSession/namespaceEvents(_:)`` for advanced integrations:

```swift
for await event in await session.namespaceEvents(namespace) {
    switch event.payload {
    case let .utf8(text):
        print("text:", text)
    case let .binary(bytes):
        print("binary bytes:", bytes.count)
    }
}
```

If binary bytes contain UTF-8 JSON, ``CastSession/NamespaceEvent/decodePayload(_:)`` can decode them.

## Handler Registry

For reusable integrations, register a handler object instead of wiring streams everywhere.

```swift
struct EchoHandler: CastSessionNamespaceHandler {
    let namespace: CastNamespace? = "urn:x-cast:com.example.echo"

    func handle(event: CastSession.NamespaceEvent, in session: CastSession) async {
        print(event)
    }
}

let token = await session.registerNamespaceHandler(EchoHandler())
// ...
await session.unregisterNamespaceHandler(token)
```

The session internally fans out matching custom namespace events to registered handlers.

## App-Specific Controller Protocols

For stateful app integrations (for example YouTube/Plex-style controllers), prefer the controller
protocol layer instead of wiring streams manually in each integration.

- ``CastSessionController`` adds registration/unregistration and session lifecycle callbacks.
- ``CastAppController`` adds target app identity and launch/readiness policy.
- ``CastQuickPlayController`` adds a strongly typed quick-play request surface.

Built-in SDK controllers remain concrete (`session.receiver`, `session.media`, `session.multizone`)
for ergonomic common usage.

```swift
actor EchoAppController: CastAppController {
    nonisolated let namespace: CastNamespace? = "urn:x-cast:com.example.echo"
    nonisolated let appID: CastAppID = .defaultMediaReceiver

    func handle(event: CastSession.NamespaceEvent, in session: CastSession) async {
        print("event:", event)
    }
}

let controller = EchoAppController()
let token = await session.registerController(controller)
// ...
await session.unregisterController(token)
```

If you need to wait for app readiness before namespace messaging, use:

- ``CastSession/waitForApp(_:timeout:pollInterval:)``
- ``CastSession/waitForNamespace(_:inApp:timeout:pollInterval:)``

The package includes a concrete ``CastYouTubeController`` for YouTube MDX quick-play and queue
actions. It follows the same high-level flow used by `pychromecast`:

- request YouTube `mdxSessionStatus` over the Cast MDX namespace to obtain `screenId`
- perform YouTube MDX web requests (lounge token + bind + queue/play actions)

```swift
let youtube = CastYouTubeController()

try await youtube.quickPlay(
    .init(videoID: "dQw4w9WgXcQ"),
    in: session
)

let status = try await youtube.refreshSessionStatus(in: session)
print(status.screenID as Any)
```

`CastYouTubeController` is intentionally focused on YouTube-specific MDX behavior. For ongoing
device/playback controls, keep using the built-in concrete controllers:

- `session.receiver` for volume and mute/unmute
- `session.media` for play/pause/seek/rate when the active app supports the media namespace

## Notes

- Core Cast namespaces (`receiver`, `media`, `heartbeat`, `connection`, `multizone`) are handled by the SDK runtime and are not emitted as custom namespace events.
- App-specific protocols often require handshake/stateful logic on top of namespace messages. Build that logic in a separate controller type and keep transport details inside the session APIs.
