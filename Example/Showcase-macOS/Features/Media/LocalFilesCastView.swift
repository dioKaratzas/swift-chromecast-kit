//
//  ChromecastKit
//  SPDX-License-Identifier: Apache-2.0
//  Copyright 2026 Dionysis Karatzas
//

import SwiftUI
import ChromecastKit

struct LocalFilesCastView: View {
    @Bindable var model: ShowcaseAppModel

    var body: some View {
        Form {
            Section("Local Files (Swifter)") {
                Text(
                    "This tab starts a small local HTTP server so your Chromecast can fetch files directly from your Mac over the LAN."
                )
                .foregroundStyle(.secondary)
            }

            Section("Files") {
                LabeledContent("Video File") {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Button("Choose Video…") { model.localChooseVideoFileButtonTapped() }
                            if let url = model.localVideoFileURL {
                                Text(url.lastPathComponent)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        if let url = model.localVideoFileURL {
                            Text(url.path)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .textSelection(.enabled)
                        } else {
                            Text("No video selected")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                LabeledContent("Subtitle (.vtt)") {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Button("Choose Subtitle…") { model.localChooseSubtitleFileButtonTapped() }
                            if model.localSubtitleFileURL != nil {
                                Button("Clear") { model.localClearSubtitleFileButtonTapped() }
                            }
                            if let url = model.localSubtitleFileURL {
                                Text(url.lastPathComponent)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        if let url = model.localSubtitleFileURL {
                            Text(url.path)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .textSelection(.enabled)
                        } else {
                            Text("Optional")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Local Server") {
                LabeledContent("LAN Host / IP") {
                    TextField("", text: $model.localServerPublicHost, prompt: Text("192.168.1.x"))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                }
                LabeledContent("Port") {
                    TextField("", text: $model.localServerPortText, prompt: Text("8081"))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                }

                HStack {
                    if model.localServerIsRunning {
                        Button("Stop Local Server") { model.localStopServerButtonTapped() }
                    } else {
                        Button("Start Local Server") { model.localStartServerButtonTapped() }
                    }
                    Spacer()
                    Text(model.localServerIsRunning ? "Running" : "Stopped")
                        .foregroundStyle(model.localServerIsRunning ? .green : .secondary)
                }
            }

            Section("Hosted URLs") {
                if let hosted = model.localHostedMedia {
                    LabeledContent("Video URL") {
                        Text(hosted.videoURL.absoluteString)
                            .font(.footnote.monospaced())
                            .textSelection(.enabled)
                            .lineLimit(2)
                    }
                    LabeledContent("Subtitle URL") {
                        Text(hosted.subtitleURL?.absoluteString ?? "—")
                            .font(.footnote.monospaced())
                            .textSelection(.enabled)
                            .lineLimit(2)
                    }
                } else {
                    Text("No local URLs hosted yet. Start the local server and launch local playback.")
                        .foregroundStyle(.secondary)
                }

                Text(
                    "Changing or clearing the local subtitle file updates the hosted subtitle URL on the running local server. Reload media on Chromecast to ensure the new subtitle is fetched."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("Cast Local Files") {
                Button("Launch DMR + Play Local Files") {
                    model.localLaunchAndLoadButtonTapped()
                }
                .disabled(model.hasConnectedSession == false || model.localVideoFileURL == nil)

                if model.hasConnectedSession == false {
                    Text("Connect to a Chromecast first.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if model.localVideoFileURL == nil {
                    Text("Choose a local video file first.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(
                        "The selected local video (and optional WebVTT subtitle) will be hosted via Swifter and then loaded into the Default Media Receiver."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}
