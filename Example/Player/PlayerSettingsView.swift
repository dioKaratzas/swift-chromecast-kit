import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct PlayerSettingsView: View {
    @Bindable var model: PlayerModel

    var body: some View {
        Form {
            Section("Subtitle Rendering") {
                ColorPicker("Text Color", selection: subtitleForegroundBinding, supportsOpacity: false)
                ColorPicker("Background Color", selection: subtitleBackgroundBinding, supportsOpacity: false)

                HStack {
                    Text("Font Scale")
                    Spacer()
                    Text(model.subtitleFontScale, format: .number.precision(.fractionLength(2)))
                        .monospacedDigit()
                }
                Slider(value: $model.subtitleFontScale, in: 0.75 ... 2.0, step: 0.05)

                HStack {
                    Text("Background Opacity")
                    Spacer()
                    Text(model.subtitleBackgroundOpacity, format: .number.precision(.fractionLength(2)))
                        .monospacedDigit()
                }
                Slider(value: $model.subtitleBackgroundOpacity, in: 0 ... 1, step: 0.05)

                Picker("Edge Style", selection: $model.subtitleEdgeStyle) {
                    ForEach(PlayerModel.SubtitleEdgeStyleOption.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
            }

            Section("Chromecast") {
                Text(
                    "Chromecast supports text-track style fields like text/background color, font scale, and edge style. Some receiver apps may ignore part of the style."
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                Button("Apply Style To Active Chromecast Session") {
                    model.applySubtitleStyleToChromecastButtonTapped()
                }
                .disabled(model.canApplySubtitleStyleToChromecast == false)
            }
        }
        .navigationTitle("Player Settings")
    }

    private var subtitleForegroundBinding: Binding<Color> {
        Binding(
            get: { color(from: model.subtitleForegroundColor) },
            set: { color in
                guard let value = rgbValue(from: color) else {
                    return
                }
                model.subtitleForegroundColor = value
            }
        )
    }

    private var subtitleBackgroundBinding: Binding<Color> {
        Binding(
            get: { color(from: model.subtitleBackgroundColor) },
            set: { color in
                guard let value = rgbValue(from: color) else {
                    return
                }
                model.subtitleBackgroundColor = value
            }
        )
    }

    private func color(from value: PlayerModel.SubtitleRGBColor) -> Color {
        Color(red: value.red, green: value.green, blue: value.blue)
    }

    private func rgbValue(from color: Color) -> PlayerModel.SubtitleRGBColor? {
#if os(iOS)
        let uiColor = UIColor(color)
        var red = CGFloat.zero
        var green = CGFloat.zero
        var blue = CGFloat.zero
        guard uiColor.getRed(&red, green: &green, blue: &blue, alpha: nil) else {
            return nil
        }
        return .init(red: Double(red), green: Double(green), blue: Double(blue))
#elseif os(macOS)
        let nsColor = NSColor(color)
        guard let converted = nsColor.usingColorSpace(.deviceRGB) else {
            return nil
        }
        return .init(
            red: Double(converted.redComponent),
            green: Double(converted.greenComponent),
            blue: Double(converted.blueComponent)
        )
#else
        return nil
#endif
    }
}

#Preview {
    NavigationStack {
        PlayerSettingsView(model: PlayerModel())
    }
}
