import Foundation
import Yams

enum ProfileConfiguration {
    static func groups(in data: Data) throws -> [ProxyGroup] {
        let configuration = try mapping(from: data)
        return (configuration["proxy-groups"] as? [[String: Any]] ?? []).compactMap { group in
            guard let name = group["name"] as? String,
                  let type = group["type"] as? String else { return nil }
            let proxies = group["proxies"] as? [String] ?? []
            return ProxyGroup(name: name, type: type, now: proxies.first, all: proxies)
        }
    }

    static func runtimeYAML(
        from data: Data,
        mode: ProxyMode,
        selections _: [String: String]
    ) throws -> Data {
        var configuration = try mapping(from: data)
        let desktopKeys = [
            "port", "socks-port", "mixed-port", "redir-port", "tproxy-port",
            "allow-lan", "bind-address", "authentication", "skip-auth-prefixes",
            "lan-allowed-ips", "lan-disallowed-ips", "listeners", "inbounds", "tunnels",
            "external-controller", "external-controller-tls", "external-controller-unix",
            "external-controller-pipe", "external-controller-cors", "external-ui",
            "external-ui-name", "external-ui-url", "secret", "tls", "tun",
            "interface-name", "routing-mark", "routing-table-id",
        ]
        for key in desktopKeys {
            configuration.removeValue(forKey: key)
        }
        configuration["mode"] = mode.rawValue
        configuration["allow-lan"] = false
        let ipv6 = configuration["ipv6"] as? Bool ?? false
        configuration["ipv6"] = ipv6

        var dns = configuration["dns"] as? [String: Any] ?? [:]
        dns["enable"] = true
        dns.removeValue(forKey: "listen")
        if dns["enhanced-mode"] == nil {
            dns["enhanced-mode"] = "fake-ip"
        }
        if dns["fake-ip-range"] == nil {
            dns["fake-ip-range"] = "198.18.0.1/16"
        }
        if dns["ipv6"] == nil {
            dns["ipv6"] = ipv6
        }
        if (dns["default-nameserver"] as? [Any] ?? []).isEmpty {
            dns["default-nameserver"] = ["223.5.5.5", "1.1.1.1"]
        }
        if (dns["nameserver"] as? [Any] ?? []).isEmpty {
            dns["nameserver"] = ["https://dns.alidns.com/dns-query", "https://1.1.1.1/dns-query"]
        }
        configuration["dns"] = dns

        for key in ["proxy-providers", "rule-providers"] {
            guard var providers = configuration[key] as? [String: Any] else { continue }
            for (name, value) in providers {
                guard var provider = value as? [String: Any] else { continue }
                if provider["type"] as? String == "file" {
                    throw ClientError(message: "File-based providers must be converted to HTTP or inline providers before connecting on iOS.")
                }
                if provider["type"] as? String == "http" {
                    provider.removeValue(forKey: "path")
                    provider.removeValue(forKey: "path-in-bundle")
                    providers[name] = provider
                }
            }
            configuration[key] = providers
        }

        do {
            return Data(try Yams.dump(object: configuration).utf8)
        } catch {
            throw ClientError(message: "Unable to prepare this profile for the VPN.")
        }
    }

    static func validate(_ data: Data) throws {
        _ = try mapping(from: data)
    }

    private static func mapping(from data: Data) throws -> [String: Any] {
        guard var yaml = String(data: data, encoding: .utf8) else {
            throw ClientError(message: "The profile must be a UTF-8 Clash YAML file.")
        }
        if yaml.hasPrefix("\u{FEFF}") {
            yaml.removeFirst()
        }
        let loaded: Any?
        do {
            loaded = try Yams.load(yaml: yaml)
        } catch {
            throw ClientError(message: "The profile contains invalid YAML.")
        }
        guard let configuration = loaded as? [String: Any] else {
            throw ClientError(message: "The profile must contain a Clash YAML mapping.")
        }
        let proxies = configuration["proxies"] as? [[String: Any]]
        let providers = configuration["proxy-providers"] as? [String: Any]
        guard proxies != nil || providers != nil else {
            throw ClientError(message: "The profile must contain proxies or proxy-providers. Import a Clash or Mihomo subscription.")
        }
        return configuration
    }
}
