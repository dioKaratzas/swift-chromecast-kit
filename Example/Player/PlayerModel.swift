import AVFoundation
import ChromecastKit
import Foundation
import Observation
import SystemConfiguration

@MainActor
@Observable
final class PlayerModel {
    struct SubtitleTrack: Identifiable, Hashable, Sendable {
        let id: UUID
        let fileURL: URL
        let displayName: String
        let cues: [SubtitleCue]
    }

    struct SubtitleRGBColor: Hashable, Sendable {
        var red: Double
        var green: Double
        var blue: Double

        init(red: Double, green: Double, blue: Double) {
            self.red = min(max(red, 0), 1)
            self.green = min(max(green, 0), 1)
            self.blue = min(max(blue, 0), 1)
        }

        var rgbHex: String {
            let r = Int((red * 255).rounded())
            let g = Int((green * 255).rounded())
            let b = Int((blue * 255).rounded())
            return String(format: "%02X%02X%02X", r, g, b)
        }

        static let white = SubtitleRGBColor(red: 1, green: 1, blue: 1)
        static let black = SubtitleRGBColor(red: 0, green: 0, blue: 0)
    }

    enum SubtitleEdgeStyleOption: String, CaseIterable, Identifiable, Sendable {
        case dropShadow
        case outline
        case none

        var id: Self {
            self
        }

        var title: String {
            switch self {
            case .dropShadow: "Drop Shadow"
            case .outline: "Outline"
            case .none: "None"
            }
        }

        var castEdgeType: CastTextTrackEdgeType {
            switch self {
            case .dropShadow: .dropShadow
            case .outline: .outline
            case .none: .none
            }
        }
    }

    struct LogEntry: Identifiable, Hashable {
        let id = UUID()
        let timestamp: Date
        let message: String
    }

    private enum Constant {
        static let subtitleTrackID: CastMediaTrackID = 1
    }

    private let discovery: CastDiscovery
    private let localFileServer = CastLocalFileServer()

    private var discoveryEventsTask: Task<Void, Never>?
    private var sessionConnectionEventsTask: Task<Void, Never>?
    private var sessionStateEventsTask: Task<Void, Never>?
    private var playerRefreshTask: Task<Void, Never>?
    private var lastCastStatusRefreshAt = Date.distantPast
    private var castStatusRefreshInFlight = false

    private(set) var discoveryState = CastDiscovery.State.stopped
    private(set) var devices = [CastDeviceDescriptor]()
    var selectedDeviceID: CastDeviceID?

    private(set) var session: CastSession?
    private(set) var sessionConnectionState = CastSession.ConnectionState.disconnected
    private(set) var sessionSnapshot = CastSession.StateSnapshot()

    let player = AVPlayer()
    private(set) var localMediaFileURL: URL?
    private(set) var subtitleTracks = [SubtitleTrack]()
    var selectedSubtitleTrackID: SubtitleTrack.ID?
    private(set) var currentSubtitleText = ""
    private(set) var localPlaybackPosition: TimeInterval = 0
    private(set) var localPlaybackDuration: TimeInterval = 1
    private(set) var castPlaybackPosition: TimeInterval = 0
    private(set) var castPlaybackDuration: TimeInterval = 1
    var scrubPosition: TimeInterval?
    var localVolumeLevel: Double = 1

    var localServerPublicHost = ""
    var localServerPortText = "8081"
    private(set) var localServerIsRunning = false
    private(set) var hostedMedia: CastLocalFileServer.HostedMedia?

    var castSeekDeltaSecondsText = "30"
    var castVolumeLevel = 0.5

    var subtitleFontScale = 1.0
    var subtitleForegroundColor = SubtitleRGBColor.white
    var subtitleBackgroundColor = SubtitleRGBColor.black
    var subtitleBackgroundOpacity = 0.66
    var subtitleEdgeStyle = SubtitleEdgeStyleOption.dropShadow

    var latestUserError: String?
    private(set) var logs = [LogEntry]()

    init(
        discovery: CastDiscovery = CastDiscovery(
            configuration: .init(
                includeGroups: true,
                browseTimeout: nil,
                enableSSDPFallback: true
            )
        )
    ) {
        self.discovery = discovery
    }

    var selectedDevice: CastDeviceDescriptor? {
        guard let selectedDeviceID else {
            return nil
        }
        return devices.first(where: { $0.id == selectedDeviceID })
    }

    var connectedDeviceID: CastDeviceID? {
        session?.device.id
    }

    var hasConnectedSession: Bool {
        switch sessionConnectionState {
        case .connected, .reconnecting:
            return true
        case .disconnected, .connecting, .failed:
            return false
        }
    }

    var hasLoadedLocalMedia: Bool {
        localMediaFileURL != nil
    }

    var hasActiveCastMediaSession: Bool {
        sessionSnapshot.mediaStatus?.mediaSessionID != nil
    }

    var isControllingChromecast: Bool {
        hasConnectedSession && hasActiveCastMediaSession
    }

    var isLocalPlaying: Bool {
        player.timeControlStatus == .playing
    }

    var isPrimaryPlaying: Bool {
        if isControllingChromecast {
            return sessionSnapshot.mediaStatus?.isPlaying == true
        }
        return isLocalPlaying
    }

    var primaryVolumeLevel: Double {
        if isControllingChromecast {
            return castVolumeLevel
        }
        return localVolumeLevel
    }

    var primaryPlaybackPosition: TimeInterval {
        if isControllingChromecast {
            return castPlaybackPosition
        }
        return localPlaybackPosition
    }

    var primaryPlaybackDuration: TimeInterval {
        if isControllingChromecast {
            return max(castPlaybackDuration, 1)
        }
        return max(localPlaybackDuration, 1)
    }

    var canCastCurrentMedia: Bool {
        hasLoadedLocalMedia && hasConnectedSession
    }

    var localMediaTitle: String {
        localMediaFileURL?.deletingPathExtension().lastPathComponent ?? "No media selected"
    }

    var selectedSubtitleTrack: SubtitleTrack? {
        guard let selectedSubtitleTrackID else {
            return nil
        }
        return subtitleTracks.first(where: { $0.id == selectedSubtitleTrackID })
    }

    var localSubtitleFileURL: URL? {
        selectedSubtitleTrack?.fileURL
    }

    var localSubtitleTitle: String {
        localSubtitleFileURL?.lastPathComponent ?? "None"
    }

    var hasSubtitle: Bool {
        localSubtitleFileURL != nil
    }

    var hasAnySubtitles: Bool {
        subtitleTracks.isEmpty == false
    }

    var canApplySubtitleStyleToChromecast: Bool {
        isControllingChromecast
    }

    var sessionStateLabel: String {
        switch sessionConnectionState {
        case .disconnected:
            return "Disconnected"
        case .connecting:
            return "Connecting"
        case .connected:
            return "Connected"
        case .reconnecting:
            return "Reconnecting"
        case .failed:
            return "Failed"
        }
    }

    var castPlayerStateLabel: String {
        sessionSnapshot.mediaStatus?.playerState.rawValue ?? "IDLE"
    }

    func onAppear() {
        startPlayerTimeObserverIfNeeded()
        startDiscoveryEventsIfNeeded()

        if case .stopped = discoveryState {
            startDiscoveryButtonTapped()
        }
    }

    func onDisappear() {
        playerRefreshTask?.cancel()
        playerRefreshTask = nil
    }

    func startDiscoveryButtonTapped() {
        Task { await startDiscovery() }
    }

    func refreshDiscoveryButtonTapped() {
        Task { await refreshDiscoverySnapshot() }
    }

    func stopDiscoveryButtonTapped() {
        Task { await stopDiscovery() }
    }

    func toggleConnectionButtonTapped() {
        Task {
            if connectedDeviceID == selectedDeviceID, hasConnectedSession {
                await disconnectSession()
            } else {
                await connectSelectedDevice()
            }
        }
    }

    func selectCastDevice(_ deviceID: CastDeviceID?) {
        Task {
            if deviceID == nil {
                selectedDeviceID = nil
                if hasConnectedSession {
                    await disconnectSession()
                }
                return
            }

            selectedDeviceID = deviceID
            await connectSelectedDevice()
            if canCastCurrentMedia {
                await castCurrentMedia()
            }
        }
    }

    func didPickMediaFile(_ url: URL) {
        localMediaFileURL = url
        localPlaybackPosition = 0
        localPlaybackDuration = 1
        scrubPosition = nil
        loadLocalMedia(url)
        appendLog("Selected media: \(url.lastPathComponent)")
    }

    func handleDroppedFiles(_ urls: [URL]) -> Bool {
        var handledAtLeastOne = false

        for url in urls {
            let ext = url.pathExtension.lowercased()
            if ext == "vtt" {
                didPickSubtitleFile(url)
                handledAtLeastOne = true
                continue
            }
            if isPlayableMediaFile(url) {
                didPickMediaFile(url)
                handledAtLeastOne = true
            }
        }

        if handledAtLeastOne == false {
            latestUserError = "Only media files and .vtt subtitles are supported."
        }
        return handledAtLeastOne
    }

    func didPickSubtitleFile(_ url: URL) {
        do {
            let cues = try WebVTTParser.parse(from: url)
            let normalizedURL = normalizedFileURL(url)
            let updatedTrack = SubtitleTrack(
                id: subtitleTrackID(for: normalizedURL) ?? UUID(),
                fileURL: normalizedURL,
                displayName: normalizedURL.deletingPathExtension().lastPathComponent,
                cues: cues
            )

            if let existingIndex = subtitleTracks.firstIndex(where: { $0.fileURL == normalizedURL }) {
                subtitleTracks[existingIndex] = updatedTrack
            } else {
                subtitleTracks.append(updatedTrack)
            }
            selectedSubtitleTrackID = updatedTrack.id
            updateSubtitle(for: localPlaybackPosition)
            appendLog("Loaded subtitle: \(updatedTrack.fileURL.lastPathComponent) (\(cues.count) cues)")
            Task { await syncSubtitleSelectionChange() }
        } catch {
            latestUserError = "Subtitle parse failed: \(errorMessage(error))"
            appendLog("Subtitle parse failed: \(errorMessage(error))")
        }
    }

    func clearSubtitleButtonTapped() {
        selectSubtitleTrack(nil)
    }

    func selectSubtitleTrack(_ trackID: SubtitleTrack.ID?) {
        if let trackID {
            guard subtitleTracks.contains(where: { $0.id == trackID }) else {
                return
            }
            selectedSubtitleTrackID = trackID
            appendLog("Selected subtitle: \(selectedSubtitleTrack?.fileURL.lastPathComponent ?? "Unknown")")
        } else {
            selectedSubtitleTrackID = nil
            appendLog("Subtitles off")
        }

        updateSubtitle(for: localPlaybackPosition)
        Task { await syncSubtitleSelectionChange() }
    }

    func removeSelectedSubtitleTrackButtonTapped() {
        guard let selectedSubtitleTrackID else {
            return
        }
        subtitleTracks.removeAll(where: { $0.id == selectedSubtitleTrackID })
        self.selectedSubtitleTrackID = subtitleTracks.first?.id
        updateSubtitle(for: localPlaybackPosition)
        appendLog("Removed selected subtitle track")
        Task { await syncSubtitleSelectionChange() }
    }

    func clearAllSubtitlesButtonTapped() {
        subtitleTracks.removeAll()
        selectedSubtitleTrackID = nil
        currentSubtitleText = ""
        appendLog("Cleared all subtitle tracks")
        Task { await syncSubtitleSelectionChange() }
    }

    func toggleLocalPlaybackButtonTapped() {
        guard player.currentItem != nil else {
            latestUserError = "Open a media file first."
            return
        }

        if isLocalPlaying {
            player.pause()
            appendLog("Local pause")
        } else {
            player.play()
            appendLog("Local play")
        }
    }

    func togglePrimaryPlaybackButtonTapped() {
        if isControllingChromecast {
            Task {
                if isPrimaryPlaying {
                    await runSessionAction("Cast pause") { session in
                        _ = try await session.media.pause()
                    }
                } else {
                    await runSessionAction("Cast play") { session in
                        _ = try await session.media.play()
                    }
                }
            }
            return
        }
        toggleLocalPlaybackButtonTapped()
    }

    func updateLocalVolume(_ level: Double) {
        let clamped = min(max(level, 0), 1)
        localVolumeLevel = clamped
        player.volume = Float(clamped)
    }

    func setPrimaryVolumeLevel(_ level: Double) {
        let clamped = min(max(level, 0), 1)
        if isControllingChromecast {
            castVolumeLevel = clamped
            return
        }
        updateLocalVolume(clamped)
    }

    func commitPrimaryVolumeChange() {
        if isControllingChromecast {
            castApplyVolumeButtonTapped()
        }
    }

    func stopLocalPlaybackButtonTapped() {
        guard player.currentItem != nil else {
            return
        }
        player.pause()
        seekLocal(to: 0)
        appendLog("Local stop")
    }

    func skipLocal(by seconds: TimeInterval) {
        guard player.currentItem != nil else {
            return
        }
        let nextPosition = min(max(localPlaybackPosition + seconds, 0), localPlaybackDuration)
        seekLocal(to: nextPosition)
    }

    func skipPrimary(by seconds: TimeInterval) {
        if isControllingChromecast {
            Task {
                let destination = max(primaryPlaybackPosition + seconds, 0)
                await seekCast(to: destination)
            }
            return
        }
        skipLocal(by: seconds)
    }

    func commitLocalScrub() {
        guard let scrubPosition else {
            return
        }
        seekLocal(to: scrubPosition)
        self.scrubPosition = nil
    }

    func commitPrimaryScrub() {
        guard let scrubPosition else {
            return
        }
        self.scrubPosition = nil

        if isControllingChromecast {
            Task { await seekCast(to: scrubPosition) }
            return
        }
        seekLocal(to: scrubPosition)
    }

    func castCurrentMediaButtonTapped() {
        Task { await castCurrentMedia() }
    }

    func castPlayButtonTapped() {
        Task {
            await runSessionAction("Cast play") { session in
                _ = try await session.media.play()
            }
        }
    }

    func castPauseButtonTapped() {
        Task {
            await runSessionAction("Cast pause") { session in
                _ = try await session.media.pause()
            }
        }
    }

    func castStopButtonTapped() {
        Task {
            await runSessionAction("Cast stop") { session in
                _ = try await session.media.stop()
            }
        }
    }

    func castSeekBackwardButtonTapped() {
        Task { await castSeek(byDirection: .backward) }
    }

    func castSeekForwardButtonTapped() {
        Task { await castSeek(byDirection: .forward) }
    }

    func castApplyVolumeButtonTapped() {
        let clamped = min(max(castVolumeLevel, 0), 1)
        castVolumeLevel = clamped

        Task {
            await runSessionAction("Cast volume \(Int(clamped * 100))%") { session in
                _ = try await session.receiver.setVolume(level: clamped)
            }
        }
    }

    func applySubtitleStyleToChromecastButtonTapped() {
        Task {
            await runSessionAction("Apply subtitle style") { session in
                _ = try await session.media.setTextTrackStyle(self.currentCastSubtitleStyle())
            }
        }
    }

    func formattedTime(_ time: TimeInterval) -> String {
        guard time.isFinite, time >= 0 else {
            return "00:00"
        }

        let totalSeconds = Int(time.rounded(.towardZero))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func loadLocalMedia(_ url: URL) {
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        player.volume = Float(localVolumeLevel)
        seekLocal(to: 0)
    }

    private func seekLocal(to position: TimeInterval) {
        let safePosition = min(max(position, 0), max(localPlaybackDuration, 0))
        let time = CMTime(seconds: safePosition, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        localPlaybackPosition = safePosition
        updateSubtitle(for: safePosition)
    }

    private func startPlayerTimeObserverIfNeeded() {
        guard playerRefreshTask == nil else {
            return
        }

        playerRefreshTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            while Task.isCancelled == false {
                self.syncLocalPlaybackState()
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
    }

    private func syncLocalPlaybackState() {
        let currentTime = player.currentTime().seconds
        localPlaybackPosition = max(currentTime.isFinite ? currentTime : 0, 0)

        if let durationSeconds = player.currentItem?.duration.seconds,
           durationSeconds.isFinite,
           durationSeconds > 0 {
            localPlaybackDuration = durationSeconds
        } else {
            localPlaybackDuration = max(localPlaybackPosition, 1)
        }

        updateSubtitle(for: localPlaybackPosition)
        syncCastPlaybackFromSnapshot()
        requestCastStatusRefreshIfNeeded()
    }

    private func updateSubtitle(for playbackTime: TimeInterval) {
        guard let cues = selectedSubtitleTrack?.cues, cues.isEmpty == false else {
            if currentSubtitleText.isEmpty == false {
                currentSubtitleText = ""
            }
            return
        }

        if let cue = cues.first(where: { $0.start <= playbackTime && playbackTime <= $0.end }) {
            if currentSubtitleText != cue.text {
                currentSubtitleText = cue.text
            }
        } else if currentSubtitleText.isEmpty == false {
            currentSubtitleText = ""
        }
    }

    private func startDiscoveryEventsIfNeeded() {
        guard discoveryEventsTask == nil else {
            return
        }

        discoveryEventsTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            let stream = await self.discovery.events()
            for await event in stream {
                await self.handleDiscoveryEvent(event)
            }
        }
    }

    private func startDiscovery() async {
        startDiscoveryEventsIfNeeded()
        do {
            try await discovery.start()
            await refreshDiscoverySnapshot()
            appendLog("Discovery started")
        } catch {
            latestUserError = errorMessage(error)
            appendLog("Discovery start failed: \(errorMessage(error))")
            await refreshDiscoverySnapshot()
        }
    }

    private func stopDiscovery() async {
        await discovery.stop()
        await refreshDiscoverySnapshot()
        appendLog("Discovery stopped")
    }

    private func refreshDiscoverySnapshot() async {
        devices = await discovery.devices()
        discoveryState = await discovery.state()

        if selectedDeviceID == nil {
            selectedDeviceID = devices.first?.id
        } else if let selectedDeviceID,
                  devices.contains(where: { $0.id == selectedDeviceID }) == false {
            self.selectedDeviceID = devices.first?.id
        }
    }

    private func handleDiscoveryEvent(_ event: CastDiscovery.Event) async {
        switch event {
        case .started:
            discoveryState = .running
            latestUserError = nil
        case .stopped:
            discoveryState = .stopped
        case let .deviceUpserted(device, isNew):
            await refreshDiscoverySnapshot()
            appendLog("\(isNew ? "Found" : "Updated") device: \(device.friendlyName)")
        case .deviceRemoved:
            await refreshDiscoverySnapshot()
        case let .error(error):
            discoveryState = .failed(error)
            latestUserError = errorMessage(error)
            appendLog("Discovery error: \(errorMessage(error))")
        }
    }

    private func connectSelectedDevice() async {
        guard let selectedDevice else {
            latestUserError = "Select a Chromecast first."
            return
        }

        if let session, session.device.id != selectedDevice.id {
            await session.disconnect(reason: .requested)
            clearSessionState()
        }

        if session == nil {
            let newSession = CastSession(device: selectedDevice)
            session = newSession
            attachSessionStreams(to: newSession)
        }

        guard let session else {
            return
        }

        do {
            try await session.connect()
            sessionConnectionState = await session.connectionState()
            sessionSnapshot = await session.snapshot()
            syncCastVolumeFromSnapshot()
            latestUserError = nil
            appendLog("Connected to \(selectedDevice.friendlyName)")
        } catch {
            latestUserError = errorMessage(error)
            sessionConnectionState = await session.connectionState()
            appendLog("Connect failed: \(errorMessage(error))")
        }
    }

    private func disconnectSession() async {
        guard let session else {
            return
        }
        await session.disconnect(reason: .requested)
        appendLog("Disconnect requested")
    }

    private func attachSessionStreams(to session: CastSession) {
        sessionConnectionEventsTask?.cancel()
        sessionStateEventsTask?.cancel()

        sessionConnectionEventsTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            let stream = await session.connectionEvents()
            for await event in stream {
                self.handleConnectionEvent(event)
            }
        }

        sessionStateEventsTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            let stream = await session.stateEvents()
            for await event in stream {
                self.handleStateEvent(event)
            }
        }

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            self.sessionConnectionState = await session.connectionState()
            self.sessionSnapshot = await session.snapshot()
            self.syncCastVolumeFromSnapshot()
        }
    }

    private func clearSessionState() {
        sessionConnectionEventsTask?.cancel()
        sessionConnectionEventsTask = nil
        sessionStateEventsTask?.cancel()
        sessionStateEventsTask = nil

        session = nil
        sessionConnectionState = .disconnected
        sessionSnapshot = .init()
        castVolumeLevel = 0.5
        castPlaybackPosition = 0
        castPlaybackDuration = 1
    }

    private func handleConnectionEvent(_ event: CastSession.ConnectionEvent) {
        switch event {
        case .connected:
            sessionConnectionState = .connected
            appendLog("Session connected")
        case .reconnected:
            sessionConnectionState = .connected
            appendLog("Session reconnected")
        case let .disconnected(reason):
            sessionConnectionState = .disconnected
            appendLog("Session disconnected\(reason.map { " (\($0.rawValue))" } ?? "")")
        case let .error(error):
            sessionConnectionState = .failed(error)
            latestUserError = errorMessage(error)
            appendLog("Session error: \(errorMessage(error))")
        }
    }

    private func handleStateEvent(_ event: CastSession.StateEvent) {
        switch event {
        case let .receiverStatusUpdated(status):
            sessionSnapshot = .init(
                receiverStatus: status,
                mediaStatus: sessionSnapshot.mediaStatus,
                multizoneStatus: sessionSnapshot.multizoneStatus
            )
            syncCastVolumeFromSnapshot()
        case let .mediaStatusUpdated(status):
            sessionSnapshot = .init(
                receiverStatus: sessionSnapshot.receiverStatus,
                mediaStatus: status,
                multizoneStatus: sessionSnapshot.multizoneStatus
            )
            syncCastPlaybackFromSnapshot()
        case let .multizoneStatusUpdated(status):
            sessionSnapshot = .init(
                receiverStatus: sessionSnapshot.receiverStatus,
                mediaStatus: sessionSnapshot.mediaStatus,
                multizoneStatus: status
            )
        }
    }

    private func syncCastVolumeFromSnapshot() {
        guard let volume = sessionSnapshot.receiverStatus?.volume else {
            return
        }
        castVolumeLevel = volume.level
    }

    private func syncCastPlaybackFromSnapshot() {
        guard let media = sessionSnapshot.mediaStatus else {
            castPlaybackPosition = 0
            castPlaybackDuration = max(localPlaybackDuration, 1)
            return
        }

        castPlaybackPosition = max(media.adjustedCurrentTime, 0)
        if let duration = media.duration, duration > 0, duration.isFinite {
            castPlaybackDuration = duration
        } else if localPlaybackDuration > 1 {
            castPlaybackDuration = localPlaybackDuration
        } else {
            castPlaybackDuration = max(castPlaybackPosition, 1)
        }
    }

    private func castCurrentMedia() async {
        guard let localMediaFileURL else {
            latestUserError = "Open a local media file first."
            return
        }

        guard let session else {
            latestUserError = "Connect to a Chromecast first."
            return
        }

        do {
            try await startLocalServerIfNeeded()
            let hostedMedia = try await localFileServer.host(
                videoFileURL: localMediaFileURL,
                subtitleFileURL: localSubtitleFileURL
            )
            self.hostedMedia = hostedMedia
            localServerIsRunning = true

            try await ensureDefaultMediaReceiverReady(session: session)

            let item = makeCastMediaItem(hostedMedia: hostedMedia, sourceMediaURL: localMediaFileURL)
            let options = makeCastLoadOptions(includeSubtitle: hostedMedia.subtitleURL != nil)
            _ = try await session.media.load(item, options: options)

            player.pause()
            appendLog("Cast load: \(localMediaFileURL.lastPathComponent)")
        } catch {
            latestUserError = errorMessage(error)
            appendLog("Cast load failed: \(errorMessage(error))")
        }
    }

    private func castSeek(byDirection direction: SeekDirection) async {
        guard let deltaSeconds = parsedCastSeekDeltaSeconds() else {
            latestUserError = "Seek seconds must be a positive number."
            return
        }

        guard let currentMedia = sessionSnapshot.mediaStatus else {
            latestUserError = "Load media on Chromecast first."
            return
        }

        let sign: Double = direction == .forward ? 1 : -1
        let destination = max(currentMedia.adjustedCurrentTime + sign * deltaSeconds, 0)
        await seekCast(to: destination)
    }

    private func seekCast(to destination: TimeInterval) async {
        await runSessionAction("Cast seek to \(formattedTime(destination))") { session in
            _ = try await session.media.seek(to: destination)
            _ = try await session.media.getStatus()
        }
    }

    private func requestCastStatusRefreshIfNeeded() {
        guard isControllingChromecast else {
            return
        }

        let now = Date()
        guard now.timeIntervalSince(lastCastStatusRefreshAt) >= 1.0 else {
            return
        }
        guard castStatusRefreshInFlight == false else {
            return
        }

        lastCastStatusRefreshAt = now
        castStatusRefreshInFlight = true

        Task {
            defer { castStatusRefreshInFlight = false }
            guard let session else {
                return
            }
            do {
                _ = try await session.media.getStatus()
            } catch {
                // Ignore periodic polling errors; event stream remains the primary source of truth.
            }
        }
    }

    private enum SeekDirection {
        case backward
        case forward
    }

    private func parsedCastSeekDeltaSeconds() -> TimeInterval? {
        let trimmed = castSeekDeltaSecondsText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Double(trimmed), value > 0 else {
            return nil
        }
        return value
    }

    private func runSessionAction(
        _ actionName: String,
        action: @escaping @Sendable (CastSession) async throws -> Void
    ) async {
        guard let session else {
            latestUserError = "Connect to a Chromecast first."
            return
        }

        do {
            try await action(session)
            latestUserError = nil
            appendLog(actionName)
        } catch {
            latestUserError = errorMessage(error)
            appendLog("\(actionName) failed: \(errorMessage(error))")
        }
    }

    private func startLocalServerIfNeeded() async throws {
        if localServerIsRunning {
            return
        }

        let host = try resolvedLocalServerHost()
        let port = try resolvedLocalServerPort()
        let baseURL = try await localFileServer.start(publicHost: host, port: port)

        localServerPublicHost = host
        localServerIsRunning = true
        appendLog("Local server: \(baseURL.absoluteString)")
    }

    private func refreshHostedSubtitleIfNeeded() async {
        guard localServerIsRunning, hostedMedia != nil else {
            return
        }

        do {
            hostedMedia = try await localFileServer.updateSubtitleFile(localSubtitleFileURL)
            if let subtitleURL = hostedMedia?.subtitleURL {
                appendLog("Updated hosted subtitle: \(subtitleURL.lastPathComponent)")
            } else {
                appendLog("Removed hosted subtitle")
            }
        } catch {
            latestUserError = errorMessage(error)
            appendLog("Hosted subtitle update failed: \(errorMessage(error))")
        }
    }

    private func syncSubtitleSelectionChange() async {
        await refreshHostedSubtitleIfNeeded()
        if isControllingChromecast, hasLoadedLocalMedia {
            await castCurrentMedia()
            return
        }
        latestUserError = nil
    }

    private func subtitleTrackID(for url: URL) -> UUID? {
        subtitleTracks.first(where: { $0.fileURL == url })?.id
    }

    private func normalizedFileURL(_ url: URL) -> URL {
        url.resolvingSymlinksInPath().standardizedFileURL
    }

    private func currentCastSubtitleStyle() -> CastTextTrackStyle {
        CastTextTrackStyle(
            backgroundColorRGBAHex: rgbaHex(color: subtitleBackgroundColor, opacity: subtitleBackgroundOpacity),
            foregroundColorRGBAHex: rgbaHex(color: subtitleForegroundColor, opacity: 1),
            edgeType: subtitleEdgeStyle.castEdgeType,
            edgeColorRGBAHex: "#000000FF",
            fontScale: subtitleFontScale,
            fontGenericFamily: .sansSerif
        )
    }

    private func rgbaHex(color: SubtitleRGBColor, opacity: Double) -> String {
        let clamped = min(max(opacity, 0), 1)
        let alpha = Int((clamped * 255).rounded())
        return "#\(color.rgbHex)\(String(format: "%02X", alpha))"
    }

    private func resolvedLocalServerHost() throws -> String {
        let typedHost = localServerPublicHost.trimmingCharacters(in: .whitespacesAndNewlines)
        if typedHost.isEmpty == false {
            return typedHost
        }

        if let detectedHost = detectLocalIPv4Address() {
            return detectedHost
        }

        throw CastError.invalidArgument("Enter your Mac's LAN IP address for casting local files")
    }

    private func resolvedLocalServerPort() throws -> UInt16 {
        let trimmed = localServerPortText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let port = Int(trimmed), (1 ... 65535).contains(port) else {
            throw CastError.invalidArgument("Port must be between 1 and 65535")
        }
        return UInt16(port)
    }

    private func ensureDefaultMediaReceiverReady(session: CastSession) async throws {
        _ = try await session.launchDefaultMediaReceiver()
        let app = try await session.waitForApp(.defaultMediaReceiver, timeout: 6)
        if app == nil {
            appendLog("Default Media Receiver readiness timed out; attempting load")
        }
    }

    private func makeCastMediaItem(
        hostedMedia: CastLocalFileServer.HostedMedia,
        sourceMediaURL: URL
    ) -> CastMediaItem {
        let textTracks = makeCastTextTracks(for: hostedMedia.subtitleURL)
        let contentType = inferredContentType(for: sourceMediaURL)
        let subtitle = selectedSubtitleTrack?.displayName ?? "Local file"

        return CastMediaItem(
            contentURL: hostedMedia.videoURL,
            contentType: contentType,
            streamType: .buffered,
            metadata: .generic(
                title: sourceMediaURL.deletingPathExtension().lastPathComponent,
                subtitle: subtitle,
                images: []
            ),
            textTracks: textTracks,
            textTrackStyle: currentCastSubtitleStyle()
        )
    }

    private func makeCastLoadOptions(includeSubtitle: Bool) -> CastMediaController.LoadOptions {
        let activeTrackIDs = includeSubtitle ? [Constant.subtitleTrackID] : []

        let startTime: TimeInterval?
        let resumePosition = isControllingChromecast ? castPlaybackPosition : localPlaybackPosition
        if resumePosition > 0, resumePosition.isFinite {
            startTime = resumePosition
        } else {
            startTime = nil
        }

        return .init(
            autoplay: true,
            startTime: startTime,
            activeTextTrackIDs: activeTrackIDs
        )
    }

    private func makeCastTextTracks(for subtitleURL: URL?) -> [CastTextTrack] {
        guard let subtitleURL else {
            return []
        }

        return [
            .subtitleVTT(
                id: Constant.subtitleTrackID,
                name: selectedSubtitleTrack?.displayName ?? "Subtitle",
                languageCode: "en",
                url: subtitleURL
            )
        ]
    }

    private func inferredContentType(for mediaURL: URL) -> String {
        switch mediaURL.pathExtension.lowercased() {
        case "mp4", "m4v":
            return "video/mp4"
        case "mov":
            return "video/quicktime"
        case "webm":
            return "video/webm"
        case "mp3":
            return "audio/mpeg"
        case "m4a":
            return "audio/mp4"
        case "aac":
            return "audio/aac"
        case "wav":
            return "audio/wav"
        default:
            return "application/octet-stream"
        }
    }

    private func isPlayableMediaFile(_ url: URL) -> Bool {
        switch url.pathExtension.lowercased() {
        case "mp4", "m4v", "mov", "webm", "mp3", "m4a", "aac", "wav":
            return true
        default:
            return false
        }
    }

    private func detectLocalIPv4Address() -> String? {
        var ifaddrPointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPointer) == 0, let first = ifaddrPointer else {
            return nil
        }
        defer { freeifaddrs(ifaddrPointer) }

        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let current = pointer {
            let interface = current.pointee
            pointer = interface.ifa_next

            let flags = Int32(interface.ifa_flags)
            let isUp = (flags & IFF_UP) != 0
            let isLoopback = (flags & IFF_LOOPBACK) != 0
            guard isUp, isLoopback == false else {
                continue
            }

            guard let address = interface.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_INET) else {
                continue
            }

            var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                address,
                socklen_t(address.pointee.sa_len),
                &hostBuffer,
                socklen_t(hostBuffer.count),
                nil,
                0,
                NI_NUMERICHOST
            )

            if result == 0 {
                let candidate = String(cString: hostBuffer)
                if candidate.hasPrefix("169.254.") == false {
                    return candidate
                }
            }
        }

        return nil
    }

    private func appendLog(_ message: String) {
        logs.insert(.init(timestamp: .now, message: message), at: 0)
        if logs.count > 200 {
            logs.removeLast(logs.count - 200)
        }
    }

    private func errorMessage(_ error: any Error) -> String {
        if let castError = error as? CastError {
            return String(describing: castError)
        }
        return String(describing: error)
    }
}
