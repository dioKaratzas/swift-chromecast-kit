//
//  ChromecastKit
//  Swift package for Google Cast (Chromecast).
//

import SwiftUI

@main
struct ExampleApp: App {
    @State private var model = DiscoveryFeatureModel()

    var body: some Scene {
        WindowGroup("ChromecastKit Example") {
            DiscoveryFeatureView(model: model)
                .frame(minWidth: 900, minHeight: 560)
        }
        .defaultSize(width: 980, height: 620)
    }
}
