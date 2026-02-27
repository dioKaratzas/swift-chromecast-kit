//
//  ChromecastKit
//  SPDX-License-Identifier: Apache-2.0
//  Copyright 2026 Dionysis Karatzas
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

    /// Default target for namespace messages emitted by this controller.
    var messageTarget: CastSession.NamespaceTarget { get }

    /// Maximum time to wait for app launch/readiness checks.
    var appReadinessTimeout: TimeInterval { get }

    /// Poll interval used during app launch/readiness checks.
    var appReadinessPollInterval: TimeInterval { get }
}

public extension CastAppController {
    var launchPolicy: CastAppControllerLaunchPolicy {
        .launchIfNeeded
    }

    var messageTarget: CastSession.NamespaceTarget {
        .currentApplication
    }

    var appReadinessTimeout: TimeInterval {
        6
    }

    var appReadinessPollInterval: TimeInterval {
        0.25
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

        guard try await session.waitForApp(
            appID,
            timeout: appReadinessTimeout,
            pollInterval: appReadinessPollInterval
        ) != nil else {
            return false
        }

        guard let namespace else {
            return true
        }
        return try await session.waitForNamespace(
            namespace,
            inApp: appID,
            timeout: appReadinessTimeout,
            pollInterval: appReadinessPollInterval
        )
    }

    /// Sends a controller-scoped JSON payload on the controller namespace.
    ///
    /// When `ensureReady` is `true` (default), app launch/readiness is checked first according to
    /// `launchPolicy`.
    @discardableResult
    func send(
        payload: [String: JSONValue],
        in session: CastSession,
        ensureReady: Bool = true
    ) async throws -> CastRequestID {
        let namespace = try requireControllerNamespace()
        if ensureReady {
            guard try await ensureAppReady(in: session) else {
                throw CastError.unsupportedNamespace("Controller namespace is not ready on the active app")
            }
        }
        return try await session.send(
            namespace: namespace,
            target: messageTarget,
            payload: payload
        )
    }

    /// Sends a controller-scoped JSON payload and awaits a correlated reply.
    func sendAndAwaitReply(
        payload: [String: JSONValue],
        in session: CastSession,
        timeout: TimeInterval? = nil,
        ensureReady: Bool = true
    ) async throws -> CastSession.NamespaceMessage {
        let namespace = try requireControllerNamespace()
        if ensureReady {
            guard try await ensureAppReady(in: session) else {
                throw CastError.unsupportedNamespace("Controller namespace is not ready on the active app")
            }
        }
        return try await session.sendAndAwaitReply(
            namespace: namespace,
            target: messageTarget,
            payload: payload,
            timeout: timeout
        )
    }

    /// Sends an untracked controller-scoped JSON payload on the controller namespace.
    func sendUntracked(
        payload: [String: JSONValue],
        in session: CastSession,
        ensureReady: Bool = true
    ) async throws {
        let namespace = try requireControllerNamespace()
        if ensureReady {
            guard try await ensureAppReady(in: session) else {
                throw CastError.unsupportedNamespace("Controller namespace is not ready on the active app")
            }
        }
        try await session.sendUntracked(
            namespace: namespace,
            target: messageTarget,
            payload: payload
        )
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

    private func requireControllerNamespace() throws -> CastNamespace {
        guard let namespace else {
            throw CastError.invalidArgument("CastAppController requires a namespace to send messages")
        }
        return namespace
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
