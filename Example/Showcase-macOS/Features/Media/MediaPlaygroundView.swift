//
//  ChromecastKit
//  SPDX-License-Identifier: Apache-2.0
//  Copyright 2026 Dionysis Karatzas
//

import SwiftUI
import ChromecastKit

struct MediaPlaygroundView: View {
    @Bindable var model: ShowcaseAppModel
    @State private var showsQueueDemoDetails = false

    var body: some View {
        Form {
            Section("Quick Start") {
                Text(
                    "Use \"Launch DMR + Load\" for the simplest demo. It launches the Default Media Receiver and loads the media URL below."
                )
                .foregroundStyle(.secondary)

                HStack {
                    Button("Launch DMR + Load") { model.mediaLaunchAndLoadButtonTapped() }
                        .disabled(model.hasConnectedSession == false)
                    Button("Load Into Current App") { model.mediaLoadButtonTapped() }
                        .disabled(model.hasConnectedSession == false)
                    Button("Get Media Status") { model.mediaGetStatusButtonTapped() }
                        .disabled(model.hasConnectedSession == false)
                }

                Text("“Load Into Current App” only works if the active app supports `com.google.cast.media`.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("YouTube (MDX)") {
                Text(
                    "Use the built-in `CastYouTubeController` for YouTube app quick-play/queue actions. Volume/mute remains receiver-level, and seek/play/pause uses the generic media controller when YouTube exposes the media namespace."
                )
                .foregroundStyle(.secondary)

                TextField("YouTube Video ID", text: $model.youtubeVideoID)
                    .textFieldStyle(.roundedBorder)
                TextField("Playlist ID (optional)", text: $model.youtubePlaylistID)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Toggle("Enqueue", isOn: $model.youtubeEnqueue)
                    Spacer()
                    TextField("Start Time", text: $model.youtubeStartTimeText, prompt: Text("0"))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                }

                HStack {
                    Button("Refresh MDX Status") { model.youtubeRefreshSessionStatusButtonTapped() }
                        .disabled(model.hasConnectedSession == false)
                    Button("Quick Play / Enqueue") { model.youtubeQuickPlayButtonTapped() }
                        .disabled(model.hasConnectedSession == false)
                    Button("Add To Queue") { model.youtubeAddToQueueButtonTapped() }
                        .disabled(model.hasConnectedSession == false)
                }

                HStack {
                    Button("Play Next") { model.youtubePlayNextButtonTapped() }
                        .disabled(model.hasConnectedSession == false)
                    Button("Clear Queue") { model.youtubeClearQueueButtonTapped() }
                        .disabled(model.hasConnectedSession == false)
                }

                LabeledContent("YouTube MDX Screen ID") {
                    Text(model.youtubeSessionStatus.screenID ?? "Unknown (refresh or quick-play)")
                        .font(.footnote.monospaced())
                }

                Text(
                    "Volume/mute: Receiver tab. Seek/play/pause: Playback Controls below (if supported by the active YouTube app build)."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("Media Source") {
                TextField("Media URL", text: $model.mediaURLString).textFieldStyle(.roundedBorder)
                TextField("Content Type", text: $model.mediaContentType).textFieldStyle(.roundedBorder)
                TextField("Title", text: $model.mediaTitle).textFieldStyle(.roundedBorder)
                TextField("Subtitle", text: $model.mediaSubtitle).textFieldStyle(.roundedBorder)
                TextField("Cover Image URL (optional)", text: $model.mediaCoverURLString).textFieldStyle(.roundedBorder)

                Toggle("Autoplay", isOn: $model.mediaAutoplay)
                TextField("Start Time (seconds, optional)", text: $model.mediaStartTimeText)
                    .textFieldStyle(.roundedBorder)
            }

            Section("Subtitles (VTT)") {
                TextField("Subtitle URL (.vtt)", text: $model.mediaSubtitleURLString)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    TextField("Track ID", text: $model.mediaSubtitleTrackIDText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                    TextField("Name", text: $model.mediaSubtitleName)
                        .textFieldStyle(.roundedBorder)
                    TextField("Language", text: $model.mediaSubtitleLanguageCode)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                }
                Picker("Style Preset", selection: $model.subtitleStylePreset) {
                    ForEach(ShowcaseAppModel.SubtitleStylePreset.allCases) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                HStack {
                    Button("Enable Track") { model.mediaEnableSubtitleButtonTapped() }
                        .disabled(model.hasActiveMediaSession == false)
                    Button("Disable Tracks") { model.mediaDisableSubtitlesButtonTapped() }
                        .disabled(model.hasActiveMediaSession == false)
                    Button("Apply Style") { model.mediaApplySubtitleStyleButtonTapped() }
                        .disabled(model.hasActiveMediaSession == false)
                }

                if model.hasActiveMediaSession == false {
                    Text("Load media first to enable subtitle controls.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Playback Controls") {
                HStack {
                    Button("Play") { model.mediaPlayButtonTapped() }
                        .disabled(model.hasActiveMediaSession == false)
                    Button("Pause") { model.mediaPauseButtonTapped() }
                        .disabled(model.hasActiveMediaSession == false)
                    Button("Stop") { model.mediaStopButtonTapped() }
                        .disabled(model.hasActiveMediaSession == false)
                    Button("Get Status") { model.mediaGetStatusButtonTapped() }
                        .disabled(model.hasConnectedSession == false)
                }

                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 10) {
                    GridRow {
                        Text("Seek Seconds")
                        HStack(spacing: 8) {
                            TextField("", text: $model.mediaSeekSecondsText, prompt: Text("30"))
                                .labelsHidden()
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 140)
                            Button("Seek") { model.mediaSeekButtonTapped() }
                                .disabled(model.hasActiveMediaSession == false)
                        }
                    }

                    GridRow {
                        Text("Playback Rate")
                        HStack(spacing: 8) {
                            TextField("", text: $model.mediaPlaybackRateText, prompt: Text("1.0"))
                                .labelsHidden()
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 120)
                            Button("Apply Rate") { model.mediaSetPlaybackRateButtonTapped() }
                                .disabled(model.hasActiveMediaSession == false)
                        }
                    }
                }

                if model.hasActiveMediaSession == false {
                    Text("Launch and load media first to enable playback controls.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Queue Demo (Advanced)") {
                DisclosureGroup("Show Queue Demo") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(
                            "This demo loads a sample queue (multiple media items) into the Default Media Receiver to showcase queue APIs."
                        )
                        .foregroundStyle(.secondary)
                        Text("It is not required for normal playback. Use it after a successful session connection.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack {
                            Button("Queue Load Sample") { model.mediaQueueLoadSampleButtonTapped() }
                                .disabled(model.hasConnectedSession == false)
                        }
                    }
                    .padding(.top, 4)
                }
                .disclosureGroupStyle(.automatic)
            }

            Section("Current Media Snapshot") {
                if let media = model.sessionSnapshot.mediaStatus {
                    LabeledContent("Player State") { Text(media.playerState.rawValue) }
                    LabeledContent("Adjusted Time") {
                        Text("\(media.adjustedCurrentTime, format: .number.precision(.fractionLength(0 ... 1)))s")
                            .monospacedDigit()
                    }
                    LabeledContent("Duration") {
                        if let duration = media.duration {
                            Text("\(duration, format: .number.precision(.fractionLength(0 ... 1)))s")
                                .monospacedDigit()
                        } else {
                            Text("—")
                        }
                    }
                    LabeledContent("Media Session ID") {
                        Text(media.mediaSessionID.map { String($0.rawValue) } ?? "None")
                    }
                    LabeledContent("Supported Commands") {
                        Text("0x\(String(media.supportedCommands.rawValue, radix: 16).uppercased())")
                            .font(.footnote.monospaced())
                    }
                    LabeledContent("Active Tracks") {
                        Text(
                            media.activeTextTrackIDs.map { String($0.rawValue) }.joined(separator: ", ").isEmpty ? "—" : media.activeTextTrackIDs.map { String(
                                $0.rawValue
                            ) }.joined(separator: ", ")
                        )
                    }
                    LabeledContent("Queue") {
                        Text(
                            "current=\(media.queueCurrentItemID.map { String($0.rawValue) } ?? "—"), repeat=\(media.queueRepeatMode?.rawValue ?? "—")"
                        )
                        .font(.footnote.monospaced())
                    }
                } else {
                    Text(
                        "No media status available yet. Media controls require an app that supports the standard Cast media namespace."
                    )
                    .foregroundStyle(.secondary)
                }
            }

            Section("Subtitle Hosting Reminder") {
                Text(
                    "Chromecast fetches subtitle URLs itself. Use a reachable URL, valid WebVTT (`text/vtt`), and enable CORS for subtitle files."
                )
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
