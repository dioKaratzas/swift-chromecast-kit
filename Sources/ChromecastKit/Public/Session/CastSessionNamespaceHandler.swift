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

// MARK: - Session Controllers

/// Higher-level session-attached controller protocol for app-specific integrations.
///
/// This builds on top of `CastSessionNamespaceHandler` with lifecycle hooks similar to the
/// controller model used by mature Cast libraries (for example pychromecast), but adapted to
/// Swift concurrency and actor isolation.
public protocol CastSessionController: CastSessionNamespaceHandler {
    /// Called after the controller is registered on a `CastSession`.
    func didRegister(in session: CastSession) async

    /// Called before the controller is unregistered from a `CastSession`.
    func willUnregister(from session: CastSession) async

    /// Called for high-level session connection lifecycle events.
    func handle(connectionEvent: CastSession.ConnectionEvent, in session: CastSession) async

    /// Called for receiver/media/multizone state updates.
    func handle(stateEvent: CastSession.StateEvent, in session: CastSession) async
}

public extension CastSessionController {
    func didRegister(in _: CastSession) async {}
    func willUnregister(from _: CastSession) async {}
    func handle(connectionEvent _: CastSession.ConnectionEvent, in _: CastSession) async {}
    func handle(stateEvent _: CastSession.StateEvent, in _: CastSession) async {}
}

// MARK: - App Controllers

/// Launch/readiness behavior for app-specific controllers.
public enum CastAppControllerLaunchPolicy: String, Sendable, Hashable, Codable {
    /// Require the target app to already be running; do not auto-launch.
    case manual
    /// Launch the supporting app if it is not already active.
    case launchIfNeeded
    /// Launch the supporting app even if another app currently exposes the namespace.
    case forceLaunch
}

/// Protocol for app-specific Cast controllers (for example YouTube/Plex-style integrations).
///
/// This protocol is intended for controllers that operate on app-defined namespaces and may need
/// app-launch/readiness behavior before sending messages. Built-in controllers like
/// `CastReceiverController` remain concrete and ergonomic, but app integrations can conform to this
/// protocol for reusable lifecycle and launch-policy behavior.
public protocol CastAppController: CastSessionController {
    /// App identifier the controller targets.
    var appID: CastAppID { get }

    /// Desired app launch policy before sending namespace commands.
    var launchPolicy: CastAppControllerLaunchPolicy { get }
}

public extension CastAppController {
    var launchPolicy: CastAppControllerLaunchPolicy {
        .launchIfNeeded
    }

    /// Returns `true` when the receiver reports this app as active and the app transport is ready.
    func isAppReady(in session: CastSession) async -> Bool {
        let receiverStatus = await session.receiverStatus()
        guard let app = receiverStatus?.app, app.appID == appID else {
            return false
        }
        return app.transportID != nil
    }

    /// Ensures the target app is running according to the controller's launch policy.
    ///
    /// Returns `true` when the app is ready for app-targeted namespace messaging.
    @discardableResult
    func ensureAppReady(in session: CastSession) async throws -> Bool {
        switch launchPolicy {
        case .manual:
            return await isControllerReady(in: session)

        case .launchIfNeeded:
            if await isControllerReady(in: session) {
                return true
            }
            _ = try await session.receiver.launch(appID: appID)

        case .forceLaunch:
            _ = try await session.receiver.launch(appID: appID)
        }

        guard try await session.waitForApp(appID, timeout: 6) != nil else {
            return false
        }

        guard let namespace else {
            return true
        }
        return try await session.waitForNamespace(namespace, inApp: appID, timeout: 6)
    }

    private func isControllerReady(in session: CastSession) async -> Bool {
        guard await isAppReady(in: session) else {
            return false
        }
        guard let namespace else {
            return true
        }
        let receiverStatus = await session.receiverStatus()
        guard let app = receiverStatus?.app, app.appID == appID else {
            return false
        }
        return app.namespaces.contains(namespace.rawValue)
    }
}

// MARK: - Quick Play

/// Generic protocol for app-specific "quick play" controllers.
///
/// This mirrors the ergonomics of pychromecast's `QuickPlayController`, but keeps request types
/// strongly typed in Swift.
public protocol CastQuickPlayController: CastAppController {
    associatedtype QuickPlayRequest: Sendable

    /// Launches/targets the controller app and starts playback using an app-specific request shape.
    func quickPlay(_ request: QuickPlayRequest, in session: CastSession, timeout: TimeInterval) async throws
}
