import Foundation
import NetworkExtension

final class PacketTunnelProvider: NEPacketTunnelProvider {
    private let core = CoreRuntime()

    nonisolated(nonsending) override func startTunnel(options: [String: NSObject]?) async throws {
        guard let settings = protocolConfiguration as? NETunnelProviderProtocol,
              let values = settings.providerConfiguration else {
            throw ClientError(message: "Select a subscription before connecting.")
        }
        let snapshot = try TunnelConfigurationStore.shared().read(providerConfiguration: values)
        let bridge = PacketBridge(flow: packetFlow)
        // Resolve providers and geodata before installing the tunnel's default routes.
        let startupID = try await core.start(yaml: snapshot.yaml, bridge: bridge, selections: snapshot.selections)
        do {
            try await setTunnelNetworkSettings(makeNetworkSettings())
            try await core.activate(startupID: startupID)
        } catch {
            await core.stop(startupID: startupID)
            throw error
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason) async {
        await core.stop()
    }

    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)? = nil) {
        let core = self.core
        let reply = ProviderCompletion(completionHandler)
        Task {
            let response: ControllerResponse
            do {
                let request = try JSONDecoder().decode(ControllerRequest.self, from: messageData)
                response = await core.request(request)
            } catch {
                response = ControllerResponse(status: 400, body: Data(), error: "Invalid controller request.")
            }
            reply.finish(try? JSONEncoder().encode(response))
        }
    }

    private func makeNetworkSettings() -> NEPacketTunnelNetworkSettings {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        let ipv4 = NEIPv4Settings(addresses: ["198.18.0.1"], subnetMasks: ["255.255.255.0"])
        ipv4.includedRoutes = [.default()]
        settings.ipv4Settings = ipv4
        let ipv6 = NEIPv6Settings(addresses: ["fd00::1"], networkPrefixLengths: [64])
        ipv6.includedRoutes = [.default()]
        settings.ipv6Settings = ipv6
        let dns = NEDNSSettings(servers: ["198.18.0.2"])
        dns.matchDomains = [""]
        settings.dnsSettings = dns
        settings.mtu = 1500
        return settings
    }
}

private final class ProviderCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var handler: ((Data?) -> Void)?

    init(_ handler: ((Data?) -> Void)?) { self.handler = handler }

    func finish(_ data: Data?) {
        lock.lock()
        let completion = handler
        handler = nil
        lock.unlock()
        completion?(data)
    }
}
