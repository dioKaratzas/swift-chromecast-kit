//
//  ChromecastKit
//  SPDX-License-Identifier: Apache-2.0
//  Copyright 2026 Dionysis Karatzas
//

import SwiftUI

struct CastDeviceMenu: View {
    @Bindable var model: PlayerModel

    var body: some View {
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
    }
}
