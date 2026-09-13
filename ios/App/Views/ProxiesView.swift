import SwiftUI

struct ProxiesView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        Group {
            if store.groups.isEmpty {
                ContentUnavailableView {
                    Label("No proxy groups", systemImage: "network")
                } description: {
                    Text("Select a profile to view its proxy groups. Provider nodes become available after connecting.")
                }
            } else {
                List {
                    if !store.isConnected {
                        Text("Your selections will be applied when you connect. Connect to measure latency and load provider nodes.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(store.groups) { group in
                        NavigationLink {
                            ProxyGroupView(groupName: group.name)
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(group.name).font(.headline)
                                Text(group.now ?? String(localized: "No selection"))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Text(group.type)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 3)
                        }
                    }
                }
            }
        }
        .navigationTitle("Proxies")
        .refreshable { await store.reload() }
    }
}

private struct ProxyGroupView: View {
    @Environment(AppStore.self) private var store
    let groupName: String

    var body: some View {
        Group {
            if let group = store.groups.first(where: { $0.name == groupName }) {
                List {
                    if !group.canSelect {
                        Text("This group selects its proxy automatically.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if group.all.isEmpty {
                        Text("No nodes are available in this group. Connect to load any configured proxy providers.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(Array(group.all.enumerated()), id: \.offset) { _, node in
                        ProxyNodeRow(group: group, node: node)
                    }
                }
            } else {
                ContentUnavailableView("Group unavailable", systemImage: "network", description:
                    Text("The active profile has changed. Return to the proxy list.")
                )
            }
        }
        .navigationTitle(groupName)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ProxyNodeRow: View {
    @Environment(AppStore.self) private var store
    @State private var isTesting = false
    let group: ProxyGroup
    let node: String

    var body: some View {
        HStack(spacing: 12) {
            Button {
                Task { await store.selectProxy(group: group.name, node: node) }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: group.now == node ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(group.now == node ? Color.purple : Color.secondary)
                    Text(node)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .multilineTextAlignment(.leading)
                }
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(!group.canSelect || store.isBusy)
            .accessibilityAddTraits(group.now == node ? .isSelected : [])
            Button {
                isTesting = true
                Task {
                    await store.testDelay(node: node)
                    isTesting = false
                }
            } label: {
                if isTesting {
                    ProgressView()
                } else if let delay = store.delays[node] {
                    if delay > 0 {
                        Text("\(delay) ms").font(.caption.monospacedDigit())
                    } else {
                        Text("Timeout").font(.caption)
                    }
                } else {
                    Image(systemName: "waveform.path.ecg")
                }
            }
            .frame(minWidth: 44, minHeight: 44)
            .buttonStyle(.borderless)
            .disabled(!store.isConnected || isTesting || store.isBusy)
            .accessibilityLabel("Test latency for \(node)")
        }
    }
}
