//
//  ChromecastKit
//  Swift package for Google Cast (Chromecast).
//

import AppKit
import Foundation
import Observation
import ChromecastKit
import SystemConfiguration

@MainActor
@Observable
final class ShowcaseAppModel {
    enum DetailTab: String, CaseIterable, Identifiable {
        case overview
        case receiver
        case media
        case localFiles
        case namespace

        var id: Self {
            self
        }

        var title: String {
            switch self {
            case .overview: "Session"
            case .receiver: "Receiver"
            case .media: "Media"
            case .localFiles: "Local Files"
            case .namespace: "Namespaces"
            }
        }

        var systemImage: String {
            switch self {
            case .overview: "dot.radiowaves.left.and.right"
            case .receiver: "tv"
            case .media: "play.rectangle"
            case .localFiles: "externaldrive"
            case .namespace: "chevron.left.forwardslash.chevron.right"
            }
        }
    }

    enum NamespaceTargetChoice: String, CaseIterable, Identifiable {
        case currentApplication
        case platform
        case transport

        var id: Self {
            self
        }

        var title: String {
            switch self {
            case .currentApplication: "Current App"
            case .platform: "Platform"
            case .transport: "Transport"
            }
        }
    }

    enum SubtitleStylePreset: String, CaseIterable, Identifiable {
        case none
        case highContrast
        case karaoke

        var id: Self {
            self
        }

        var title: String {
            switch self {
            case .none: "None"
            case .highContrast: "High Contrast"
            case .karaoke: "Large Yellow"
            }
        }

        var castStyle: CastTextTrackStyle? {
            switch self {
            case .none:
                nil
            case .highContrast:
                .init(
                    backgroundColorRGBAHex: "#000000AA",
                    foregroundColorRGBAHex: "#FFFFFFFF",
                    edgeType: .dropShadow,
                    edgeColorRGBAHex: "#000000FF",
                    fontScale: 1,
                    fontGenericFamily: .sansSerif
                )
            case .karaoke:
                .init(
                    backgroundColorRGBAHex: "#00000066",
                    foregroundColorRGBAHex: "#FFFF00FF",
                    edgeType: .outline,
                    edgeColorRGBAHex: "#000000FF",
                    fontScale: 1.25,
                    fontStyle: .bold,
                    fontGenericFamily: .sansSerif
                )
            }
        }
    }

    struct LogEntry: Identifiable, Hashable {
        let id = UUID()
        let timestamp: Date
        let category: String
        let message: String
    }

    struct NamespaceLogEntry: Identifiable, Hashable {
        let id = UUID()
        let timestamp: Date
        let namespace: String
        let sourceID: String
        let destinationID: String
        let summary: String
        let payloadPreview: String
        let isBinary: Bool
    }

    private let discovery: CastDiscovery
    private let localFileServer = CastLocalFileServer()
    private let youtubeController = CastYouTubeController()

    private var discoveryEventsTask: Task<Void, Never>?
    private var sessionConnectionEventsTask: Task<Void, Never>?
    private var sessionStateEventsTask: Task<Void, Never>?
    private var sessionNamespaceEventsTask: Task<Void, Never>?
    private var autoRefreshMediaTimeTask: Task<Void, Never>?

    private(set) var discoveryState = CastDiscovery.State.stopped
    private(set) var devices = [CastDeviceDescriptor]()
    var selectedDeviceID: CastDeviceID?
    var selectedTab = DetailTab.overview

    private(set) var session: CastSession?
    private(set) var sessionConnectionState = CastSession.ConnectionState.disconnected
    private(set) var sessionSnapshot = CastSession.StateSnapshot()

    var discoveryLog = [LogEntry]()
    var sessionLog = [LogEntry]()
    var namespaceLog = [NamespaceLogEntry]()

    var latestUserError: String?
    var isBusyConnecting = false

    var sessionConfiguration = CastSession.Configuration(
        connectTimeout: 10,
        commandTimeout: 10,
        heartbeatInterval: 5,
        autoReconnect: true,
        reconnectRetryDelay: 1
    )

    // Receiver controls
    var receiverVolumeLevel = 0.5
    var receiverMuted = false

    // Media playground form
    var mediaURLString = "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4"
    var mediaContentType = "video/mp4"
    var mediaTitle = "Big Buck Bunny"
    var mediaSubtitle = "ChromecastKit Example"
    var mediaCoverURLString = "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/images/BigBuckBunny.jpg"
    var mediaSubtitleURLString = ""
    var mediaSubtitleName = "English"
    var mediaSubtitleLanguageCode = "en"
    var mediaSubtitleTrackIDText = "1"
    var mediaAutoplay = true
    var mediaStartTimeText = ""
    var mediaSeekSecondsText = "30"
    var mediaPlaybackRateText = "1.0"
    var subtitleStylePreset = SubtitleStylePreset.none

    // YouTube MDX demo
    var youtubeVideoID = "dQw4w9WgXcQ"
    var youtubePlaylistID = ""
    var youtubeStartTimeText = "0"
    var youtubeEnqueue = false
    private(set) var youtubeSessionStatus = CastYouTubeController.SessionStatus()

    // Namespace console
    var namespaceFilterString = "urn:x-cast:com.example.echo"
    var namespaceTargetChoice = NamespaceTargetChoice.currentApplication
    var namespaceTransportTargetID = ""
    var namespacePayloadText = "{\n  \"type\": \"PING\",\n  \"hello\": \"world\"\n}"
    var namespaceReplyText = ""

    // Local file demo (Swifter-backed local hosting)
    var localVideoFileURL: URL?
    var localSubtitleFileURL: URL?
    var localServerPublicHost = ""
    var localServerPortText = "8081"
    private(set) var localHostedMedia: CastLocalFileServer.HostedMedia?
    private(set) var localServerIsRunning = false

    // Manual host fallback (when mDNS is unavailable)
    var manualHostAddress = ""
    var manualHostPortText = "8009"
    var manualHostFriendlyName = ""

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

    var currentApp: CastRunningApp? {
        sessionSnapshot.receiverStatus?.app
    }

    var hasConnectedSession: Bool {
        if case .connected = sessionConnectionState {
            return true
        }
        if case .reconnecting = sessionConnectionState {
            return true
        }
        return false
    }

    var hasActiveMediaSession: Bool {
        sessionSnapshot.mediaStatus?.mediaSessionID != nil
    }

    var showsNetflixCapabilityNote: Bool {
        guard let app = currentApp else {
            return false
        }
        return app.displayName.localizedCaseInsensitiveContains("netflix")
    }

    var canConnectSelectedDevice: Bool {
        selectedDevice != nil && isBusyConnecting == false
    }

    func onAppear() {
        startDiscoveryEventsIfNeeded()
        startMediaTimeRefreshIfNeeded()

        if case .stopped = discoveryState {
            startDiscoveryButtonTapped()
        }
    }

    // MARK: Discovery Actions

    func startDiscoveryButtonTapped() {
        Task { await startDiscovery() }
    }

    func stopDiscoveryButtonTapped() {
        Task { await stopDiscovery() }
    }

    func refreshDiscoverySnapshotButtonTapped() {
        Task { await refreshDiscoverySnapshot() }
    }

    func clearDiscoveryDevicesButtonTapped() {
        Task { await clearDiscoveryDevices() }
    }

    func addManualHostButtonTapped() {
        Task { await addManualHost() }
    }

    func selectedDeviceChanged(_ deviceID: CastDeviceID?) {
        selectedDeviceID = deviceID
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
            appendDiscoveryLog("Discovery started")
        } catch {
            let message = errorMessage(error)
            latestUserError = message
            appendDiscoveryLog("Start failed: \(message)")
            await refreshDiscoverySnapshot()
        }
    }

    private func stopDiscovery() async {
        await discovery.stop()
        await refreshDiscoverySnapshot()
        appendDiscoveryLog("Discovery stopped")
    }

    private func refreshDiscoverySnapshot() async {
        devices = await discovery.devices()
        discoveryState = await discovery.state()
        if selectedDeviceID == nil {
            selectedDeviceID = devices.first?.id
        } else if let selectedDeviceID, devices.contains(where: { $0.id == selectedDeviceID }) == false {
            self.selectedDeviceID = devices.first?.id
        }
    }

    private func clearDiscoveryDevices() async {
        await discovery.clearDevices()
        await refreshDiscoverySnapshot()
        appendDiscoveryLog("Cleared discovery snapshot")
    }

    private func addManualHost() async {
        let host = manualHostAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard host.isEmpty == false else {
            latestUserError = "Enter a host/IP address."
            return
        }

        let port = Int(manualHostPortText) ?? 8009
        guard (1 ... 65535).contains(port) else {
            latestUserError = "Port must be between 1 and 65535."
            return
        }

        let friendlyName = manualHostFriendlyName.trimmingCharacters(in: .whitespacesAndNewlines)
        let descriptor = await discovery.addKnownHost(
            host: host,
            port: port,
            friendlyName: friendlyName.isEmpty ? nil : friendlyName
        )
        await refreshDiscoverySnapshot()
        selectedDeviceID = descriptor.id
        appendDiscoveryLog("Added manual host: \(descriptor.friendlyName) @ \(descriptor.host):\(descriptor.port)")
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
            appendDiscoveryLog("\(isNew ? "Found" : "Updated"): \(device.friendlyName) @ \(device.host):\(device.port)")
        case let .deviceRemoved(id):
            await refreshDiscoverySnapshot()
            appendDiscoveryLog("Removed: \(id.rawValue)")
        case let .error(error):
            discoveryState = .failed(error)
            latestUserError = errorMessage(error)
            appendDiscoveryLog("Error: \(errorMessage(error))")
        }
    }

    // MARK: Session Actions

    func connectSelectedDeviceButtonTapped() {
        Task { await connectSelectedDevice() }
    }

    func disconnectSessionButtonTapped() {
        Task { await disconnectSession() }
    }

    func toggleSelectedDeviceConnectionButtonTapped() {
        Task {
            if connectedDeviceID == selectedDeviceID, hasConnectedSession {
                await disconnectSession()
            } else {
                await connectSelectedDevice()
            }
        }
    }

    func reconnectSessionButtonTapped() {
        Task { await reconnectSession() }
    }

    func refreshSessionSnapshotButtonTapped() {
        Task { await refreshSessionSnapshot() }
    }

    private func connectSelectedDevice() async {
        guard let device = selectedDevice else {
            latestUserError = "Select a Chromecast first."
            return
        }

        isBusyConnecting = true
        defer { isBusyConnecting = false }

        if let session, session.device.id != device.id {
            await session.disconnect(reason: .requested)
            clearSessionStateForNewDevice()
        }

        if session == nil || session?.device.id != device.id {
            let newSession = CastSession(device: device, configuration: sessionConfiguration)
            self.session = newSession
            attachSessionStreams(to: newSession)
        }

        guard let session else {
            return
        }

        do {
            try await session.connect()
            sessionConnectionState = await session.connectionState()
            sessionSnapshot = await session.snapshot()
            syncReceiverControlsFromSnapshot()
            appendSessionLog("Connected to \(device.friendlyName)")
        } catch {
            let message = errorMessage(error)
            latestUserError = message
            appendSessionLog("Connect failed: \(message)")
            sessionConnectionState = await session.connectionState()
        }
    }

    private func disconnectSession() async {
        guard let session else {
            return
        }
        await session.disconnect(reason: .requested)
        appendSessionLog("Disconnect requested")
    }

    private func reconnectSession() async {
        guard let session else {
            return
        }
        do {
            try await session.reconnect()
            sessionConnectionState = await session.connectionState()
            sessionSnapshot = await session.snapshot()
            syncReceiverControlsFromSnapshot()
            appendSessionLog("Reconnect requested")
        } catch {
            latestUserError = errorMessage(error)
            appendSessionLog("Reconnect failed: \(errorMessage(error))")
        }
    }

    private func refreshSessionSnapshot() async {
        guard let session else {
            return
        }
        sessionConnectionState = await session.connectionState()
        sessionSnapshot = await session.snapshot()
        syncReceiverControlsFromSnapshot()
        appendSessionLog("Snapshot refreshed")
    }

    private func attachSessionStreams(to session: CastSession) {
        sessionConnectionEventsTask?.cancel()
        sessionStateEventsTask?.cancel()
        sessionNamespaceEventsTask?.cancel()

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

        sessionNamespaceEventsTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            let stream = await session.namespaceEvents()
            for await event in stream {
                self.handleNamespaceEvent(event)
            }
        }

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            self.sessionConnectionState = await session.connectionState()
            self.sessionSnapshot = await session.snapshot()
            self.syncReceiverControlsFromSnapshot()
        }
    }

    private func clearSessionStateForNewDevice() {
        sessionConnectionEventsTask?.cancel()
        sessionConnectionEventsTask = nil
        sessionStateEventsTask?.cancel()
        sessionStateEventsTask = nil
        sessionNamespaceEventsTask?.cancel()
        sessionNamespaceEventsTask = nil

        session = nil
        sessionConnectionState = .disconnected
        sessionSnapshot = .init()
        namespaceReplyText = ""
        namespaceLog.removeAll()
    }

    private func handleConnectionEvent(_ event: CastSession.ConnectionEvent) {
        switch event {
        case .connected:
            sessionConnectionState = .connected
            appendSessionLog("Connected")
        case .reconnected:
            sessionConnectionState = .connected
            appendSessionLog("Reconnected")
        case let .disconnected(reason):
            sessionConnectionState = .disconnected
            appendSessionLog("Disconnected\(reason.map { " (\($0.rawValue))" } ?? "")")
        case let .error(error):
            sessionConnectionState = .failed(error)
            latestUserError = errorMessage(error)
            appendSessionLog("Error: \(errorMessage(error))")
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
            syncReceiverControlsFromSnapshot()
            if let app = status?.app {
                appendSessionLog("Receiver app: \(app.displayName) (\(app.appID.rawValue))")
            }
        case let .mediaStatusUpdated(status):
            sessionSnapshot = .init(
                receiverStatus: sessionSnapshot.receiverStatus,
                mediaStatus: status,
                multizoneStatus: sessionSnapshot.multizoneStatus
            )
            if let status {
                appendSessionLog("Media status: \(status.playerState.rawValue) t=\(Int(status.currentTime))s")
            }
        case let .multizoneStatusUpdated(status):
            sessionSnapshot = .init(
                receiverStatus: sessionSnapshot.receiverStatus,
                mediaStatus: sessionSnapshot.mediaStatus,
                multizoneStatus: status
            )
            if let status {
                appendSessionLog("Multizone: \(status.members.count) members, \(status.castingGroups.count) groups")
            }
        }
    }

    private func handleNamespaceEvent(_ event: CastSession.NamespaceEvent) {
        let preview: String
        let summary: String
        let isBinary: Bool

        switch event.payload {
        case let .utf8(text):
            preview = String(text.prefix(300))
            summary = "UTF-8"
            isBinary = false
        case let .binary(data):
            preview = data.prefix(48).map { String(format: "%02X", $0) }.joined(separator: " ")
            summary = "Binary (\(data.count) bytes)"
            isBinary = true
        }

        namespaceLog.insert(
            .init(
                timestamp: .now,
                namespace: event.namespace.rawValue,
                sourceID: event.sourceID,
                destinationID: event.destinationID,
                summary: summary,
                payloadPreview: preview,
                isBinary: isBinary
            ),
            at: 0
        )
        trimNamespaceLog()
    }

    private func syncReceiverControlsFromSnapshot() {
        guard let receiver = sessionSnapshot.receiverStatus else {
            return
        }
        receiverVolumeLevel = receiver.volume.level
        receiverMuted = receiver.volume.muted
    }

    private func startMediaTimeRefreshIfNeeded() {
        guard autoRefreshMediaTimeTask == nil else {
            return
        }
        autoRefreshMediaTimeTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            while Task.isCancelled == false {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                // Trigger UI refresh for adjustedCurrentTime-derived displays.
                if self.sessionSnapshot.mediaStatus?.isPlaying == true {
                    self.sessionSnapshot = .init(
                        receiverStatus: self.sessionSnapshot.receiverStatus,
                        mediaStatus: self.sessionSnapshot.mediaStatus,
                        multizoneStatus: self.sessionSnapshot.multizoneStatus
                    )
                }
            }
        }
    }

    // MARK: Receiver Controls

    func receiverGetStatusButtonTapped() {
        Task { await receiverGetStatus() }
    }

    func receiverLaunchDefaultMediaReceiverButtonTapped() {
        Task { await receiverLaunchDefaultMediaReceiver() }
    }

    func receiverStopCurrentAppButtonTapped() {
        Task { await receiverStopCurrentApp() }
    }

    func receiverApplyVolumeButtonTapped() {
        Task { await receiverApplyVolume() }
    }

    func receiverSetMutedButtonTapped() {
        Task { await receiverSetMuted() }
    }

    func multizoneGetStatusButtonTapped() {
        Task { await multizoneGetStatus() }
    }

    func multizoneGetCastingGroupsButtonTapped() {
        Task { await multizoneGetCastingGroups() }
    }

    private func receiverGetStatus() async {
        await runSessionAction("Receiver GET_STATUS") { session in
            _ = try await session.receiver.getStatus()
        }
    }

    private func receiverLaunchDefaultMediaReceiver() async {
        await runSessionAction("Launch Default Media Receiver") { session in
            _ = try await session.receiver.launch(appID: "CC1AD845")
        }
    }

    private func receiverStopCurrentApp() async {
        let sessionID = sessionSnapshot.receiverStatus?.app?.sessionID
        await runSessionAction("Stop current app") { session in
            _ = try await session.receiver.stop(sessionID: sessionID)
        }
    }

    private func receiverApplyVolume() async {
        let clamped = min(max(receiverVolumeLevel, 0), 1)
        receiverVolumeLevel = clamped
        await runSessionAction("Set volume to \(String(format: "%.2f", clamped))") { session in
            _ = try await session.receiver.setVolume(level: clamped)
        }
    }

    private func receiverSetMuted() async {
        let muted = receiverMuted
        await runSessionAction(muted ? "Mute receiver" : "Unmute receiver") { session in
            _ = try await session.receiver.setMuted(muted)
        }
    }

    private func multizoneGetStatus() async {
        await runSessionAction("Multizone GET_STATUS") { session in
            _ = try await session.multizone.getStatus()
        }
    }

    private func multizoneGetCastingGroups() async {
        await runSessionAction("Multizone GET_CASTING_GROUPS") { session in
            _ = try await session.multizone.getCastingGroups()
        }
    }

    // MARK: Media Playground

    func mediaLoadButtonTapped() {
        Task { await mediaLoad() }
    }

    func mediaLaunchAndLoadButtonTapped() {
        Task { await mediaLaunchAndLoad() }
    }

    func mediaQueueLoadSampleButtonTapped() {
        Task { await mediaQueueLoadSample() }
    }

    func mediaGetStatusButtonTapped() {
        Task { await mediaGetStatus() }
    }

    func mediaPlayButtonTapped() {
        Task { await mediaPlay() }
    }

    func mediaPauseButtonTapped() {
        Task { await mediaPause() }
    }

    func mediaStopButtonTapped() {
        Task { await mediaStop() }
    }

    func mediaSeekButtonTapped() {
        Task { await mediaSeek() }
    }

    func mediaSetPlaybackRateButtonTapped() {
        Task { await mediaSetPlaybackRate() }
    }

    func mediaEnableSubtitleButtonTapped() {
        Task { await mediaEnableSubtitle() }
    }

    func mediaDisableSubtitlesButtonTapped() {
        Task { await mediaDisableSubtitles() }
    }

    func mediaApplySubtitleStyleButtonTapped() {
        Task { await mediaApplySubtitleStyle() }
    }

    // MARK: YouTube MDX Demo

    func youtubeRefreshSessionStatusButtonTapped() {
        Task { await youtubeRefreshSessionStatus() }
    }

    func youtubeQuickPlayButtonTapped() {
        Task { await youtubeQuickPlay() }
    }

    func youtubeAddToQueueButtonTapped() {
        Task { await youtubeAddToQueue() }
    }

    func youtubePlayNextButtonTapped() {
        Task { await youtubePlayNext() }
    }

    func youtubeClearQueueButtonTapped() {
        Task { await youtubeClearQueue() }
    }

    // MARK: Local File Demo

    func localChooseVideoFileButtonTapped() {
        if let url = openFilePanel(allowedExtensions: nil) {
            localVideoFileURL = url
        }
    }

    func localChooseSubtitleFileButtonTapped() {
        if let url = openFilePanel(allowedExtensions: ["vtt"]) {
            localSubtitleFileURL = url
            Task { await localRefreshHostedSubtitleIfNeeded() }
        }
    }

    func localClearSubtitleFileButtonTapped() {
        localSubtitleFileURL = nil
        Task { await localRefreshHostedSubtitleIfNeeded() }
    }

    func localStartServerButtonTapped() {
        Task { await localStartServer() }
    }

    func localStopServerButtonTapped() {
        Task { await localStopServer() }
    }

    func localLaunchAndLoadButtonTapped() {
        Task { await localLaunchAndLoad() }
    }

    private func mediaLaunchAndLoad() async {
        await ensureDefaultMediaReceiverReadyForLoad()
        await mediaLoad()
    }

    private func mediaLoad() async {
        do {
            let item = try makeMediaItemFromForm()
            let options = try makeMediaLoadOptionsFromForm()
            await runSessionAction("Media LOAD") { session in
                _ = try await session.media.load(item, options: options)
            }
        } catch {
            latestUserError = errorMessage(error)
            appendSessionLog("Media load form error: \(errorMessage(error))")
        }
    }

    private func mediaQueueLoadSample() async {
        do {
            let item = try makeMediaItemFromForm()
            let first = CastQueueItem(
                itemID: nil,
                media: item,
                autoplay: true,
                startTime: parsedDouble(mediaStartTimeText),
                activeTextTrackIDs: parsedSubtitleTrackID().map { [$0] } ?? []
            )
            var secondMedia = item
            if case let .generic(metadata) = item.metadata {
                var updated = metadata
                updated.title = (metadata.title ?? "Item") + " (Queue 2)"
                secondMedia.metadata = .generic(updated)
            }
            let second = CastQueueItem(media: secondMedia, autoplay: true)

            await runSessionAction("QUEUE_LOAD sample") { session in
                _ = try await session.media.queueLoad(items: [first, second])
            }
        } catch {
            latestUserError = errorMessage(error)
            appendSessionLog("Queue form error: \(errorMessage(error))")
        }
    }

    private func mediaGetStatus() async {
        await runSessionAction("Media GET_STATUS") { session in
            _ = try await session.media.getStatus()
        }
    }

    private func mediaPlay() async {
        await runSessionAction("Media PLAY") { session in
            _ = try await session.media.play()
        }
    }

    private func mediaPause() async {
        await runSessionAction("Media PAUSE") { session in
            _ = try await session.media.pause()
        }
    }

    private func mediaStop() async {
        await runSessionAction("Media STOP") { session in
            _ = try await session.media.stop()
        }
    }

    private func mediaSeek() async {
        guard let seconds = parsedDouble(mediaSeekSecondsText) else {
            latestUserError = "Enter a valid seek time in seconds."
            return
        }
        await runSessionAction("Media SEEK to \(seconds)s") { session in
            _ = try await session.media.seek(to: seconds)
        }
    }

    private func mediaSetPlaybackRate() async {
        guard let rate = parsedDouble(mediaPlaybackRateText) else {
            latestUserError = "Enter a valid playback rate."
            return
        }
        await runSessionAction("Set playback rate \(rate)") { session in
            _ = try await session.media.setPlaybackRate(rate)
        }
    }

    private func mediaEnableSubtitle() async {
        guard let trackID = parsedSubtitleTrackID() else {
            latestUserError = "Enter a valid subtitle track ID."
            return
        }
        await runSessionAction("Enable subtitle track \(trackID.rawValue)") { session in
            _ = try await session.media.enableTextTrack(id: trackID)
        }
    }

    private func mediaDisableSubtitles() async {
        await runSessionAction("Disable subtitles") { session in
            _ = try await session.media.disableTextTracks()
        }
    }

    private func mediaApplySubtitleStyle() async {
        guard let style = subtitleStylePreset.castStyle else {
            latestUserError = "Choose a subtitle style preset first."
            return
        }
        await runSessionAction("Apply subtitle style") { session in
            _ = try await session.media.setTextTrackStyle(style)
        }
    }

    private func youtubeRefreshSessionStatus() async {
        guard let session else {
            latestUserError = "Connect to a device first."
            return
        }

        do {
            let status = try await youtubeController.refreshSessionStatus(in: session, timeout: 5)
            youtubeSessionStatus = status
            appendSessionLog("YouTube mdxSessionStatus refreshed (screenId=\(status.screenID ?? "nil"))")
        } catch {
            latestUserError = errorMessage(error)
            appendSessionLog("YouTube mdxSessionStatus failed: \(errorMessage(error))")
        }
    }

    private func youtubeQuickPlay() async {
        guard let session else {
            latestUserError = "Connect to a device first."
            return
        }

        do {
            let request = try makeYouTubeQuickPlayRequestFromForm()
            try await youtubeController.quickPlay(request, in: session, timeout: 10)
            youtubeSessionStatus = await youtubeController.status()
            appendSessionLog(request.enqueue ? "YouTube enqueue \(request.videoID)" : "YouTube quick play \(request.videoID)")
        } catch {
            latestUserError = errorMessage(error)
            appendSessionLog("YouTube quick play failed: \(errorMessage(error))")
        }
    }

    private func youtubeAddToQueue() async {
        guard let session else {
            latestUserError = "Connect to a device first."
            return
        }

        let videoID = youtubeVideoID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard videoID.isEmpty == false else {
            latestUserError = "Enter a YouTube video ID."
            return
        }

        do {
            try await youtubeController.addToQueue(videoID: videoID, in: session, timeout: 10)
            youtubeSessionStatus = await youtubeController.status()
            appendSessionLog("YouTube add to queue \(videoID)")
        } catch {
            latestUserError = errorMessage(error)
            appendSessionLog("YouTube add to queue failed: \(errorMessage(error))")
        }
    }

    private func youtubePlayNext() async {
        guard let session else {
            latestUserError = "Connect to a device first."
            return
        }

        let videoID = youtubeVideoID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard videoID.isEmpty == false else {
            latestUserError = "Enter a YouTube video ID."
            return
        }

        do {
            try await youtubeController.playNext(videoID: videoID, in: session, timeout: 10)
            youtubeSessionStatus = await youtubeController.status()
            appendSessionLog("YouTube play-next \(videoID)")
        } catch {
            latestUserError = errorMessage(error)
            appendSessionLog("YouTube play-next failed: \(errorMessage(error))")
        }
    }

    private func youtubeClearQueue() async {
        guard let session else {
            latestUserError = "Connect to a device first."
            return
        }

        do {
            try await youtubeController.clearQueue(in: session, timeout: 10)
            youtubeSessionStatus = await youtubeController.status()
            appendSessionLog("YouTube clear queue")
        } catch {
            latestUserError = errorMessage(error)
            appendSessionLog("YouTube clear queue failed: \(errorMessage(error))")
        }
    }

    private func localStartServer() async {
        do {
            let host = try resolvedLocalServerHost()
            let port = try resolvedLocalServerPort()
            let baseURL = try await localFileServer.start(publicHost: host, port: port)
            localServerIsRunning = true
            localServerPublicHost = host
            appendSessionLog("Local file server started at \(baseURL.absoluteString)")
        } catch {
            latestUserError = errorMessage(error)
            appendSessionLog("Local server start failed: \(errorMessage(error))")
        }
    }

    private func localStopServer() async {
        await localFileServer.stop()
        localServerIsRunning = false
        localHostedMedia = nil
        appendSessionLog("Local file server stopped")
    }

    private func localLaunchAndLoad() async {
        guard let localVideoFileURL else {
            latestUserError = "Choose a local video file first."
            return
        }

        do {
            if localServerIsRunning == false {
                try await startLocalServerIfNeeded()
            }

            let hostedMedia = try await localFileServer.host(
                videoFileURL: localVideoFileURL,
                subtitleFileURL: localSubtitleFileURL
            )
            localHostedMedia = hostedMedia
            localServerIsRunning = true
            appendSessionLog("Hosted local media at \(hostedMedia.videoURL.absoluteString)")

            let item = try makeLocalHostedMediaItem(from: hostedMedia, sourceVideoURL: localVideoFileURL)
            let options = try makeMediaLoadOptionsFromForm(
                includeSubtitleTracks: hostedMedia.subtitleURL != nil
            )

            await ensureDefaultMediaReceiverReadyForLoad()

            await runSessionAction("Local media LOAD") { session in
                _ = try await session.media.load(item, options: options)
            }
        } catch {
            latestUserError = errorMessage(error)
            appendSessionLog("Local media launch/load failed: \(errorMessage(error))")
        }
    }

    private func localRefreshHostedSubtitleIfNeeded() async {
        guard localServerIsRunning, localHostedMedia != nil else {
            return
        }
        do {
            let hostedMedia = try await localFileServer.updateSubtitleFile(localSubtitleFileURL)
            localHostedMedia = hostedMedia
            if let subtitleURL = hostedMedia.subtitleURL {
                appendSessionLog("Updated hosted local subtitle: \(subtitleURL.absoluteString)")
            } else {
                appendSessionLog("Removed hosted local subtitle")
            }
        } catch {
            latestUserError = errorMessage(error)
            appendSessionLog("Local subtitle update failed: \(errorMessage(error))")
        }
    }

    private func ensureDefaultMediaReceiverReadyForLoad() async {
        guard let session else {
            latestUserError = "Connect to a device first."
            return
        }

        do {
            _ = try await session.launchDefaultMediaReceiver()
            appendSessionLog("Launch Default Media Receiver")
        } catch {
            latestUserError = errorMessage(error)
            appendSessionLog("Launch Default Media Receiver failed: \(errorMessage(error))")
            return
        }

        // DMR launch is asynchronous on the receiver. Poll until the receiver status reports
        // the DMR app and an app transport ID is available, otherwise a following LOAD may race.
        let deadline = Date().addingTimeInterval(6)
        while Date() < deadline {
            do {
                try await session.refreshStatuses()
            } catch {
                // Receiver GET_STATUS can transiently fail during app launch; retry until timeout.
            }

            let snapshot = await session.snapshot()
            sessionSnapshot = snapshot
            syncReceiverControlsFromSnapshot()

            if let app = snapshot.receiverStatus?.app,
               app.appID == .defaultMediaReceiver,
               app.transportID != nil {
                appendSessionLog("Default Media Receiver ready")
                return
            }

            try? await Task.sleep(nanoseconds: 250_000_000)
        }

        appendSessionLog("Default Media Receiver not confirmed ready before timeout; proceeding with LOAD")
    }

    // MARK: Namespace Console

    func namespaceSendButtonTapped() {
        Task { await namespaceSendTracked() }
    }

    func namespaceSendAwaitReplyButtonTapped() {
        Task { await namespaceSendAndAwaitReply() }
    }

    private func namespaceSendTracked() async {
        namespaceReplyText = ""
        do {
            let (namespace, target, payload) = try namespaceRequestInputs()
            await runSessionAction("Namespace send \(namespace.rawValue)") { session in
                _ = try await session.send(namespace: namespace, target: target, payload: payload)
            }
            namespaceReplyText = "Request sent (no reply awaited). Check observed events or use Send & Await Reply."
        } catch {
            latestUserError = errorMessage(error)
            appendSessionLog("Namespace input error: \(errorMessage(error))")
            namespaceReplyText = "Send failed: \(errorMessage(error))"
        }
    }

    private func namespaceSendAndAwaitReply() async {
        namespaceReplyText = "Waiting for reply…"
        do {
            let (namespace, target, payload) = try namespaceRequestInputs()
            guard let session else {
                throw CastError.disconnected
            }
            let reply = try await session.sendAndAwaitReply(
                namespace: namespace,
                target: target,
                payload: payload,
                timeout: 5
            )
            namespaceReplyText = reply.payloadUTF8
            appendSessionLog("Namespace reply from \(reply.namespace.rawValue)")
        } catch {
            latestUserError = errorMessage(error)
            appendSessionLog("Namespace sendAndAwaitReply failed: \(errorMessage(error))")
            namespaceReplyText = "Request failed: \(errorMessage(error))"
        }
    }

    // MARK: Helpers

    private func runSessionAction(
        _ name: String,
        action: @escaping @Sendable (CastSession) async throws -> Void
    ) async {
        guard let session else {
            latestUserError = "Connect to a device first."
            return
        }

        do {
            try await action(session)
            appendSessionLog(name)
        } catch {
            latestUserError = errorMessage(error)
            appendSessionLog("\(name) failed: \(errorMessage(error))")
        }
    }

    private func makeMediaItemFromForm() throws -> CastMediaItem {
        guard let contentURL = URL(string: mediaURLString), contentURL.scheme != nil else {
            throw CastError.invalidArgument("Invalid media URL")
        }
        guard mediaContentType.isEmpty == false else {
            throw CastError.invalidArgument("Content type is required")
        }

        var images = [CastImage]()
        if mediaCoverURLString.isEmpty == false {
            guard let coverURL = URL(string: mediaCoverURLString), coverURL.scheme != nil else {
                throw CastError.invalidArgument("Invalid cover image URL")
            }
            images = [CastImage(url: coverURL)]
        }

        let textTracks = try makeTextTracksFromForm()

        return CastMediaItem(
            contentURL: contentURL,
            contentType: mediaContentType,
            streamType: .buffered,
            metadata: .generic(title: emptyToNil(mediaTitle), subtitle: emptyToNil(mediaSubtitle), images: images),
            textTracks: textTracks,
            textTrackStyle: subtitleStylePreset.castStyle
        )
    }

    private func makeMediaLoadOptionsFromForm() throws -> CastMediaController.LoadOptions {
        try makeMediaLoadOptionsFromForm(
            includeSubtitleTracks: mediaSubtitleURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        )
    }

    private func makeMediaLoadOptionsFromForm(includeSubtitleTracks: Bool) throws -> CastMediaController.LoadOptions {
        let startTime = mediaStartTimeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil
            : parsedDouble(mediaStartTimeText)
        if mediaStartTimeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false, startTime == nil {
            throw CastError.invalidArgument("Start time must be a number")
        }

        let activeTrackIDs: [CastMediaTrackID]
        if includeSubtitleTracks == false {
            activeTrackIDs = []
        } else {
            activeTrackIDs = parsedSubtitleTrackID().map { [$0] } ?? [1]
        }

        return .init(
            autoplay: mediaAutoplay,
            startTime: startTime,
            activeTextTrackIDs: activeTrackIDs
        )
    }

    private func namespaceRequestInputs() throws -> (CastNamespace, CastSession.NamespaceTarget, [String: JSONValue]) {
        let namespaceString = namespaceFilterString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard namespaceString.isEmpty == false else {
            throw CastError.invalidArgument("Namespace is required")
        }
        let namespace = CastNamespace(namespaceString)

        let data = Data(namespacePayloadText.utf8)
        let payload = try JSONDecoder().decode([String: JSONValue].self, from: data)

        let target: CastSession.NamespaceTarget
        switch namespaceTargetChoice {
        case .currentApplication:
            target = .currentApplication
        case .platform:
            target = .platform
        case .transport:
            let transportID = namespaceTransportTargetID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard transportID.isEmpty == false else {
                throw CastError.invalidArgument("Transport target ID is required")
            }
            target = .transport(CastTransportID(transportID))
        }

        return (namespace, target, payload)
    }

    private func parsedSubtitleTrackID() -> CastMediaTrackID? {
        guard let value = Int(mediaSubtitleTrackIDText.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }
        return .init(value)
    }

    private func parsedDouble(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return nil
        }
        return Double(trimmed)
    }

    private func makeYouTubeQuickPlayRequestFromForm() throws -> CastYouTubeController.QuickPlayRequest {
        let videoID = youtubeVideoID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard videoID.isEmpty == false else {
            throw CastError.invalidArgument("YouTube video ID is required")
        }

        let startTime = parsedDouble(youtubeStartTimeText) ?? 0
        guard startTime.isFinite, startTime >= 0 else {
            throw CastError.invalidArgument("YouTube start time must be a non-negative number")
        }

        let playlistID = emptyToNil(youtubePlaylistID)
        return .init(
            videoID: videoID,
            playlistID: playlistID,
            enqueue: youtubeEnqueue,
            startTime: startTime
        )
    }

    private func emptyToNil(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func appendDiscoveryLog(_ message: String) {
        discoveryLog.insert(.init(timestamp: .now, category: "Discovery", message: message), at: 0)
        if discoveryLog.count > 300 {
            discoveryLog.removeLast(discoveryLog.count - 300)
        }
    }

    private func appendSessionLog(_ message: String) {
        sessionLog.insert(.init(timestamp: .now, category: "Session", message: message), at: 0)
        if sessionLog.count > 400 {
            sessionLog.removeLast(sessionLog.count - 400)
        }
    }

    private func trimNamespaceLog() {
        if namespaceLog.count > 400 {
            namespaceLog.removeLast(namespaceLog.count - 400)
        }
    }

    func errorMessage(_ error: any Error) -> String {
        if let castError = error as? CastError {
            return String(describing: castError)
        }
        return String(describing: error)
    }

    private func makeTextTracksFromForm(overrideSubtitleURL: URL? = nil) throws -> [CastTextTrack] {
        let subtitleURLString = overrideSubtitleURL?.absoluteString ?? mediaSubtitleURLString
        if subtitleURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return []
        }

        guard let subtitleURL = URL(string: subtitleURLString), subtitleURL.scheme != nil else {
            throw CastError.invalidArgument("Invalid subtitle URL")
        }

        let trackID = parsedSubtitleTrackID() ?? 1
        return [
            .subtitleVTT(
                id: trackID,
                name: mediaSubtitleName.isEmpty ? "Subtitle" : mediaSubtitleName,
                languageCode: mediaSubtitleLanguageCode.isEmpty ? "en" : mediaSubtitleLanguageCode,
                url: subtitleURL
            )
        ]
    }

    private func makeLocalHostedMediaItem(
        from hostedMedia: CastLocalFileServer.HostedMedia,
        sourceVideoURL: URL
    ) throws -> CastMediaItem {
        let contentType = inferredMediaContentType(for: sourceVideoURL)
        let localVideoTitle = sourceVideoURL.deletingPathExtension().lastPathComponent
        let localSubtitleName = localSubtitleFileURL?.deletingPathExtension().lastPathComponent

        let textTracks = try makeTextTracksFromForm(overrideSubtitleURL: hostedMedia.subtitleURL)
        return CastMediaItem(
            contentURL: hostedMedia.videoURL,
            contentType: contentType,
            streamType: .buffered,
            metadata: .generic(
                title: localVideoTitle,
                subtitle: localSubtitleName ?? "Local file",
                images: []
            ),
            textTracks: textTracks,
            textTrackStyle: subtitleStylePreset.castStyle
        )
    }

    private func inferredMediaContentType(for fileURL: URL) -> String {
        switch fileURL.pathExtension.lowercased() {
        case "mp4", "m4v":
            return "video/mp4"
        case "webm":
            return "video/webm"
        case "mov":
            return "video/quicktime"
        case "mp3":
            return "audio/mpeg"
        case "m4a":
            return "audio/mp4"
        default:
            return mediaContentType.isEmpty ? "application/octet-stream" : mediaContentType
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
        appendSessionLog("Local file server started at \(baseURL.absoluteString)")
    }

    private func resolvedLocalServerHost() throws -> String {
        let typedHost = localServerPublicHost.trimmingCharacters(in: .whitespacesAndNewlines)
        if typedHost.isEmpty == false {
            return typedHost
        }
        if let detected = detectLocalIPv4Address() {
            return detected
        }
        throw CastError.invalidArgument("Enter your Mac's LAN IP for local hosting")
    }

    private func resolvedLocalServerPort() throws -> UInt16 {
        let trimmed = localServerPortText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let intPort = Int(trimmed), (1 ... 65535).contains(intPort) else {
            throw CastError.invalidArgument("Local server port must be between 1 and 65535")
        }
        return UInt16(intPort)
    }

    private func openFilePanel(allowedExtensions: [String]?) -> URL? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.resolvesAliases = true
        if let allowedExtensions {
            panel.allowedFileTypes = allowedExtensions
        }
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func detectLocalIPv4Address() -> String? {
        var address: String?
        var ifaddrPointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPointer) == 0, let first = ifaddrPointer else {
            return nil
        }
        defer { freeifaddrs(ifaddrPointer) }

        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let current = pointer {
            let interface = current.pointee
            defer { pointer = interface.ifa_next }

            let flags = Int32(interface.ifa_flags)
            let isUp = (flags & IFF_UP) != 0
            let isLoopback = (flags & IFF_LOOPBACK) != 0
            guard isUp, isLoopback == false else {
                continue
            }
            guard let addr = interface.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else {
                continue
            }

            var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                addr,
                socklen_t(addr.pointee.sa_len),
                &hostBuffer,
                socklen_t(hostBuffer.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            if result == 0 {
                let candidate = String(cString: hostBuffer)
                if candidate.hasPrefix("169.254.") == false {
                    address = candidate
                    break
                }
            }
        }
        return address
    }
}
