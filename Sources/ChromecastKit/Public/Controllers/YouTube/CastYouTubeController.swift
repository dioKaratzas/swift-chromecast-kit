//
//  ChromecastKit
//  Swift package for Google Cast (Chromecast).
//

import Foundation

/// App-specific controller skeleton for the YouTube Cast receiver.
///
/// This type provides a Swift-native, protocol-oriented controller shape similar to pychromecast's
/// YouTube controller ergonomics, while keeping the actual YouTube MDX protocol implementation out
/// of the core non-app-specific feature set for now.
///
/// Use this controller to:
/// - register for YouTube MDX namespace events on a `CastSession`
/// - ensure the YouTube receiver app is launched and ready
/// - build future YouTube-specific quick-play and queue APIs on a stable controller abstraction
public actor CastYouTubeController: CastAppController, CastQuickPlayController {
    // MARK: Public Models

    /// A high-level quick-play request for YouTube content.
    ///
    /// This is intentionally lightweight until the YouTube MDX protocol implementation is added.
    public struct QuickPlayRequest: Sendable, Hashable, Codable {
        public var videoID: String
        public var playlistID: String?
        public var enqueue: Bool

        public init(
            videoID: String,
            playlistID: String? = nil,
            enqueue: Bool = false
        ) {
            self.videoID = videoID
            self.playlistID = playlistID
            self.enqueue = enqueue
        }
    }

    /// Latest observed YouTube MDX session identifiers (when available).
    public struct SessionStatus: Sendable, Hashable, Codable {
        public var screenID: String?

        public init(screenID: String? = nil) {
            self.screenID = screenID
        }
    }

    // MARK: Public Identity

    public nonisolated let namespace: CastNamespace? = .youtubeMDX
    public nonisolated let appID = CastAppID.youtube
    public nonisolated let launchPolicy: CastAppControllerLaunchPolicy

    // MARK: Private State

    private var sessionStatus = SessionStatus()

    // MARK: Initialization

    public init(launchPolicy: CastAppControllerLaunchPolicy = .launchIfNeeded) {
        self.launchPolicy = launchPolicy
    }

    // MARK: Public API

    /// Returns the latest observed YouTube MDX session status.
    public func status() -> SessionStatus {
        sessionStatus
    }

    /// Requests YouTube MDX session status from the running YouTube receiver app.
    ///
    /// This sends the `getMdxSessionStatus` request on the YouTube MDX namespace after ensuring
    /// the app is ready according to `launchPolicy`.
    @discardableResult
    public func requestSessionStatus(in session: CastSession) async throws -> CastRequestID {
        guard try await ensureAppReady(in: session) else {
            throw CastError.unsupportedFeature("YouTube app is not ready for MDX messaging")
        }
        return try await session.send(
            namespace: .youtubeMDX,
            target: .currentApplication,
            payload: ["type": .string("getMdxSessionStatus")]
        )
    }

    /// YouTube quick-play API placeholder.
    ///
    /// The controller lifecycle/registration is in place, but the private YouTube MDX playback
    /// protocol is not implemented yet.
    public func quickPlay(
        _ request: QuickPlayRequest,
        in session: CastSession,
        timeout: TimeInterval = 10
    ) async throws {
        _ = request
        _ = timeout
        _ = try await ensureAppReady(in: session)
        throw CastError.unsupportedFeature("YouTube app-specific quick play is not implemented yet")
    }

    // MARK: CastSessionController

    public func willUnregister(from _: CastSession) async {
        sessionStatus = .init()
    }

    public func handle(connectionEvent event: CastSession.ConnectionEvent, in _: CastSession) async {
        switch event {
        case .disconnected, .error:
            sessionStatus = .init()
        case .connected, .reconnected:
            break
        }
    }

    // MARK: CastSessionNamespaceHandler

    public func handle(event: CastSession.NamespaceEvent, in _: CastSession) async {
        guard event.namespace == .youtubeMDX else {
            return
        }

        guard let json = try? event.jsonObject(),
              json["type"] == .string("mdxSessionStatus"),
              case let .object(data)? = json["data"] else {
            return
        }

        let screenID: String?
        if case let .string(value)? = data["screenId"] {
            screenID = value
        } else {
            screenID = nil
        }

        sessionStatus = .init(screenID: screenID)
    }
}
