import SwiftUI

struct DashboardView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        List {
            Section {
                ConnectionPanel()
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 20, leading: 0, bottom: 20, trailing: 0))
            }
            Section("Active profile") {
                if let profile = store.profiles.selectedProfile {
                    Label(profile.name, systemImage: "doc.text.fill")
                    NavigationLink("Manage profiles") { ProfilesView() }
                } else {
                    Text("Import a Clash YAML subscription or file to get started.")
                        .foregroundStyle(.secondary)
                    NavigationLink("Add a profile") { ProfilesView() }
                }
            }
            Section {
                Picker("Routing mode", selection: Binding(
                    get: { store.mode },
                    set: { mode in Task { await store.changeMode(mode) } }
                )) {
                    ForEach(ProxyMode.allCases) { mode in
                        Text(LocalizedStringKey(mode.title)).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(store.isBusy)
            } header: {
                Text("Routing mode")
            } footer: {
                Text("Rule follows the profile's routing rules. Global sends traffic through the global proxy group. Direct bypasses proxies.")
            }
            Section("Current session") {
                LabeledContent("Downloaded", value: ByteCountFormatter.string(
                    fromByteCount: store.downloadTotal, countStyle: .binary
                ))
                LabeledContent("Uploaded", value: ByteCountFormatter.string(
                    fromByteCount: store.uploadTotal, countStyle: .binary
                ))
                LabeledContent("Connections", value: store.connectionCount.formatted())
            }
        }
        .navigationTitle("Clash Verge")
        .refreshable { await store.reload() }
    }
}

private struct ConnectionPanel: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: store.isConnected ? "shield.lefthalf.filled" : "shield")
                .font(.system(size: 42, weight: .medium))
                .foregroundStyle(store.isConnected ? Color.purple : Color.secondary)
                .frame(width: 96, height: 96)
                .background(.purple.opacity(0.10), in: Circle())
                .accessibilityHidden(true)
            Text(LocalizedStringKey(store.statusText))
                .font(.title3.weight(.semibold))
                .accessibilityAddTraits(.updatesFrequently)
            Button {
                Task {
                    if store.isConnected {
                        await store.disconnect()
                    } else {
                        await store.connect()
                    }
                }
            } label: {
                HStack {
                    if store.isBusy { ProgressView().tint(.white) }
                    Text(store.isConnected ? LocalizedStringKey("Disconnect") : LocalizedStringKey("Connect"))
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity, minHeight: 34)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(store.isBusy || (!store.isConnected && store.profiles.selectedProfile == nil))
            if !store.isConnected {
                Text("iOS will ask permission to add a VPN configuration on first connection.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
