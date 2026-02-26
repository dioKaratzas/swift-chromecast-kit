# Runtime Behavior and Error Handling

## Overview

`ChromecastKit` is designed for long-lived sender sessions and attempts to handle common runtime concerns:

- heartbeat ping/pong monitoring
- reconnect behavior
- request/reply correlation with timeouts
- typed error mapping for common Cast error replies

## Session Configuration

Tune runtime behavior with ``CastSession/Configuration``:

```swift
let session = CastSession(
    device: device,
    configuration: .init(
        connectTimeout: 10,
        commandTimeout: 10,
        heartbeatInterval: 5,
        autoReconnect: true,
        reconnectRetryDelay: 1
    )
)
```

## Connection Events

Observe lifecycle changes via ``CastSession/connectionEvents()``:

```swift
for await event in await session.connectionEvents() {
    switch event {
    case .connected:
        print("connected")
    case let .disconnected(reason):
        print("disconnected:", reason as Any)
    case .reconnected:
        print("reconnected")
    case let .error(error):
        print("error:", error)
    }
}
```

## Request/Reply Timeouts

When using ``CastSession/sendAndAwaitReply(namespace:target:payload:timeout:)``, the SDK:

- injects a `requestId`
- waits for a matching reply
- throws on timeout
- throws mapped errors for common Cast error reply messages

This provides `async/await` ergonomics over an event-driven Cast protocol.

## Error Model

Most public failures are surfaced as ``CastError``.

Important cases include:

- ``CastError/connectionFailed(_:)``
- ``CastError/discoveryFailed(_:)``
- ``CastError/timeout(operation:)``
- ``CastError/requestFailed(code:message:)``
- ``CastError/loadFailed(code:message:)``
- ``CastError/noActiveMediaSession``

## Receiver vs Media Availability

Receiver controls are generally available whenever the device is connected.

Media controls require:

- an active app transport
- a media session (for commands like pause/seek/stop)

If there is no active media session, media commands may throw ``CastError/noActiveMediaSession``.

## Scope Note

`ChromecastKit` focuses on platform/default-media-receiver behavior and extensibility.
App-specific protocols (for example YouTube/Plex private namespaces) should be layered on top of custom namespace APIs.

