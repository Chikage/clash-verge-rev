import SwiftUI

struct DashboardView: View {
    @Environment(AppStore.self) private var store
    @State private var showsProfiles = false

    var body: some View {
        List {
            Section {
                ConnectionPanel(addProfile: { showsProfiles = true })
                    .listRowInsets(EdgeInsets(top: 20, leading: 20, bottom: 20, trailing: 20))
            }
            if let profile = store.profiles.selectedProfile {
                Section("Active profile") {
                    Label {
                        Text(profile.name)
                            .font(.headline)
                    } icon: {
                        Image(systemName: "doc.text.fill")
                            .foregroundStyle(AppTheme.accent)
                    }
                    NavigationLink("Manage profiles") { ProfilesView() }
                }
            }
            Section {
                RoutingModePicker()
            } header: {
                Text("Routing mode")
            } footer: {
                Text("Rule follows the profile's routing rules. Global sends traffic through the global proxy group. Direct bypasses proxies.")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.secondaryText)
                    .lineSpacing(3)
            }
            Section("Current session") {
                SessionMetricRow(title: "Downloaded", systemImage: "arrow.down.circle", value:
                    ByteCountFormatter.string(fromByteCount: store.downloadTotal, countStyle: .binary)
                )
                SessionMetricRow(title: "Uploaded", systemImage: "arrow.up.circle", value:
                    ByteCountFormatter.string(fromByteCount: store.uploadTotal, countStyle: .binary)
                )
                SessionMetricRow(title: "Connections", systemImage: "network", value: store.connectionCount.formatted())
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Clash Verge")
        .navigationDestination(isPresented: $showsProfiles) { ProfilesView() }
        .refreshable { await store.reload() }
    }
}

private struct ConnectionPanel: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title2) private var iconSize = 28
    let addProfile: () -> Void

    var body: some View {
        let statusLayout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
            : AnyLayout(HStackLayout(spacing: 16))

        VStack(alignment: .leading, spacing: 20) {
            statusLayout {
                Image(systemName: store.isConnected ? "checkmark.shield.fill" : "shield")
                    .font(.system(size: iconSize, weight: .medium))
                    .foregroundStyle(store.isConnected ? AppTheme.success : AppTheme.secondaryText)
                    .padding(16)
                    .background(
                        (store.isConnected ? AppTheme.success : AppTheme.secondaryText).opacity(0.10),
                        in: RoundedRectangle(cornerRadius: 18)
                    )
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text(LocalizedStringKey(store.statusText))
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(store.isConnected ? AppTheme.success : Color.primary)
                        .accessibilityAddTraits(.updatesFrequently)
                    Text(LocalizedStringKey(store.profiles.selectedProfile == nil
                         ? "Import a Clash YAML subscription or file to get started."
                         : "Your connection is controlled here."))
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !store.isConnected && store.profiles.selectedProfile == nil {
                Button(action: addProfile) {
                    Label("Add a profile", systemImage: "plus")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 30)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.action)
                .foregroundStyle(.white)
                .controlSize(.large)
                .disabled(store.isBusy)
            } else {
                Button {
                    Task {
                        if store.isConnected {
                            await store.disconnect()
                        } else {
                            await store.connect()
                        }
                    }
                } label: {
                    HStack(spacing: 10) {
                        if store.isBusy { ProgressView().tint(.white) }
                        Text(store.isConnected ? LocalizedStringKey("Disconnect") : LocalizedStringKey("Connect"))
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity, minHeight: 30)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.action)
                .foregroundStyle(.white)
                .controlSize(.large)
                .disabled(store.isBusy)
            }
            if !store.isConnected && store.profiles.selectedProfile != nil {
                Text("iOS will ask permission to add a VPN configuration on first connection.")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct RoutingModePicker: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let picker = Picker("Routing mode", selection: Binding(
            get: { store.mode },
            set: { mode in Task { await store.changeMode(mode) } }
        )) {
            ForEach(ProxyMode.allCases) { mode in
                Text(LocalizedStringKey(mode.title)).tag(mode)
            }
        }
        .disabled(store.isBusy)

        if dynamicTypeSize.isAccessibilitySize {
            picker.pickerStyle(.inline)
        } else {
            picker.pickerStyle(.segmented)
        }
    }
}

private struct SessionMetricRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title: LocalizedStringKey
    let systemImage: String
    let value: String

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 12))

        layout {
            Label {
                Text(title)
                    .foregroundStyle(AppTheme.secondaryText)
            } icon: {
                Image(systemName: systemImage)
                    .foregroundStyle(AppTheme.accent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(value)
                .font(.body.weight(.semibold).monospacedDigit())
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
