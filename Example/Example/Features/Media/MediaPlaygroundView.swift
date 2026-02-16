//
//  ChromecastKit
//  Swift package for Google Cast (Chromecast).
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
                    Button("Load Into Current App") { model.mediaLoadButtonTapped() }
                    Button("Get Media Status") { model.mediaGetStatusButtonTapped() }
                }

                Text("“Load Into Current App” only works if the active app supports `com.google.cast.media`.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Media Source") {
                TextField("Media URL", text: $model.mediaURLString)
                TextField("Content Type", text: $model.mediaContentType)
                TextField("Title", text: $model.mediaTitle)
                TextField("Subtitle", text: $model.mediaSubtitle)
                TextField("Cover Image URL (optional)", text: $model.mediaCoverURLString)

                Toggle("Autoplay", isOn: $model.mediaAutoplay)
                TextField("Start Time (seconds, optional)", text: $model.mediaStartTimeText)
            }

            Section("Subtitles (VTT)") {
                TextField("Subtitle URL (.vtt)", text: $model.mediaSubtitleURLString)
                HStack {
                    TextField("Track ID", text: $model.mediaSubtitleTrackIDText)
                        .frame(width: 100)
                    TextField("Name", text: $model.mediaSubtitleName)
                    TextField("Language", text: $model.mediaSubtitleLanguageCode)
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
                    Button("Disable Tracks") { model.mediaDisableSubtitlesButtonTapped() }
                    Button("Apply Style") { model.mediaApplySubtitleStyleButtonTapped() }
                }
            }

            Section("Playback Controls") {
                HStack {
                    Button("Play") { model.mediaPlayButtonTapped() }
                    Button("Pause") { model.mediaPauseButtonTapped() }
                    Button("Stop") { model.mediaStopButtonTapped() }
                    Button("Get Status") { model.mediaGetStatusButtonTapped() }
                }

                HStack {
                    TextField("Seek Seconds", text: $model.mediaSeekSecondsText)
                        .frame(width: 140)
                    Button("Seek") { model.mediaSeekButtonTapped() }
                    Spacer()
                    TextField("Playback Rate", text: $model.mediaPlaybackRateText)
                        .frame(width: 120)
                    Button("Apply Rate") { model.mediaSetPlaybackRateButtonTapped() }
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
