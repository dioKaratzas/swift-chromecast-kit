# Multizone and Groups

## Overview

`ChromecastKit` includes a ``CastMultizoneController`` for Cast speaker groups and multizone metadata.

This is useful for:

- querying speaker-group membership
- inspecting casting groups reported by the multizone namespace
- building group-aware UIs

## When to Use This Guide

Use this page when you need:

- group-aware dashboards or route pickers
- member/coordinator metadata for speaker groups
- polling-based multizone state refresh patterns

## Querying Multizone State

```swift
try await session.multizone.getStatus()
try await session.multizone.getCastingGroups()

let status = await session.multizone.status()
```

You can also read the latest value from the session snapshot:

```swift
let snapshot = await session.snapshot()
print(snapshot.multizoneStatus as Any)
```

## Models

The public multizone models include:

- ``CastMultizoneStatus``
- ``CastMultizoneMember``
- ``CastCastingGroup``

These are immutable, typed, and `Sendable`, so they can be passed across actors/tasks safely.

## Discovery and Groups

Group devices may also appear during discovery as devices with capabilities such as:

- ``CastDeviceCapability/group``
- ``CastDeviceCapability/multizone``

You can include or exclude group devices through ``CastDiscovery/Configuration/includeGroups`` depending on your UI.

## See Also

- <doc:Discovery-and-Sessions>
- <doc:Discovery-Strategies-and-Network-Notes>
