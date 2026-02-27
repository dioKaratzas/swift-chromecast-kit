import AVKit
import ChromecastKit
import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import CoreTransferable
import PhotosUI
#endif

struct ContentView: View {
    @Bindable var model: PlayerModel
    @State private var showsMediaImporter = false
    @State private var showsSettings = false
    @State private var isDropTargeted = false
#if os(iOS)
    @State private var selectedPhotoVideoItem: PhotosPickerItem?
#endif

    private var scrubBinding: Binding<Double> {
        Binding(
            get: { model.scrubPosition ?? model.primaryPlaybackPosition },
            set: { model.scrubPosition = $0 }
        )
    }

    private var volumeBinding: Binding<Double> {
        Binding(
            get: { model.primaryVolumeLevel },
            set: { model.setPrimaryVolumeLevel($0) }
        )
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.09, green: 0.10, blue: 0.13),
                    Color(red: 0.04, green: 0.04, blue: 0.05)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                playerSurface

                playerControls
                    .padding()
            }

            if let latestError = model.latestUserError {
                VStack {
                    Spacer()
                    Text(latestError)
                        .font(.footnote)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.65), in: Capsule())
                        .foregroundStyle(.orange)
                        .padding(.bottom, 78)
                }
                .transition(.opacity)
            }
        }
        .task { model.onAppear() }
        .onDisappear { model.onDisappear() }
        .fileImporter(
            isPresented: $showsMediaImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false,
            onCompletion: handleMediaImport
        )
#if os(iOS)
        .onChange(of: selectedPhotoVideoItem) { _, _ in
            Task { await importPickedPhotoVideoIfNeeded() }
        }
#endif
        .sheet(isPresented: $showsSettings) {
            NavigationStack {
                PlayerSettingsView(model: model)
            }
            .frame(minWidth: 360, minHeight: 360)
        }
    }

    private var playerSurface: some View {
        ZStack(alignment: .bottom) {
            if model.hasLoadedLocalMedia {
                VideoPlayer(player: model.player)
            } else {
                Rectangle()
                    .fill(.black.opacity(0.55))
                    .overlay {
                        Image(systemName: "play.fill")
                            .font(.system(size: 48, weight: .medium))
                            .foregroundStyle(.white.opacity(0.4))
                    }
            }

            if model.currentSubtitleText.isEmpty == false {
                Text(model.currentSubtitleText)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 20 * model.subtitleFontScale, weight: .semibold))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(
                        subtitleColor(from: model.subtitleBackgroundColor)
                            .opacity(model.subtitleBackgroundOpacity),
                        in: RoundedRectangle(cornerRadius: 12)
                    )
                    .foregroundStyle(subtitleColor(from: model.subtitleForegroundColor))
                    .padding(.horizontal, 22)
                    .padding(.bottom, 26)
            }

            if isDropTargeted {
                Rectangle()
                    .stroke(Color.blue, style: StrokeStyle(lineWidth: 3, dash: [8]))
                    .padding(2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topLeading) {
            HStack(spacing: 8) {
                Text(model.localMediaTitle)
                    .font(.caption)
                    .lineLimit(1)
                if model.hasSubtitle {
                    Image(systemName: "captions.bubble.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.black.opacity(0.45), in: Capsule())
            .foregroundStyle(.white.opacity(0.82))
            .padding(10)
        }
        .dropDestination(for: URL.self) { urls, _ in
            model.handleDroppedFiles(urls)
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
    }

    private var playerControls: some View {
        VStack(spacing: 8) {
            Slider(
                value: scrubBinding,
                in: 0 ... model.primaryPlaybackDuration,
                onEditingChanged: { isEditing in
                    if isEditing == false {
                        model.commitPrimaryScrub()
                    }
                }
            )
            .tint(.white.opacity(0.8))

            HStack(alignment: .center) {
                HStack(spacing: 8) {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                    Slider(value: volumeBinding, in: 0 ... 1) { editing in
                        if editing == false {
                            model.commitPrimaryVolumeChange()
                        }
                    }
                    .frame(width: 110)
                }

                Spacer()

                HStack(spacing: 18) {
                    Button {
                        model.skipPrimary(by: -10)
                    } label: {
                        Image(systemName: "backward.fill")
                    }
                    .buttonStyle(.plain)

                    Button {
                        model.togglePrimaryPlaybackButtonTapped()
                    } label: {
                        Image(systemName: model.isPrimaryPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 24, weight: .semibold))
                    }
                    .buttonStyle(.plain)

                    Button {
                        model.skipPrimary(by: 10)
                    } label: {
                        Image(systemName: "forward.fill")
                    }
                    .buttonStyle(.plain)
                }
                .foregroundStyle(.white)

                Spacer()

                HStack(spacing: 8) {
                    subtitleTracksMenu

                    Menu {
                        Button {
                            model.selectCastDevice(nil)
                        } label: {
                            Label(
                                "Computer",
                                systemImage: model.hasConnectedSession ? "desktopcomputer" : "checkmark"
                            )
                        }

                        ForEach(model.devices, id: \.id) { device in
                            Button {
                                model.selectCastDevice(device.id)
                            } label: {
                                Label(
                                    device.friendlyName,
                                    systemImage: model.connectedDeviceID == device.id ? "checkmark" : "tv"
                                )
                            }
                        }

                        Divider()

                        if case .running = model.discoveryState {
                            Button("Stop discovery") {
                                model.stopDiscoveryButtonTapped()
                            }
                        } else {
                            Button("Start discovery") {
                                model.startDiscoveryButtonTapped()
                            }
                        }

                        Button("Refresh device list") {
                            model.refreshDiscoveryButtonTapped()
                        }

                        if model.canCastCurrentMedia {
                            Button("Cast current media") {
                                model.castCurrentMediaButtonTapped()
                            }
                        }
                    } label: {
                        Image(systemName: "airplayaudio")
                            .foregroundStyle(.white.opacity(0.92))
                    }
                    .menuStyle(.borderlessButton)
                    .buttonStyle(.plain)

                    Button {
                        showsSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .foregroundStyle(.white.opacity(0.92))
                    }
                    .buttonStyle(.plain)

#if os(iOS)
                    PhotosPicker(selection: $selectedPhotoVideoItem, matching: .videos, photoLibrary: .shared()) {
                        Image(systemName: "photo.on.rectangle")
                            .foregroundStyle(.white.opacity(0.92))
                    }
                    .buttonStyle(.plain)
#endif

                    Button {
                        showsMediaImporter = true
                    } label: {
                        Image(systemName: "folder")
                            .foregroundStyle(.white.opacity(0.92))
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack {
                Text(model.formattedTime(model.primaryPlaybackPosition))
                Spacer()
                Text(model.formattedTime(model.primaryPlaybackDuration))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.white.opacity(0.7))
        }
    }

    private var subtitleTracksMenu: some View {
        Menu {
            Button {
                model.selectSubtitleTrack(nil)
            } label: {
                Label(
                    "Off",
                    systemImage: model.selectedSubtitleTrackID == nil ? "checkmark" : "captions.bubble"
                )
            }

            if model.subtitleTracks.isEmpty {
                Text("Drop one or more .vtt files")
            } else {
                ForEach(model.subtitleTracks) { track in
                    Button {
                        model.selectSubtitleTrack(track.id)
                    } label: {
                        Label(
                            track.fileURL.lastPathComponent,
                            systemImage: model.selectedSubtitleTrackID == track.id ? "checkmark" : "captions.bubble"
                        )
                    }
                }

                Divider()

                if model.selectedSubtitleTrackID != nil {
                    Button("Remove selected subtitle") {
                        model.removeSelectedSubtitleTrackButtonTapped()
                    }
                }

                Button("Clear all subtitles") {
                    model.clearAllSubtitlesButtonTapped()
                }
            }
        } label: {
            Image(systemName: model.hasSubtitle ? "captions.bubble.fill" : "captions.bubble")
                .foregroundStyle(.white.opacity(0.92))
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
    }

    private func handleMediaImport(_ result: Result<[URL], any Error>) {
        switch result {
        case let .success(urls):
            guard let url = urls.first else {
                return
            }
            let importedURL = copyImportedFileToTemp(url) ?? url
            _ = model.handleDroppedFiles([importedURL])
        case let .failure(error):
            model.latestUserError = String(describing: error)
        }
    }

    private func copyImportedFileToTemp(_ url: URL) -> URL? {
        let hasScopedAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasScopedAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let tempDirectory = FileManager.default.temporaryDirectory
        let targetURL = tempDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
            .appendingPathExtension(url.pathExtension)

        do {
            if FileManager.default.fileExists(atPath: targetURL.path) {
                try FileManager.default.removeItem(at: targetURL)
            }
            try FileManager.default.copyItem(at: url, to: targetURL)
            return targetURL
        } catch {
            model.latestUserError = "Import failed: \(error)"
            return nil
        }
    }

#if os(iOS)
    private func importPickedPhotoVideoIfNeeded() async {
        guard let item = selectedPhotoVideoItem else {
            return
        }
        defer { selectedPhotoVideoItem = nil }

        do {
            if let pickedMovie = try await item.loadTransferable(type: PickedMovie.self) {
                _ = model.handleDroppedFiles([pickedMovie.url])
                return
            }

            if let data = try await item.loadTransferable(type: Data.self) {
                let preferredType = item.supportedContentTypes.first ?? .movie
                let preferredExtension = preferredType.preferredFilenameExtension ?? "mov"
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension(preferredExtension)
                try data.write(to: tempURL, options: [.atomic])
                _ = model.handleDroppedFiles([tempURL])
                return
            }

            model.latestUserError = "Could not load selected video from Photos."
        } catch {
            model.latestUserError = "Photo video import failed: \(error.localizedDescription)"
        }
    }

    private struct PickedMovie: Transferable {
        let url: URL

        static var transferRepresentation: some TransferRepresentation {
            FileRepresentation(importedContentType: .movie) { received in
                let sourceURL = received.file
                let pathExtension = sourceURL.pathExtension.isEmpty ? "mov" : sourceURL.pathExtension
                let destinationURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension(pathExtension)

                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }
                try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
                return Self(url: destinationURL)
            }
        }
    }
#endif

    private func subtitleColor(from value: PlayerModel.SubtitleRGBColor) -> Color {
        Color(red: value.red, green: value.green, blue: value.blue)
    }
}

#Preview {
    ContentView(model: PlayerModel())
}
