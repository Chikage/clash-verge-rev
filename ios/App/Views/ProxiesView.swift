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
                        .foregroundStyle(AppTheme.secondaryText)
                }
            } else {
                List {
                    if !store.isConnected {
                        Text("Your selections will be applied when you connect. Connect to measure latency and load provider nodes.")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.secondaryText)
                            .lineSpacing(3)
                    }
                    ForEach(store.groups) { group in
                        NavigationLink {
                            ProxyGroupView(groupName: group.name)
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(group.name).font(.headline)
                                Text(group.now ?? String(localized: "No selection"))
                                    .font(.subheadline)
                                    .foregroundStyle(group.now == nil ? AppTheme.secondaryText : AppTheme.accent)
                                Text(group.type)
                                    .font(.footnote)
                                    .foregroundStyle(AppTheme.secondaryText)
                            }
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.vertical, 6)
                        }
                    }
                }
                .listStyle(.insetGrouped)
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
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.secondaryText)
                            .lineSpacing(3)
                    }
                    if group.all.isEmpty {
                        Text("No nodes are available in this group. Connect to load any configured proxy providers.")
                            .foregroundStyle(AppTheme.secondaryText)
                            .lineSpacing(3)
                    }
                    ForEach(Array(group.all.enumerated()), id: \.offset) { _, node in
                        ProxyNodeRow(group: group, node: node)
                    }
                }
                .listStyle(.insetGrouped)
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var isTesting = false
    let group: ProxyGroup
    let node: String

    private var isSelected: Bool { group.now == node }

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(spacing: 12))

        layout {
            Button {
                Task { await store.selectProxy(group: group.name, node: node) }
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? AppTheme.accent : AppTheme.secondaryText)
                        .padding(.top, 2)
                        .accessibilityHidden(true)
                    Text(node)
                        .fontWeight(isSelected ? .semibold : .regular)
                        .foregroundStyle(isSelected ? AppTheme.accent : Color.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(minHeight: 44)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(!group.canSelect || store.isBusy)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            Button {
                isTesting = true
                Task {
                    await store.testDelay(node: node)
                    isTesting = false
                }
            } label: {
                Group {
                    if isTesting {
                        ProgressView()
                    } else if let delay = store.delays[node] {
                        if delay > 0 {
                            Text("\(delay) ms")
                                .foregroundStyle(delay >= 300 ? AppTheme.warning : AppTheme.success)
                        } else {
                            Text("Timeout")
                                .foregroundStyle(AppTheme.error)
                        }
                    } else {
                        Image(systemName: "waveform.path.ecg")
                            .foregroundStyle(AppTheme.accent)
                    }
                }
                .font(.subheadline.monospacedDigit())
                .frame(minWidth: 44, minHeight: 44)
                .fixedSize(horizontal: true, vertical: false)
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(!store.isConnected || isTesting || store.isBusy)
            .accessibilityLabel("Test latency for \(node)")
            .accessibilityValue(latencyValue)
        }
        .listRowBackground(isSelected ? AppTheme.accent.opacity(0.08) : Color(uiColor: .secondarySystemGroupedBackground))
    }

    private var latencyValue: Text {
        if isTesting { return Text("Testing…") }
        if let delay = store.delays[node] {
            return delay > 0 ? Text("\(delay) ms") : Text("Timeout")
        }
        return Text("Not measured")
    }
}
