//
//  ChromecastKit
//  SPDX-License-Identifier: Apache-2.0
//  Copyright 2026 Dionysis Karatzas
//

import SwiftUI

struct ReceiverControlsView: View {
    @Bindable var model: ShowcaseAppModel

    var body: some View {
        Form {
            Section("Receiver Commands") {
                HStack {
                    Button("Get Status") { model.receiverGetStatusButtonTapped() }
                    Button("Launch Default Media Receiver") { model.receiverLaunchDefaultMediaReceiverButtonTapped() }
                    Button("Stop Current App") { model.receiverStopCurrentAppButtonTapped() }
                }
                .buttonStyle(.bordered)
                .disabled(model.hasConnectedSession == false)
            }

            Section("Volume") {
                LabeledContent("Level") {
                    HStack(spacing: 12) {
                        Slider(value: $model.receiverVolumeLevel, in: 0 ... 1)
                            .frame(width: 220)
                        Text("\(Int(model.receiverVolumeLevel * 100))%")
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                }
                .disabled(model.hasConnectedSession == false)

                Toggle("Muted", isOn: $model.receiverMuted)
                    .disabled(model.hasConnectedSession == false)

                HStack {
                    Button("Apply Volume") { model.receiverApplyVolumeButtonTapped() }
                    Button(model.receiverMuted ? "Apply Mute" : "Apply Unmute") { model.receiverSetMutedButtonTapped() }
                }
                .disabled(model.hasConnectedSession == false)

                if model.hasConnectedSession == false {
                    Text("Connect to a device first to use receiver commands.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Notes") {
                Text("Receiver controls work even when app-specific media status is unavailable (for example, Netflix).")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
