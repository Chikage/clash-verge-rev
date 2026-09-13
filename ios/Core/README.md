# Embedded Mihomo

`core.lock.json` pins [Swihomo Core](https://github.com/ruattd/swihomo-core), a
[Mihomo](https://github.com/MetaCubeX/mihomo) fork with an in-process C bridge and
a gVisor packet-flow adapter. Its source is GPL-3.0; the original license is
preserved in `LICENSE.mihomo`. The separate Swihomo application is not vendored.

Run `bash ios/scripts/build-core.sh` from the repository root. The script verifies
the source archive checksum, builds iOS 17 ARM64 device and simulator static
libraries, and creates `ios/Vendor/MihomoCore.xcframework`. On Apple Silicon it
downloads the checksum-pinned Go compiler if Go is absent. Set
`GO=/absolute/path/to/go` to use an installed compiler. Xcode and network access
for the pinned Go modules are required. Downloaded sources, modules, and binaries
stay under `ios/Vendor` and are not committed.

The Packet Tunnel extension links the archive and implements the C symbols
`swihomo_write_packet` and `swihomo_write_log`. Its public
`NEPacketTunnelFlow.readPackets` input goes to `SwihomoCoreInputPacket`; output
goes back through `NEPacketTunnelFlow.writePackets`. Packet bytes are copied at
the C boundary. The Swift host must retain its packet bridge until the core has
stopped, and release returned strings/data with the corresponding free function.

The embedded adapter owns no operating-system TUN interface. It fixes its
addresses to `198.18.0.1/24` and `fd00::1/64`, uses gVisor, and disables host route
modification. The extension configures matching Network Extension addresses and
routes. Use `198.18.0.2` and `fd00::2` for tunnel DNS; the profile must enable DNS.
`SwihomoCoreAPIRequest` dispatches directly to the core's controller router, so
the extension can handle app messages without exposing a controller port.
