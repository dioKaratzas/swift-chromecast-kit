# Discovery and Sessions

## Overview

`ChromecastKit` separates discovery from session control:

- ``CastDiscovery`` tracks devices visible on the network.
- ``CastSession`` manages a connection to one device and exposes receiver/media/multizone controllers.

This keeps app architecture simple:

1. discover devices
2. select one device
3. create a session
4. connect and control

## Basic Flow

```swift
import ChromecastKit

let discovery = CastDiscovery()
try await discovery.start()

let device = try await discovery.waitForFirstDevice(timeout: 10)

let session = CastSession(device: device)
try await session.connect()
```

## Useful Discovery Helpers

`CastDiscovery` includes convenience APIs for common UI workflows:

- ``CastDiscovery/device(id:)``
- ``CastDiscovery/device(named:caseInsensitive:)``
- ``CastDiscovery/firstDevice()``
- ``CastDiscovery/waitForFirstDevice(timeout:)``
- ``CastDiscovery/waitForDevice(id:timeout:)``
- ``CastDiscovery/waitForDevice(named:caseInsensitive:timeout:)``
- ``CastDiscovery/addKnownHost(host:port:id:friendlyName:modelName:manufacturer:uuid:capabilities:)``

These are especially useful when:

- a user wants to reconnect to a known device by name
- discovery is restricted on the current network
- you want a manual IP fallback UI

## Session Lifecycle

Use ``CastSession`` lifecycle methods for connection management:

- ``CastSession/connect()``
- ``CastSession/connectIfNeeded()``
- ``CastSession/reconnect()``
- ``CastSession/disconnect(reason:)``

Observe lifecycle changes with:

- ``CastSession/connectionState()``
- ``CastSession/connectionEvents()``

```swift
for await event in await session.connectionEvents() {
    print("connection event:", event)
}
```

## Status Snapshots vs Streams

Use snapshots for immediate UI rendering and streams for reactive updates:

- Snapshot: ``CastSession/snapshot()``
- Stream: ``CastSession/stateEvents()``

```swift
let snapshot = await session.snapshot()
print(snapshot.receiverStatus?.app?.displayName as Any)

for await event in await session.stateEvents() {
    print("state event:", event)
}
```

## Receiver-First Strategy (Recommended)

When connecting to a device, especially when another app is already running:

1. connect the session
2. request receiver status
3. inspect the active app
4. decide whether to launch the Default Media Receiver or interact at receiver level only

```swift
try await session.connect()
try await session.receiver.getStatus()

if let app = await session.receiverStatus()?.app {
    print("Running app:", app.displayName, app.appID.rawValue)
}
```

