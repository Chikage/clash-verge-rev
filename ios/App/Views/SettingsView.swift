import SwiftUI

struct SettingsView: View {
    var body: some View {
        List {
            Section("VPN") {
                Label("On-device proxy", systemImage: "iphone")
                Text("The VPN extension runs the proxy core on this device. The selected profile controls servers, DNS, and routing rules.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("Closing the app does not disconnect the VPN. Disconnect from Overview or in iOS Settings.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("Profiles") {
                Text("Subscriptions and imported YAML files are stored on this device. Subscription links may contain access credentials; keep them private.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("To refresh a subscription, open its actions menu in Profiles and choose Update subscription.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("About") {
                LabeledContent("Version", value:
                    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
                )
                Link(destination: URL(string: "https://github.com/clash-verge-rev/clash-verge-rev")!) {
                    Label("Clash Verge Rev source", systemImage: "arrow.up.right.square")
                }
                Link(destination: URL(string: "https://github.com/ruattd/swihomo-core")!) {
                    Label("Swihomo proxy core", systemImage: "arrow.up.right.square")
                }
                Link(destination: URL(string: "https://www.gnu.org/licenses/gpl-3.0.html")!) {
                    Label("GNU General Public License v3", systemImage: "doc.text")
                }
                Text("A native iOS port based on Clash Verge Rev, powered by the Mihomo-compatible Swihomo core.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
    }
}
