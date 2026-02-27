# Discovery Strategies and Network Notes

## Overview

`ChromecastKit` supports multiple discovery strategies and fallback paths:

- Bonjour/mDNS (`_googlecast._tcp`) as the primary path
- optional SSDP/DIAL fallback
- manual known-host injection

The public API hides backend implementation details behind ``CastDiscovery``.

## When to Use This Guide

Use this page when you need:

- stable discovery behavior across mixed/home/enterprise networks
- fallback behavior when Bonjour is unavailable
- practical debugging hints for local-network failures

## Discovery Configuration

Use ``CastDiscovery/Configuration`` to tune behavior:

```swift
let discovery = CastDiscovery(
    configuration: .init(
        includeGroups: true,
        browseTimeout: nil,
        enableSSDPFallback: true
    )
)
```

### `includeGroups`

Controls whether discovery should include Cast groups/speaker groups in the snapshot.

### `browseTimeout`

Optional auto-stop timeout for scanning sessions (useful for one-shot scans in UI flows).

### `enableSSDPFallback`

Enables an additional SSDP/DIAL-based discovery path for environments where Bonjour is incomplete or blocked.

## Manual Host Fallback

If network discovery is unavailable, you can seed known devices manually:

```swift
let descriptor = await discovery.addKnownHost(
    host: "192.168.1.50",
    port: 8009,
    friendlyName: "Office TV"
)

let session = CastSession(device: descriptor)
```

## Network Reachability Notes

Common discovery/connectivity issues:

- app and Chromecast are on different subnets/VLANs
- local network permission not granted (Apple platforms)
- VPN/firewall blocks local multicast or port `8009`
- enterprise Wi-Fi client isolation enabled

## Subtitle Hosting Note (Important)

`ChromecastKit` sends subtitle track metadata, but the Chromecast downloads subtitle files itself.

For reliable subtitles:

- use reachable URLs (public internet or LAN URL)
- prefer WebVTT (`text/vtt`)
- enable CORS for text track resources
- do not use `localhost` unless the Chromecast can reach that host

## See Also

- <doc:Discovery-and-Sessions>
- <doc:Runtime-Behavior-and-Error-Handling>
- <doc:Media-Playback-Queues-and-Tracks>
