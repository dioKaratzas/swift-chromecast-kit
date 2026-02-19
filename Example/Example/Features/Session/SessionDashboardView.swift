//
//  ChromecastKit
//  Swift package for Google Cast (Chromecast).
//

import SwiftUI
import ChromecastKit

struct SessionDashboardView: View {
    @Bindable var model: ShowcaseAppModel

    var body: some View {
        List {
            Section("Connection") {
                LabeledContent("State") {
                    Text(connectionStateDescription)
                }
                LabeledContent("Connected Device") {
                    Text(model.connectedDeviceID?.rawValue ?? "None")
                        .font(.footnote.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                LabeledContent("Auto Reconnect") {
                    Text(model.sessionConfiguration.autoReconnect ? "On" : "Off")
                }
                LabeledContent("Reconnect Delay") {
                    Text(
                        "\(model.sessionConfiguration.reconnectRetryDelay, format: .number.precision(.fractionLength(0 ... 2)))s"
                    )
                }
                HStack {
                    Button("Refresh Snapshot") {
                        model.refreshSessionSnapshotButtonTapped()
                    }
                    .disabled(model.session == nil)

                    Spacer()
                }
            }

            Section("Receiver Status") {
                if let receiver = model.sessionSnapshot.receiverStatus {
                    LabeledContent("Volume") {
                        Text("\(Int(receiver.volume.level * 100))%")
                    }
                    LabeledContent("Muted") {
                        Text(receiver.volume.muted ? "Yes" : "No")
                    }
                    LabeledContent("Standby") {
                        Text(receiver.isStandBy.map { $0 ? "Yes" : "No" } ?? "Unknown")
                    }
                    LabeledContent("Active Input") {
                        Text(receiver.isActiveInput.map { $0 ? "Yes" : "No" } ?? "Unknown")
                    }
                } else {
                    Text("No receiver status yet. Connect and request receiver status.")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Current App") {
                if let app = model.currentApp {
                    LabeledContent("Display Name") { Text(app.displayName) }
                    LabeledContent("App ID") {
                        Text(app.appID.rawValue)
                            .font(.footnote.monospaced())
                            .textSelection(.enabled)
                    }
                    LabeledContent("Session ID") {
                        Text(app.sessionID?.rawValue ?? "None")
                            .font(.footnote.monospaced())
                            .textSelection(.enabled)
                    }
                    LabeledContent("Transport ID") {
                        Text(app.transportID?.rawValue ?? "None")
                            .font(.footnote.monospaced())
                            .textSelection(.enabled)
                    }
                    LabeledContent("Status Text") {
                        Text(app.statusText ?? "—")
                    }
                    if app.namespaces.isEmpty == false {
                        LabeledContent("Namespaces") {
                            Text(app.namespaces.joined(separator: ", "))
                                .font(.footnote)
                        }
                    }
                } else {
                    Text("No running app reported yet.")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Multizone / Groups") {
                HStack {
                    Button("Get Multizone Status") {
                        model.multizoneGetStatusButtonTapped()
                    }
                    .disabled(model.session == nil)

                    Button("Get Casting Groups") {
                        model.multizoneGetCastingGroupsButtonTapped()
                    }
                    .disabled(model.session == nil)
                }

                if let multizone = model.sessionSnapshot.multizoneStatus {
                    LabeledContent("Members") {
                        Text("\(multizone.members.count)")
                    }
                    if multizone.members.isEmpty == false {
                        ForEach(multizone.members) { member in
                            LabeledContent(member.name) {
                                Text(member.id.rawValue)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                    }

                    LabeledContent("Casting Groups") {
                        Text("\(multizone.castingGroups.count)")
                    }
                    if multizone.castingGroups.isEmpty == false {
                        ForEach(multizone.castingGroups) { group in
                            LabeledContent(group.name) {
                                Text(group.id.rawValue)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                } else {
                    Text("No multizone status yet. Useful for speaker groups and multizone-capable audio devices.")
                        .foregroundStyle(.secondary)
                }
            }

            if model.showsNetflixCapabilityNote {
                Section("Netflix / App-Specific Protocol Note") {
                    Text(
                        "This Chromecast is running Netflix. ChromecastKit can connect to the device and control receiver-level features (volume, mute, stop app) and detect the running app. Playback title/progress/media controls for Netflix usually require Netflix-specific Cast namespaces/protocol support."
                    )
                    .foregroundStyle(.secondary)
                }
            } else {
                Section("Protocol Capability Note") {
                    Text(
                        "Receiver-level status and controls work with any app. Media status and playback controls depend on the active app supporting the standard Cast media namespace (`com.google.cast.media`)."
                    )
                    .foregroundStyle(.secondary)
                }
            }

            Section("Media Status") {
                if let media = model.sessionSnapshot.mediaStatus {
                    LabeledContent("Player State") { Text(media.playerState.rawValue) }
                    LabeledContent("Time") {
                        Text("\(media.adjustedCurrentTime, format: .number.precision(.fractionLength(0 ... 1)))s")
                            .monospacedDigit()
                    }
                    LabeledContent("Duration") {
                        if let duration = media.duration {
                            Text("\(duration, format: .number.precision(.fractionLength(0 ... 1)))s")
                                .monospacedDigit()
                        } else {
                            Text("—")
                        }
                    }
                    LabeledContent("Media Session ID") {
                        Text(media.mediaSessionID.map { String($0.rawValue) } ?? "None")
                            .font(.footnote.monospaced())
                    }
                    LabeledContent("Content Type") { Text(media.contentType ?? "—") }
                    LabeledContent("URL") {
                        Text(media.contentURL?.absoluteString ?? "—")
                            .font(.footnote)
                            .lineLimit(2)
                            .textSelection(.enabled)
                    }
                    if let metadata = media.metadata {
                        LabeledContent("Metadata") { Text(summary(for: metadata)) }
                    }
                    LabeledContent("Active Tracks") {
                        Text(media.activeTextTrackIDs.map { String($0.rawValue) }.joined(separator: ", ").ifEmpty("—"))
                    }
                    LabeledContent("Queue") {
                        Text(
                            "current=\(media.queueCurrentItemID.map { String($0.rawValue) } ?? "—"), repeat=\(media.queueRepeatMode?.rawValue ?? "—")"
                        )
                    }
                } else {
                    Text("No media status yet.")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Session Events") {
                if model.sessionLog.isEmpty {
                    Text("No session events yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.sessionLog.prefix(120)) { entry in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(entry.timestamp, format: .dateTime.hour().minute().second())
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Text(entry.message)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
        }
        .listStyle(.inset)
    }

    private var connectionStateDescription: String {
        switch model.sessionConnectionState {
        case .disconnected: "Disconnected"
        case .connecting: "Connecting"
        case .connected: "Connected"
        case .reconnecting: "Reconnecting"
        case let .failed(error): "Failed (\(String(describing: error)))"
        }
    }

    private func summary(for metadata: CastMediaMetadata) -> String {
        switch metadata {
        case let .generic(value): value.title ?? value.subtitle ?? "Generic"
        case let .movie(value): value.title ?? value.subtitle ?? "Movie"
        case let .tvShow(value): value.title ?? value.seriesTitle ?? "TV Show"
        case let .musicTrack(value): value.title ?? value.artist ?? "Music"
        case let .photo(value): value.title ?? value.location ?? "Photo"
        }
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String {
        isEmpty ? fallback : self
    }
}
