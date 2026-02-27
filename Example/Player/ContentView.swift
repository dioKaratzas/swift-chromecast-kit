//
//  ChromecastKit
//  SPDX-License-Identifier: Apache-2.0
//  Copyright 2026 Dionysis Karatzas
//

import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
    import PhotosUI
    import CoreTransferable
#endif

struct ContentView: View {
    @Bindable var model: PlayerModel
    @State private var showsMediaImporter = false
    @State private var showsSettings = false
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
            backgroundGradient

            VStack(spacing: 0) {
                PlayerSurfaceView(model: model)
                controlsView
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

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color(red: 0.09, green: 0.10, blue: 0.13),
                Color(red: 0.04, green: 0.04, blue: 0.05)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    @ViewBuilder private var controlsView: some View {
        #if os(iOS)
            PlayerControlsView(
                model: model,
                scrubBinding: scrubBinding,
                volumeBinding: volumeBinding,
                showsSettings: $showsSettings,
                showsMediaImporter: $showsMediaImporter,
                selectedPhotoVideoItem: $selectedPhotoVideoItem
            )
        #else
            PlayerControlsView(
                model: model,
                scrubBinding: scrubBinding,
                volumeBinding: volumeBinding,
                showsSettings: $showsSettings,
                showsMediaImporter: $showsMediaImporter
            )
        #endif
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
}

#Preview {
    ContentView(model: PlayerModel())
}
