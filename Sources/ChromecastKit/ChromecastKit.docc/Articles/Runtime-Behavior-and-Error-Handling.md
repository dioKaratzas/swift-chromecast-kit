# Runtime Behavior and Error Handling

## Overview

`ChromecastKit` is designed for long-lived sender sessions and attempts to handle common runtime concerns:

- heartbeat ping/pong monitoring
- reconnect behavior
- request/reply correlation with timeouts
- typed error mapping for common Cast error replies

## When to Use This Guide

Use this page when you are:

- tuning reconnect behavior for production conditions
- configuring runtime diagnostics log levels
- validating failure semantics (timeouts, disconnects, non-success replies)

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
        reconnectPolicy: .exponential(
            initialDelay: 1,
            maxDelay: 30,
            multiplier: 2,
            jitterFactor: 0.2,
            maxAttempts: nil,
            waitsForReachableNetworkPath: true
        ),
        stateRestorationPolicy: .receiverAndMedia,
        logLevel: .error
    )
)
```

Use ``CastSession/ReconnectPolicy`` to tune retry behavior:

- fixed or exponential backoff
- jitter
- attempt cap
- optional network-path gating before retries
- optional wait timeout for reachable network

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

Auto-recovery emits:

- `.disconnected(reason:)` when runtime failure is detected
- `.reconnected` when a reconnect attempt succeeds

## Request/Reply Timeouts

When using ``CastSession/sendAndAwaitReply(namespace:target:payload:timeout:)``, the SDK:

- injects a `requestId`
- waits for a matching reply
- throws on timeout
- throws mapped errors for common Cast error reply messages

This provides `async/await` ergonomics over an event-driven Cast protocol.

## Package Logging

`ChromecastKit` emits runtime diagnostics through `OSLog` categories.
Configure verbosity with ``ChromecastKitLogLevel`` in session/discovery configuration:

```swift
let discovery = CastDiscovery(
    configuration: .init(
        includeGroups: true,
        enableSSDPFallback: true,
        logLevel: .warning
    )
)

let session = CastSession(
    device: device,
    configuration: .init(
        logLevel: .debug
    )
)
```

Use categories in Console.app or `log` CLI filters:

```bash
log stream --level debug --predicate 'subsystem == "com.swift-chromecast-kit"'
log stream --level debug --predicate 'subsystem == "com.swift-chromecast-kit" && category == "session"'
```

Built-in categories include:

- `discovery`
- `session`
- `transport`
- `command`

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

## See Also

- <doc:Discovery-and-Sessions>
- <doc:Discovery-Strategies-and-Network-Notes>
- <doc:Custom-Namespaces-and-Handlers>
