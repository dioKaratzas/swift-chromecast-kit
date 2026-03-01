# ``ChromecastKit``

Modern Swift APIs for Google Cast (Chromecast) sender apps.

## Overview

`ChromecastKit` provides a typed, concurrency-first Swift interface for:

- discovering Cast devices on the local network
- connecting and maintaining a Cast session
- controlling receiver and media channels
- using app-specific controllers such as YouTube MDX quick play / queue actions
- managing subtitles, text tracks, and media queues
- querying multizone/speaker-group state
- handling custom Cast namespaces for advanced integrations

The public API is intentionally split between:

- simple task-oriented facades (`CastDiscovery`, `CastSession`)
- typed domain models (`CastMediaItem`, `CastReceiverStatus`, `CastMediaStatus`, etc.)
- advanced extensibility (`CastNamespace`, namespace events/handlers)

## Start Here

If you are new to the package, use this order:

1. <doc:Discovery-and-Sessions>
2. <doc:Media-Playback-Queues-and-Tracks>
3. <doc:Runtime-Behavior-and-Error-Handling>

## Read by Scenario

- First-time Cast flow (discover -> connect -> launch -> play):
  - <doc:Discovery-and-Sessions>
  - <doc:Media-Playback-Queues-and-Tracks>
- Production runtime behavior and reconnect tuning:
  - <doc:Runtime-Behavior-and-Error-Handling>
- Network-restricted environments and discovery fallback:
  - <doc:Discovery-Strategies-and-Network-Notes>
- Custom app integrations and namespace protocols:
  - <doc:Custom-Namespaces-and-Handlers>
- Speaker groups and multizone metadata:
  - <doc:Multizone-and-Groups>

## Topics

### Essentials

- <doc:Discovery-and-Sessions>
- <doc:Media-Playback-Queues-and-Tracks>
- ``CastDiscovery``
- ``CastSession``

### Device Discovery

- <doc:Discovery-Strategies-and-Network-Notes>
- ``CastDiscovery/Configuration``
- ``CastDeviceDescriptor``
- ``CastDiscovery/Event``

### Receiver and Media Control

- ``CastReceiverController``
- ``CastMediaController``
- ``CastMediaItem``
- ``CastMediaStatus``
- ``CastReceiverStatus``

### Queues, Tracks, and Styling

- ``CastQueueItem``
- ``CastQueueRepeatMode``
- ``CastTextTrack``
- ``CastTextTrackStyle``

### Multizone / Groups

- <doc:Multizone-and-Groups>
- ``CastMultizoneController``
- ``CastMultizoneStatus``

### Advanced Namespace Messaging

- <doc:Custom-Namespaces-and-Handlers>
- ``CastNamespace``
- ``CastSessionController``
- ``CastAppController``
- ``CastQuickPlayController``
- ``CastYouTubeController``
- ``CastSession/registerNamespaceHandler(_:)``
- ``CastSession/registerController(_:)``
- ``CastSession/namespaceEvents(_:)``
- ``CastSession/send(namespace:target:payload:)``
- ``CastSession/waitForApp(_:timeout:pollInterval:)``
- ``CastSession/waitForNamespace(_:inApp:timeout:pollInterval:)``

### Operational Behavior

- <doc:Runtime-Behavior-and-Error-Handling>
- ``CastSession/Configuration``
- ``CastSession/ReconnectPolicy``
- ``CastSession/StateRestorationPolicy``
- ``ChromecastKitLogLevel``
- ``CastError``
