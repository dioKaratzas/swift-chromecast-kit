//
//  ChromecastKit
//  Swift package for Google Cast (Chromecast).
//

import SwiftUI
import ChromecastKit

struct DiscoverySidebarView: View {
    @Bindable var model: ShowcaseAppModel

    var body: some View {
        List(selection: $model.selectedDeviceID) {
            Section {
                LabeledContent("State") {
                    DiscoveryStateLabel(state: model.discoveryState)
                }
                LabeledContent("Devices") {
                    Text(model.devices.count, format: .number)
                        .monospacedDigit()
                }
                if let error = model.latestUserError {
                    LabeledContent("Last Error") {
                        Text(error)
                            .foregroundStyle(.orange)
                            .lineLimit(2)
                    }
                }
            } header: {
                Text("Discovery")
            }

            Section("Devices") {
                ForEach(model.devices, id: \.id) { device in
                    DeviceSidebarRow(device: device, isConnected: model.connectedDeviceID == device.id)
                        .tag(Optional(device.id))
                }
            }

            Section("Connection") {
                LabeledContent("Session") {
                    ConnectionStatePill(state: model.sessionConnectionState)
                }

                if let selected = model.selectedDevice {
                    HStack {
                        if model.connectedDeviceID == selected.id {
                            Button("Reconnect") {
                                model.reconnectSessionButtonTapped()
                            }
                            .help("Reconnect the session to the selected device")

                            Button("Disconnect") {
                                model.disconnectSessionButtonTapped()
                            }
                            .keyboardShortcut(.cancelAction)
                            .help("Disconnect the current session")
                        } else {
                            Button("Connect") {
                                model.connectSelectedDeviceButtonTapped()
                            }
                            .disabled(model.canConnectSelectedDevice == false)
                            .help("Connect to the selected device")

                            if model.connectedDeviceID != nil {
                                Button("Disconnect Current") {
                                    model.disconnectSessionButtonTapped()
                                }
                                .help("Disconnect the currently connected device before switching")
                            }
                        }
                    }

                    Text("Selected: \(selected.friendlyName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text("Select a device from the Devices list to connect.")
                        .foregroundStyle(.secondary)
                }

                if let connectedID = model.connectedDeviceID,
                   connectedID != model.selectedDeviceID,
                   let connectedDevice = model.devices.first(where: { $0.id == connectedID }) {
                    Text("Connected: \(connectedDevice.friendlyName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Section("Recent Discovery Events") {
                if model.discoveryLog.isEmpty {
                    Text("No events yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.discoveryLog.prefix(20)) { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.message)
                                .lineLimit(2)
                            Text(entry.timestamp, format: .dateTime.hour().minute().second())
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Chromecasts")
        .toolbar {
            ToolbarItemGroup {
                switch model.discoveryState {
                case .running, .starting:
                    Button {
                        model.stopDiscoveryButtonTapped()
                    } label: {
                        Label("Stop Scan", systemImage: "stop.circle")
                    }
                    .help("Stop Bonjour discovery scanning")
                case .stopped, .failed:
                    Button {
                        model.startDiscoveryButtonTapped()
                    } label: {
                        Label("Start Scan", systemImage: "play.circle")
                    }
                    .help("Start Bonjour discovery scanning")
                }

                Button {
                    model.refreshDiscoverySnapshotButtonTapped()
                } label: {
                    Label("Refresh Devices", systemImage: "arrow.clockwise")
                }
                .help("Refresh the sidebar from the current discovery snapshot")
            }
        }
        .overlay {
            if model.devices.isEmpty {
                ContentUnavailableView(
                    "No Devices",
                    systemImage: "dot.radiowaves.left.and.right",
                    description: Text("Start discovery and allow local network access to find Chromecast devices.")
                )
            }
        }
    }
}

private struct ConnectionStatePill: View {
    let state: CastSession.ConnectionState

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .foregroundStyle(tint)
    }

    private var title: String {
        switch state {
        case .disconnected: "Disconnected"
        case .connecting: "Connecting"
        case .connected: "Connected"
        case .reconnecting: "Reconnecting"
        case .failed: "Failed"
        }
    }

    private var systemImage: String {
        switch state {
        case .disconnected: "pause.circle"
        case .connecting: "hourglass.circle"
        case .connected: "checkmark.circle"
        case .reconnecting: "arrow.trianglehead.clockwise"
        case .failed: "exclamationmark.triangle"
        }
    }

    private var tint: Color {
        switch state {
        case .disconnected: .secondary
        case .connecting, .reconnecting: .orange
        case .connected: .green
        case .failed: .red
        }
    }
}

private struct DeviceSidebarRow: View {
    let device: CastDeviceDescriptor
    let isConnected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(device.friendlyName)
                    .font(.headline)
                    .lineLimit(1)
                if isConnected {
                    Image(systemName: "link.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                        .help("Connected in current session")
                }
            }
            Text("\(device.host):\(device.port)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            HStack(spacing: 8) {
                if let modelName = device.modelName, modelName.isEmpty == false {
                    Text(modelName)
                        .lineLimit(1)
                }
                if device.capabilities.isEmpty == false {
                    Text(device.capabilities.map(\.rawValue).sorted().joined(separator: ", "))
                        .lineLimit(1)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

private struct DiscoveryStateLabel: View {
    let state: CastDiscoveryState

    var body: some View {
        Label(title, systemImage: image)
            .foregroundStyle(tint)
    }

    private var title: String {
        switch state {
        case .stopped: "Stopped"
        case .starting: "Starting"
        case .running: "Running"
        case .failed: "Failed"
        }
    }

    private var image: String {
        switch state {
        case .stopped: "pause.circle"
        case .starting: "hourglass.circle"
        case .running: "checkmark.circle"
        case .failed: "exclamationmark.triangle"
        }
    }

    private var tint: Color {
        switch state {
        case .stopped: .secondary
        case .starting: .orange
        case .running: .green
        case .failed: .red
        }
    }
}
