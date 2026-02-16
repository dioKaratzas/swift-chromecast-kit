//
//  ChromecastKit
//  Swift package for Google Cast (Chromecast).
//

import SwiftUI
import ChromecastKit

struct ShowcaseRootView: View {
    @Bindable var model: ShowcaseAppModel

    var body: some View {
        NavigationSplitView {
            DiscoverySidebarView(model: model)
        } detail: {
            if let device = model.selectedDevice {
                DeviceWorkspaceView(model: model, device: device)
            } else {
                ContentUnavailableView(
                    "Select a Chromecast",
                    systemImage: "tv",
                    description: Text(
                        "Choose a device from the sidebar to inspect status, connect, and try receiver/media/namespace demos."
                    )
                )
            }
        }
        .navigationSplitViewStyle(.balanced)
        .task { model.onAppear() }
    }
}

private struct DeviceWorkspaceView: View {
    @Bindable var model: ShowcaseAppModel
    let device: CastDeviceDescriptor

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SessionDashboardHeaderView(model: model, device: device)

            TabView(selection: $model.selectedTab) {
                SessionDashboardView(model: model)
                    .tabItem { Label("Session", systemImage: "dot.radiowaves.left.and.right") }
                    .tag(ShowcaseAppModel.DetailTab.overview)

                ReceiverControlsView(model: model)
                    .tabItem { Label("Receiver", systemImage: "tv") }
                    .tag(ShowcaseAppModel.DetailTab.receiver)

                MediaPlaygroundView(model: model)
                    .tabItem { Label("Media", systemImage: "play.rectangle") }
                    .tag(ShowcaseAppModel.DetailTab.media)

                NamespaceConsoleView(model: model)
                    .tabItem { Label("Namespaces", systemImage: "chevron.left.forwardslash.chevron.right") }
                    .tag(ShowcaseAppModel.DetailTab.namespace)
            }
        }
        .padding()
        .navigationTitle(device.friendlyName)
    }
}

private struct SessionDashboardHeaderView: View {
    @Bindable var model: ShowcaseAppModel
    let device: CastDeviceDescriptor

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(device.friendlyName)
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                ConnectionStateBadge(state: model.sessionConnectionState)
            }

            Text("\(device.host):\(device.port)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            HStack(spacing: 12) {
                if let modelName = device.modelName, modelName.isEmpty == false {
                    Label(modelName, systemImage: "cpu")
                        .foregroundStyle(.secondary)
                }
                if let manufacturer = device.manufacturer, manufacturer.isEmpty == false {
                    Label(manufacturer, systemImage: "building.2")
                        .foregroundStyle(.secondary)
                }
                if device.capabilities.isEmpty == false {
                    Label(device.capabilities.map(\.rawValue).sorted().joined(separator: ", "), systemImage: "checklist")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .font(.caption)
        }
        .padding(.bottom, 4)
    }
}

private struct ConnectionStateBadge: View {
    let state: CastSession.ConnectionState

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.medium))
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
