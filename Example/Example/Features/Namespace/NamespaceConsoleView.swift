//
//  ChromecastKit
//  Swift package for Google Cast (Chromecast).
//

import SwiftUI

struct NamespaceConsoleView: View {
    @Bindable var model: ShowcaseAppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Form {
                Section("Send Custom Namespace Message") {
                    TextField("Namespace", text: $model.namespaceFilterString)

                    Picker("Target", selection: $model.namespaceTargetChoice) {
                        ForEach(ShowcaseAppModel.NamespaceTargetChoice.allCases) { choice in
                            Text(choice.title).tag(choice)
                        }
                    }
                    .pickerStyle(.segmented)

                    if model.namespaceTargetChoice == .transport {
                        TextField("Transport ID", text: $model.namespaceTransportTargetID)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("JSON Payload")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextEditor(text: $model.namespacePayloadText)
                            .font(.system(.body, design: .monospaced))
                            .frame(minHeight: 120)
                    }

                    HStack {
                        Button("Send") { model.namespaceSendButtonTapped() }
                        Button("Send & Await Reply") { model.namespaceSendAwaitReplyButtonTapped() }
                    }
                }

                Section("Last Reply") {
                    if model.namespaceReplyText.isEmpty {
                        Text("No reply yet")
                            .foregroundStyle(.secondary)
                    } else {
                        Text(model.namespaceReplyText)
                            .font(.system(.footnote, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
            }
            .formStyle(.grouped)

            GroupBox("Observed Custom Namespace Events") {
                if model.namespaceLog.isEmpty {
                    ContentUnavailableView(
                        "No Custom Namespace Events",
                        systemImage: "tray",
                        description: Text(
                            "Events on non-core namespaces will appear here once a session is connected and an app emits messages."
                        )
                    )
                    .frame(maxWidth: .infinity, minHeight: 180)
                } else {
                    List(model.namespaceLog.prefix(150)) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(entry.namespace)
                                    .font(.system(.body, design: .monospaced))
                                    .lineLimit(1)
                                Spacer()
                                Text(entry.timestamp, format: .dateTime.hour().minute().second())
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            HStack(spacing: 8) {
                                Label(entry.summary, systemImage: entry.isBinary ? "doc.badge.gearshape" : "doc.text")
                                Text("\(entry.sourceID) -> \(entry.destinationID)")
                                    .foregroundStyle(.secondary)
                            }
                            .font(.caption)
                            Text(entry.payloadPreview)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .lineLimit(3)
                        }
                        .padding(.vertical, 2)
                    }
                    .listStyle(.plain)
                    .frame(minHeight: 240)
                }
            }
        }
    }
}
