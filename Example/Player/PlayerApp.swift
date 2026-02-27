//
//  ChromecastKit
//  SPDX-License-Identifier: Apache-2.0
//  Copyright 2026 Dionysis Karatzas
//

import SwiftUI

@main
struct PlayerApp: App {
    @State private var model = PlayerModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
            #if os(macOS)
                .frame(minWidth: 1100, minHeight: 720)
            #endif
        }

        #if os(macOS)
            Settings {
                PlayerSettingsView(model: model)
                    .frame(minWidth: 420, minHeight: 380)
            }
        #endif
    }
}
