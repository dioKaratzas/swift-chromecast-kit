//
//  ChromecastKit
//  SPDX-License-Identifier: Apache-2.0
//  Copyright 2026 Dionysis Karatzas
//

import SwiftUI

struct SubtitleTracksMenu: View {
    @Bindable var model: PlayerModel

    var body: some View {
        Menu {
            Button {
                model.selectSubtitleTrack(nil)
            } label: {
                Label(
                    "Off",
                    systemImage: model.selectedSubtitleTrackID == nil ? "checkmark" : "captions.bubble"
                )
            }

            if model.subtitleTracks.isEmpty {
                Text("Drop one or more .vtt files")
            } else {
                ForEach(model.subtitleTracks) { track in
                    Button {
                        model.selectSubtitleTrack(track.id)
                    } label: {
                        Label(
                            track.fileURL.lastPathComponent,
                            systemImage: model.selectedSubtitleTrackID == track.id ? "checkmark" : "captions.bubble"
                        )
                    }
                }

                Divider()

                if model.selectedSubtitleTrackID != nil {
                    Button("Remove selected subtitle") {
                        model.removeSelectedSubtitleTrackButtonTapped()
                    }
                }

                Button("Clear all subtitles") {
                    model.clearAllSubtitlesButtonTapped()
                }
            }
        } label: {
            Image(systemName: model.hasSubtitle ? "captions.bubble.fill" : "captions.bubble")
                .foregroundStyle(.white.opacity(0.92))
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
    }
}
