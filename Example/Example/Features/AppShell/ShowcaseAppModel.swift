//
//  ChromecastKit
//  Swift package for Google Cast (Chromecast).
//

import Foundation
import Observation
import ChromecastKit

@MainActor
@Observable
final class ShowcaseAppModel {
    enum DetailTab: String, CaseIterable, Identifiable {
        case overview
        case receiver
        case media
        case namespace

        var id: Self {
            self
        }

        var title: String {
            switch self {
            case .overview: "Session"
            case .receiver: "Receiver"
            case .media: "Media"
            case .namespace: "Namespaces"
            }
        }

        var systemImage: String {
            switch self {
            case .overview: "dot.radiowaves.left.and.right"
            case .receiver: "tv"
            case .media: "play.rectangle"
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

    private var discoveryEventsTask: Task<Void, Never>?
    private var sessionConnectionEventsTask: Task<Void, Never>?
    private var sessionStateEventsTask: Task<Void, Never>?
    private var sessionNamespaceEventsTask: Task<Void, Never>?
    private var autoRefreshMediaTimeTask: Task<Void, Never>?

    private(set) var discoveryState = CastDiscoveryState.stopped
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

    // Namespace console
    var namespaceFilterString = "urn:x-cast:com.example.echo"
    var namespaceTargetChoice = NamespaceTargetChoice.currentApplication
    var namespaceTransportTargetID = ""
    var namespacePayloadText = "{\n  \"type\": \"PING\",\n  \"hello\": \"world\"\n}"
    var namespaceReplyText = ""

    // Manual host fallback (when mDNS is unavailable)
    var manualHostAddress = ""
    var manualHostPortText = "8009"
    var manualHostFriendlyName = ""

    init(discovery: CastDiscovery = CastDiscovery()) {
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

    private func handleDiscoveryEvent(_ event: CastDiscoveryEvent) async {
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

    private func mediaLaunchAndLoad() async {
        await receiverLaunchDefaultMediaReceiver()
        try? await Task.sleep(nanoseconds: 600_000_000)
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

    // MARK: Namespace Console

    func namespaceSendButtonTapped() {
        Task { await namespaceSendTracked() }
    }

    func namespaceSendAwaitReplyButtonTapped() {
        Task { await namespaceSendAndAwaitReply() }
    }

    private func namespaceSendTracked() async {
        do {
            let (namespace, target, payload) = try namespaceRequestInputs()
            await runSessionAction("Namespace send \(namespace.rawValue)") { session in
                _ = try await session.send(namespace: namespace, target: target, payload: payload)
            }
        } catch {
            latestUserError = errorMessage(error)
            appendSessionLog("Namespace input error: \(errorMessage(error))")
        }
    }

    private func namespaceSendAndAwaitReply() async {
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

        var textTracks = [CastTextTrack]()
        if mediaSubtitleURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            guard let subtitleURL = URL(string: mediaSubtitleURLString), subtitleURL.scheme != nil else {
                throw CastError.invalidArgument("Invalid subtitle URL")
            }
            let trackID = parsedSubtitleTrackID() ?? 1
            textTracks = [
                .subtitleVTT(
                    id: trackID,
                    name: mediaSubtitleName.isEmpty ? "Subtitle" : mediaSubtitleName,
                    languageCode: mediaSubtitleLanguageCode.isEmpty ? "en" : mediaSubtitleLanguageCode,
                    url: subtitleURL
                )
            ]
        }

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
        let startTime = mediaStartTimeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil
            : parsedDouble(mediaStartTimeText)
        if mediaStartTimeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false, startTime == nil {
            throw CastError.invalidArgument("Start time must be a number")
        }

        let activeTrackIDs: [CastMediaTrackID]
        if mediaSubtitleURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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
}
