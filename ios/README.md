# Clash Verge for iOS

A native SwiftUI port for iPhone and iPad running iOS 17 or later. It imports
Clash/Mihomo YAML subscriptions and files, manages profiles, selects proxy nodes,
measures latency, switches rule/global/direct mode, and displays session traffic.
Existing `clash://` and `clash-verge://` subscription import links also work.
The Packet Tunnel extension embeds the real Mihomo core and routes device traffic
through Apple's public `NEPacketTunnelFlow` API. The interface supports English
and Simplified Chinese.

## Build

Use an Apple Silicon Mac, Xcode 26 or newer (Swift 6.2), and XcodeGen 2.44 or newer.
From the repository root:

```sh
bash ios/scripts/build-core.sh
xcodegen generate --spec ios/project.yml
open ios/ClashVerge.xcodeproj
```

The core script verifies a pinned source archive and builds both iPhone ARM64
and ARM64 simulator libraries. It downloads a checksum-pinned Go toolchain into
`ios/Vendor` when Go is absent. If Go's default module proxy is unreachable, run
the script with `GOPROXY=https://goproxy.cn,direct`. Go module checksum verification
remains enabled. See [Core/README.md](Core/README.md) for the exact source and ABI.
Yams is pinned to version 5.4.0's commit in the project specification and resolved
by Xcode. Build outputs and dependency caches are ignored by Git.

For a simulator build:

```sh
xcodebuild -project ios/ClashVerge.xcodeproj -scheme ClashVerge \
  -configuration Debug -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath ios/.build CODE_SIGNING_ALLOWED=NO build
```

For an unsigned device compilation, replace `iphonesimulator` with `iphoneos`
and the destination with `generic/platform=iOS`. Simulator builds can import and
manage profiles; VPN connections require a physical device.

## Run on an iPhone

1. Select an Apple Developer team for both `ClashVerge` and `PacketTunnel` in
   Xcode. The provisioning profiles must permit the Packet Tunnel Network
   Extension and App Groups entitlements.
2. Set the project build setting `VERGE_BUNDLE_ID` to your own unique app ID.
   The extension ID and the app's embedded tunnel identifier derive from this
   setting. Keep both targets on the same team. Enable the same App Group on
   both targets: `VERGE_APP_GROUP` defaults to `group.$(VERGE_BUNDLE_ID)`.
   When upgrading a build made before shared configuration storage was added,
   refresh both provisioning profiles to include this App Group and reinstall
   the app with its extension. Existing subscriptions remain in the app.
3. Run the `ClashVerge` scheme on your iPhone. Add a subscription URL or import a
   YAML file from Files, select the profile and a node, then tap Connect.
4. Allow iOS to add the VPN configuration. Use the Proxies page to change nodes
   and run latency checks while connected.

No signing identity, subscription credentials, or working
proxy nodes are included. A device-signed IPA and end-to-end VPN verification
require your provisioning setup and subscription.

## Porting boundaries

Profile validation and subscription metadata follow the desktop implementation
in `src-tauri/src/config/prfitem.rs`. Proxy selection follows the desktop
`src-tauri/src/feat/profile.rs` behavior. Native SwiftUI replaces the Tauri UI;
Network Extension replaces the desktop service, sidecar and system-proxy guard.
The desktop client remains independently buildable.

Raw profiles are saved unchanged. An in-memory runtime copy removes desktop
listeners/controller settings, enables tunnel DNS, and keeps the subscription's
proxy definitions, rules and DNS upstreams. HTTP providers use the core's local
cache paths. File providers referring to desktop paths must first be converted
to HTTP or inline providers. Base64 node lists and individual proxy URI imports
are not supported; use complete Clash YAML subscriptions.

The first version does not port JavaScript/Merge enhancement chains, WebDAV
backup, rule editing, scheduled background subscription refresh, or desktop
tray/window features. Profile changes reconnect an active tunnel. Core startup
resolves providers before installing the tunnel routes; failures and cancelled
starts do not report a successful connection.

The app stores profiles locally and writes runtime YAML and node selections into
an atomic binary-plist file in its App Group container. Network Extension
preferences contain only the profile ID and file reference, keeping large
subscriptions below iOS's VPN configuration size limit. The extension reads the
shared snapshot on every start, including starts from iOS Settings. Legacy
inline configurations remain readable; connecting from the updated app replaces
them with a file reference. Controller requests
use extension messages and the embedded core router; no controller port is
exposed. Core diagnostic messages use private OS logging.

## Source and license

This port follows the repository's [GPL-3.0 license](../LICENSE). The app icon is
reused from Clash Verge Rev. The embedded [Swihomo Core](https://github.com/ruattd/swihomo-core)
is a GPL-3.0 fork of [Mihomo](https://github.com/MetaCubeX/mihomo), pinned with its
license in `Core/`. The separate Swihomo app is not included. Yams retains its MIT
license in its resolved source package.

Apple documents the VPN integration in
[NEPacketTunnelProvider](https://developer.apple.com/documentation/networkextension/nepackettunnelprovider)
and [NEPacketTunnelFlow](https://developer.apple.com/documentation/networkextension/nepackettunnelflow).
