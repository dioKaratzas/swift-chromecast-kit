//
//  ChromecastKit
//  Swift package for Google Cast (Chromecast).
//

import SwiftUI
import ChromecastKit

struct DiscoveryFeatureView: View {
    @Bindable var model: DiscoveryFeatureModel
    @State private var selectedDeviceID: CastDeviceID?

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar { toolbarContent }
        .task { model.onAppear() }
        .onChange(of: model.devices) { _, devices in
            guard let selectedDeviceID else {
                if let first = devices.first?.id {
                    self.selectedDeviceID = first
                }
                return
            }

            if devices.contains(where: { $0.id == selectedDeviceID }) == false {
                self.selectedDeviceID = devices.first?.id
            }
        }
    }

    private var sidebar: some View {
        List(selection: $selectedDeviceID) {
            Section("Devices") {
                ForEach(model.devices, id: \.id) { device in
                    DeviceSidebarRow(device: device)
                        .tag(Optional(device.id))
                }
            }
        }
        .navigationTitle("Chromecasts")
        .overlay {
            if model.devices.isEmpty {
                ContentUnavailableView(
                    "No Devices",
                    systemImage: "dot.radiowaves.left.and.right",
                    description: Text("Start discovery to browse Chromecast devices on your local network.")
                )
            }
        }
    }

    private var detail: some View {
        List {
            Section("Discovery") {
                LabeledContent("State") {
                    Label(phaseLabelText, systemImage: phaseSystemImage)
                        .foregroundStyle(phaseTint)
                }
                LabeledContent("Devices") {
                    Text(model.devices.count, format: .number)
                        .monospacedDigit()
                }
                if let latestError = model.latestError {
                    LabeledContent("Last Error") {
                        Text(latestError)
                            .foregroundStyle(.orange)
                    }
                }
            }

            if let selectedDevice {
                Section("Selected Device") {
                    LabeledContent("Name") { Text(selectedDevice.friendlyName) }
                    LabeledContent("Identifier") {
                        Text(selectedDevice.id.rawValue)
                            .font(.footnote.monospaced())
                            .textSelection(.enabled)
                    }
                    LabeledContent("Host") {
                        Text("\(selectedDevice.host):\(selectedDevice.port)")
                            .textSelection(.enabled)
                    }
                    if let modelName = selectedDevice.modelName {
                        LabeledContent("Model") { Text(modelName) }
                    }
                    if let manufacturer = selectedDevice.manufacturer {
                        LabeledContent("Manufacturer") { Text(manufacturer) }
                    }
                    if selectedDevice.capabilities.isEmpty == false {
                        LabeledContent("Capabilities") {
                            Text(selectedDevice.capabilities
                                .map(\.rawValue)
                                .sorted()
                                .joined(separator: ", "))
                        }
                    }
                }
            } else {
                Section {
                    ContentUnavailableView(
                        "Select a Device",
                        systemImage: "tv",
                        description: Text("Pick a discovered Chromecast from the sidebar to inspect its details.")
                    )
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }

            Section("Recent Events") {
                if model.eventLog.isEmpty {
                    Text("No events yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.eventLog.prefix(100)) { entry in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
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
        .navigationTitle(selectedDevice?.friendlyName ?? "ChromecastKit Example")
    }

    private var selectedDevice: CastDeviceDescriptor? {
        guard let selectedDeviceID else {
            return nil
        }
        return model.devices.first(where: { $0.id == selectedDeviceID })
    }

    private var phaseLabelText: String {
        switch model.phase {
        case .idle:
            return "Idle"
        case .starting:
            return "Starting"
        case .running:
            return "Running"
        case .failed:
            return "Failed"
        }
    }

    private var phaseSystemImage: String {
        switch model.phase {
        case .idle:
            return "pause.circle"
        case .starting:
            return "hourglass.circle"
        case .running:
            return "checkmark.circle"
        case .failed:
            return "exclamationmark.triangle"
        }
    }

    private var phaseTint: Color {
        switch model.phase {
        case .idle:
            return .secondary
        case .starting:
            return .orange
        case .running:
            return .green
        case .failed:
            return .red
        }
    }

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            Button {
                model.refreshSnapshot()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }

            Button {
                model.clearDiscoveredDevices()
            } label: {
                Label("Clear", systemImage: "trash")
            }

            if model.phase.isRunning || model.phase == .starting {
                Button {
                    model.stopDiscovery()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
            } else {
                Button {
                    model.startDiscovery()
                } label: {
                    Label("Start", systemImage: "play.fill")
                }
            }
        }
    }
}

private struct DeviceSidebarRow: View {
    let device: CastDeviceDescriptor

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(device.friendlyName)
                .font(.headline)
                .lineLimit(1)
            Text("\(device.host):\(device.port)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if let modelName = device.modelName {
                Text(modelName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    DiscoveryFeatureView(model: DiscoveryFeatureModel())
}
