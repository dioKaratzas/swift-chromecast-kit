//
//  ChromecastKit
//  Swift package for Google Cast (Chromecast).
//

import Foundation

/// Protocol for receiving inbound Cast custom namespace events through a session-managed registry.
///
/// This is useful for building app-specific controllers (for example YouTube/Plex) on top of
/// the SDK without manually wiring event streams in every integration.
public protocol CastSessionNamespaceHandler: Sendable {
    // MARK: Requirements

    /// Optional namespace filter. Return `nil` to receive all custom namespace events.
    var namespace: CastNamespace? { get }

    /// Handles a received custom namespace event.
    func handle(event: CastSession.NamespaceEvent, in session: CastSession) async
}

public extension CastSessionNamespaceHandler {
    // MARK: Defaults

    var namespace: CastNamespace? {
        nil
    }
}
