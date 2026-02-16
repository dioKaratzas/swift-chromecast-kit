//
//  ChromecastKit
//  Swift package for Google Cast (Chromecast).
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

                Toggle("Muted", isOn: $model.receiverMuted)

                HStack {
                    Button("Apply Volume") { model.receiverApplyVolumeButtonTapped() }
                    Button(model.receiverMuted ? "Apply Mute" : "Apply Unmute") { model.receiverSetMutedButtonTapped() }
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
