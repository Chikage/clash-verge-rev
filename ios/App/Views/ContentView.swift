import SwiftUI

struct ContentView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        VStack(spacing: 0) {
            if let message = store.errorMessage {
                ErrorBanner(message: message) { store.errorMessage = nil }
            }
            TabView {
                NavigationStack { DashboardView() }
                    .tabItem { Label("Overview", systemImage: "house") }
                NavigationStack { ProxiesView() }
                    .tabItem { Label("Proxies", systemImage: "network") }
                NavigationStack { ProfilesView() }
                    .tabItem { Label("Profiles", systemImage: "doc.text") }
                NavigationStack { SettingsView() }
                    .tabItem { Label("Settings", systemImage: "gearshape") }
            }
        }
        .tint(.purple)
    }
}

private struct ErrorBanner: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
                .accessibilityHidden(true)
            Text(message)
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            Button("Dismiss", systemImage: "xmark", action: dismiss)
                .labelStyle(.iconOnly)
                .frame(minWidth: 44, minHeight: 44)
        }
        .padding()
        .background(.red.opacity(0.08))
        .accessibilityElement(children: .contain)
    }
}
