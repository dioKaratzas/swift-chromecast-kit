//
//  ChromecastKit
//  SPDX-License-Identifier: Apache-2.0
//  Copyright 2026 Dionysis Karatzas
//

import Foundation

/// App-specific controller for the YouTube Cast receiver using the YouTube MDX flow.
///
/// This controller uses two layers, matching the behavior used by `pychromecast`:
/// - Cast namespace messaging (`urn:x-cast:com.google.youtube.mdx`) to obtain the MDX `screenId`
/// - YouTube MDX web requests (lounge token + bind + queue actions) to start or enqueue playback
///
/// Use this controller to:
/// - request and observe `mdxSessionStatus`
/// - quick-play a YouTube video (play now or enqueue)
/// - perform queue-oriented YouTube actions (add/play-next/remove/clear)
public actor CastYouTubeController: CastAppController, CastQuickPlayController {
    // MARK: Public Models

    /// A high-level quick-play request for YouTube content.
    public struct QuickPlayRequest: Sendable, Hashable, Codable {
        public var videoID: String
        public var playlistID: String?
        public var enqueue: Bool
        public var startTime: TimeInterval

        public init(
            videoID: String,
            playlistID: String? = nil,
            enqueue: Bool = false,
            startTime: TimeInterval = 0
        ) {
            self.videoID = videoID
            self.playlistID = playlistID
            self.enqueue = enqueue
            self.startTime = startTime
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
    private let mdxWebSession: CastYouTubeMDXWebSession

    // MARK: Initialization

    /// Creates a YouTube MDX controller.
    ///
    /// - Parameters:
    ///   - launchPolicy: App launch behavior before namespace or MDX actions.
    ///   - requestTimeout: Default timeout for YouTube MDX web requests and status refresh waits.
    public init(
        launchPolicy: CastAppControllerLaunchPolicy = .launchIfNeeded,
        requestTimeout: TimeInterval = 10
    ) {
        self.launchPolicy = launchPolicy
        self.mdxWebSession = CastYouTubeMDXWebSession(
            httpClient: CastYouTubeURLSessionHTTPClient(),
            timeout: requestTimeout
        )
    }

    init(
        launchPolicy: CastAppControllerLaunchPolicy = .launchIfNeeded,
        requestTimeout: TimeInterval = 10,
        httpClient: any CastYouTubeHTTPClient
    ) {
        self.launchPolicy = launchPolicy
        self.mdxWebSession = CastYouTubeMDXWebSession(
            httpClient: httpClient,
            timeout: requestTimeout
        )
    }

    // MARK: Public API

    /// Returns the latest observed YouTube MDX session status.
    public func status() -> SessionStatus {
        sessionStatus
    }

    /// Requests YouTube MDX session status from the running YouTube receiver app.
    ///
    /// This sends `getMdxSessionStatus` on the YouTube MDX namespace.
    @discardableResult
    public func requestSessionStatus(in session: CastSession) async throws -> CastRequestID {
        try await send(
            payload: ["type": .string("getMdxSessionStatus")],
            in: session
        )
    }

    /// Requests `mdxSessionStatus` and waits for the next matching namespace event.
    ///
    /// This is the easiest way to populate the cached `screenID` before web-based MDX commands.
    @discardableResult
    public func refreshSessionStatus(
        in session: CastSession,
        timeout: TimeInterval = 10
    ) async throws -> SessionStatus {
        let events = await session.namespaceEvents(.youtubeMDX)
        _ = try await requestSessionStatus(in: session)

        let status = try await withThrowingTaskGroup(of: SessionStatus.self) { group in
            group.addTask {
                for await event in events {
                    if let status = Self.parseSessionStatus(from: event) {
                        return status
                    }
                }
                throw CastError.disconnected
            }

            if timeout > 0 {
                group.addTask {
                    try await CastTaskTiming.sleep(for: timeout)
                    throw CastError.timeout(operation: "YouTube mdxSessionStatus")
                }
            }

            guard let status = try await group.next() else {
                throw CastError.timeout(operation: "YouTube mdxSessionStatus")
            }
            group.cancelAll()
            return status
        }

        await applySessionStatus(status)
        return status
    }

    /// Plays a YouTube video immediately, replacing the current YouTube queue.
    ///
    /// This follows the same high-level MDX flow used by `pychromecast`/`casttube`.
    public func playVideo(
        _ videoID: String,
        playlistID: String? = nil,
        startTime: TimeInterval = 0,
        in session: CastSession,
        timeout: TimeInterval = 10
    ) async throws {
        _ = try await ensureScreenID(in: session, timeout: timeout)
        await mdxWebSession.setTimeout(timeout)
        try await mdxWebSession.playVideo(
            videoID: videoID,
            playlistID: playlistID,
            startTimeSeconds: Self.youtubeSecondsString(startTime)
        )
    }

    /// Adds a YouTube video to the end of the current YouTube queue.
    public func addToQueue(
        videoID: String,
        in session: CastSession,
        timeout: TimeInterval = 10
    ) async throws {
        _ = try await ensureScreenID(in: session, timeout: timeout)
        await mdxWebSession.setTimeout(timeout)
        try await mdxWebSession.addToQueue(videoID: videoID)
    }

    /// Inserts a YouTube video after the currently playing item.
    public func playNext(
        videoID: String,
        in session: CastSession,
        timeout: TimeInterval = 10
    ) async throws {
        _ = try await ensureScreenID(in: session, timeout: timeout)
        await mdxWebSession.setTimeout(timeout)
        try await mdxWebSession.playNext(videoID: videoID)
    }

    /// Removes a YouTube video from the current queue.
    public func removeVideo(
        videoID: String,
        in session: CastSession,
        timeout: TimeInterval = 10
    ) async throws {
        _ = try await ensureScreenID(in: session, timeout: timeout)
        await mdxWebSession.setTimeout(timeout)
        try await mdxWebSession.removeVideo(videoID: videoID)
    }

    /// Clears the current YouTube queue.
    public func clearQueue(
        in session: CastSession,
        timeout: TimeInterval = 10
    ) async throws {
        _ = try await ensureScreenID(in: session, timeout: timeout)
        await mdxWebSession.setTimeout(timeout)
        try await mdxWebSession.clearPlaylist()
    }

    /// Quick-play convenience API.
    ///
    /// When `enqueue == false`, this plays immediately (replacing the queue). When `enqueue == true`,
    /// the video is added to the end of the queue.
    public func quickPlay(
        _ request: QuickPlayRequest,
        in session: CastSession,
        timeout: TimeInterval = 10
    ) async throws {
        if request.enqueue {
            try await addToQueue(videoID: request.videoID, in: session, timeout: timeout)
        } else {
            try await playVideo(
                request.videoID,
                playlistID: request.playlistID,
                startTime: request.startTime,
                in: session,
                timeout: timeout
            )
        }
    }

    // MARK: CastSessionController

    public func willUnregister(from _: CastSession) async {
        await clearRuntimeState()
    }

    public func handle(connectionEvent event: CastSession.ConnectionEvent, in _: CastSession) async {
        switch event {
        case .disconnected, .error:
            await clearRuntimeState()
        case .connected, .reconnected:
            break
        }
    }

    // MARK: CastSessionNamespaceHandler

    public func handle(event: CastSession.NamespaceEvent, in _: CastSession) async {
        guard let status = Self.parseSessionStatus(from: event) else {
            return
        }
        await applySessionStatus(status)
    }

    // MARK: Private Helpers

    private func ensureScreenID(in session: CastSession, timeout: TimeInterval) async throws -> String {
        guard try await ensureAppReady(in: session) else {
            throw CastError.unsupportedNamespace("YouTube app is not ready for MDX messaging")
        }

        if let screenID = sessionStatus.screenID, screenID.isEmpty == false {
            return screenID
        }

        let refreshed = try await refreshSessionStatus(in: session, timeout: timeout)
        guard let screenID = refreshed.screenID, screenID.isEmpty == false else {
            throw CastError.invalidResponse("YouTube mdxSessionStatus did not include a screenId")
        }
        return screenID
    }

    private func applySessionStatus(_ newStatus: SessionStatus) async {
        sessionStatus = newStatus
        await mdxWebSession.setScreenID(newStatus.screenID)
    }

    private func clearRuntimeState() async {
        sessionStatus = .init()
        await mdxWebSession.setScreenID(nil)
    }

    private nonisolated static func parseSessionStatus(from event: CastSession.NamespaceEvent) -> SessionStatus? {
        guard event.namespace == .youtubeMDX else {
            return nil
        }

        guard let json = try? event.jsonObject(),
              json["type"] == .string("mdxSessionStatus"),
              case let .object(data)? = json["data"] else {
            return nil
        }

        let screenID: String?
        if case let .string(value)? = data["screenId"] {
            screenID = value
        } else {
            screenID = nil
        }

        return .init(screenID: screenID)
    }

    private nonisolated static func youtubeSecondsString(_ value: TimeInterval) -> String {
        guard value.isFinite else {
            return "0"
        }
        let clamped = max(value, 0)
        if clamped.rounded(.towardZero) == clamped {
            return String(Int(clamped))
        }
        return String(clamped)
    }
}
