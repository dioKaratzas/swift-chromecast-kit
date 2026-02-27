//
//  ChromecastKit
//  SPDX-License-Identifier: Apache-2.0
//  Copyright 2026 Dionysis Karatzas
//

import AVKit
import SwiftUI

struct PlayerSurfaceView: View {
    @Bindable var model: PlayerModel
    @State private var isDropTargeted = false

    var body: some View {
        ZStack(alignment: .bottom) {
            if model.hasLoadedLocalMedia {
                VideoPlayer(player: model.player)
            } else {
                Rectangle()
                    .fill(.black.opacity(0.55))
                    .overlay {
                        Image(systemName: "play.fill")
                            .font(.system(size: 48, weight: .medium))
                            .foregroundStyle(.white.opacity(0.4))
                    }
            }

            if model.currentSubtitleText.isEmpty == false {
                Text(model.currentSubtitleText)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 20 * model.subtitleFontScale, weight: .semibold))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(
                        subtitleColor(from: model.subtitleBackgroundColor)
                            .opacity(model.subtitleBackgroundOpacity),
                        in: RoundedRectangle(cornerRadius: 12)
                    )
                    .foregroundStyle(subtitleColor(from: model.subtitleForegroundColor))
                    .padding(.horizontal, 22)
                    .padding(.bottom, 26)
            }

            if isDropTargeted {
                Rectangle()
                    .stroke(Color.blue, style: StrokeStyle(lineWidth: 3, dash: [8]))
                    .padding(2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topLeading) {
            HStack(spacing: 8) {
                Text(model.localMediaTitle)
                    .font(.caption)
                    .lineLimit(1)
                if model.hasSubtitle {
                    Image(systemName: "captions.bubble.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.black.opacity(0.45), in: Capsule())
            .foregroundStyle(.white.opacity(0.82))
            .padding(10)
        }
        .dropDestination(for: URL.self) { urls, _ in
            model.handleDroppedFiles(urls)
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
    }

    private func subtitleColor(from value: PlayerModel.SubtitleRGBColor) -> Color {
        Color(red: value.red, green: value.green, blue: value.blue)
    }
}
