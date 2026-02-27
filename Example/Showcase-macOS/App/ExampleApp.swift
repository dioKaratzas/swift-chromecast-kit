//
//  ChromecastKit
//  SPDX-License-Identifier: Apache-2.0
//  Copyright 2026 Dionysis Karatzas
//

import SwiftUI

@main
struct ExampleApp: App {
    @State private var model = ShowcaseAppModel()

    var body: some Scene {
        WindowGroup("ChromecastKit Example") {
            ShowcaseRootView(model: model)
                .frame(minWidth: 1120, minHeight: 700)
        }
        .defaultSize(width: 1240, height: 760)
    }
}
