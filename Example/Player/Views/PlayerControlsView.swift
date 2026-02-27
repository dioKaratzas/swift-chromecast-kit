//
//  ChromecastKit
//  Swift package for Google Cast (Chromecast).
//

import SwiftUI
#if os(iOS)
    import PhotosUI
#endif

struct PlayerControlsView: View {
    @Bindable var model: PlayerModel
    let scrubBinding: Binding<Double>
    let volumeBinding: Binding<Double>
    @Binding var showsSettings: Bool
    @Binding var showsMediaImporter: Bool
    #if os(iOS)
        @Binding var selectedPhotoVideoItem: PhotosPickerItem?
    #endif

    var body: some View {
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
                    SubtitleTracksMenu(model: model)
                    CastDeviceMenu(model: model)

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
}
