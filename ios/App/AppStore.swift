import Foundation
import NetworkExtension
import Observation

@MainActor @Observable
final class AppStore {
    let profiles = ProfileRepository()
    let tunnel = TunnelController()
    private(set) var groups: [ProxyGroup] = []
    private(set) var mode = ProxyMode(rawValue: UserDefaults.standard.string(forKey: "proxyMode") ?? "") ?? .rule
    private(set) var downloadTotal: Int64 = 0
    private(set) var uploadTotal: Int64 = 0
    private(set) var connectionCount = 0
    private(set) var delays: [String: Int] = [:]
    var errorMessage: String?
    private var operationActive = false
    private var refreshing = false
    private var loaded = false
    private var mutationRevision = 0
    private var selections: [String: [String: String]] = [:]

    var isConnected: Bool { tunnel.status == .connected }
    var isBusy: Bool {
        operationActive || tunnel.status == .connecting || tunnel.status == .disconnecting || tunnel.status == .reasserting
    }
    var statusText: String {
        switch tunnel.status {
        case .connected: "Connected"
        case .connecting: "Connecting…"
        case .disconnecting: "Disconnecting…"
        case .reasserting: "Reconnecting…"
        default: "Disconnected"
        }
    }

    func prepare() async {
        guard !loaded else { return }
        loaded = true
        do {
            try profiles.load()
            if let data = UserDefaults.standard.data(forKey: "proxySelections") {
                selections = try JSONDecoder().decode([String: [String: String]].self, from: data)
            }
            tunnel.onFailure = { [weak self] in self?.errorMessage = $0 }
            #if !targetEnvironment(simulator)
            try await tunnel.prepare()
            if isConnected, let profile = profiles.profiles.first(where: { $0.id == tunnel.activeProfileID }) {
                try profiles.select(profile)
            }
            #endif
            try loadOfflineGroups()
            await reload()
        } catch { errorMessage = error.localizedDescription }
    }

    func connect() async {
        guard !isBusy, !isConnected else { return }
        #if targetEnvironment(simulator)
        errorMessage = "VPN connections require a signed build on a physical iPhone or iPad. Subscription management is available in the simulator."
        #else
        await perform { try await self.startSelectedProfile() }
        #endif
    }

    func disconnect() async {
        guard !operationActive else { return }
        await perform {
            try await self.tunnel.stop()
            try self.loadOfflineGroups()
            self.connectionCount = 0
        }
    }

    func selectProfile(_ profile: ClashProfile) async {
        guard !isBusy, profile.id != profiles.selectedID else { return }
        await perform {
            let reconnect = self.isConnected
            if reconnect { try await self.tunnel.stop() }
            try self.profiles.select(profile)
            self.delays = [:]
            try self.loadOfflineGroups()
            if reconnect { try await self.startSelectedProfile() }
            else { try await self.saveTunnelSnapshot() }
        }
    }

    func updateProfile(_ profile: ClashProfile) async {
        guard !isBusy else { return }
        await perform {
            try await self.profiles.update(profile)
            if profile.id == self.profiles.selectedID {
                let reconnect = self.isConnected
                if reconnect { try await self.tunnel.stop() }
                try self.loadOfflineGroups()
                if reconnect { try await self.startSelectedProfile() }
                else { try await self.saveTunnelSnapshot() }
            }
        }
    }

    func deleteProfile(_ profile: ClashProfile) async {
        guard !isBusy else { return }
        await perform {
            if profile.id == self.profiles.selectedID && self.isConnected { try await self.tunnel.stop() }
            try self.profiles.delete(profile)
            self.selections.removeValue(forKey: profile.id.uuidString)
            try self.persistSelections()
            try self.loadOfflineGroups()
            try await self.saveTunnelSnapshot()
            if let shared = try? TunnelConfigurationStore.shared() {
                try shared.remove(profileID: profile.id)
            }
        }
    }

    func runImport(url: String, name: String) async -> Bool {
        guard !isBusy else { return false }
        return await perform {
            try await self.profiles.importSubscription(url: url, name: name)
            if !self.isConnected { try self.loadOfflineGroups() }
        }
    }

    func runFileImport(_ url: URL) async -> Bool {
        guard !isBusy else { return false }
        return await perform {
            try await self.profiles.importFile(url: url)
            if !self.isConnected { try self.loadOfflineGroups() }
        }
    }

    func open(_ url: URL) async {
        await prepare()
        if url.isFileURL { _ = await runFileImport(url); return }
        guard ["clash", "clash-verge"].contains(url.scheme ?? ""),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let query = components.percentEncodedQuery,
              let range = query.range(of: "(?:^|&)url=", options: .regularExpression) else {
            errorMessage = "The import link is missing a subscription URL."
            return
        }
        let remainder = String(query[range.upperBound...])
        var subscription = components.queryItems?.first(where: { $0.name == "url" })?.value ?? ""
        // Some desktop links leave the nested URL unescaped, including its query parameters.
        if remainder.hasPrefix("https://") || remainder.hasPrefix("http://") {
            subscription = remainder
        } else if !subscription.hasPrefix("https://") && !subscription.hasPrefix("http://") {
            subscription = subscription.removingPercentEncoding ?? subscription
        }
        let name = components.queryItems?.first(where: { $0.name == "name" })?.value ?? ""
        _ = await runImport(url: subscription, name: name)
    }

    func selectProxy(group: String, node: String) async {
        guard !isBusy, let profileID = profiles.selectedID else { return }
        await perform {
            if self.isConnected {
                let body = try JSONEncoder().encode(["name": node])
                _ = try await self.tunnel.request(ControllerRequest(method: "PUT", path: "/proxies/\(Self.pathComponent(group))", body: body))
            }
            self.selections[profileID.uuidString, default: [:]][group] = node
            try self.persistSelections()
            if let index = self.groups.firstIndex(where: { $0.name == group }) { self.groups[index].now = node }
            try await self.saveTunnelSnapshot()
        }
    }

    func changeMode(_ newMode: ProxyMode) async {
        guard !isBusy, newMode != mode else { return }
        await perform {
            if self.isConnected {
                let body = try JSONEncoder().encode(["mode": newMode.rawValue])
                _ = try await self.tunnel.request(ControllerRequest(method: "PATCH", path: "/configs", body: body))
            }
            self.mode = newMode
            UserDefaults.standard.set(newMode.rawValue, forKey: "proxyMode")
            try await self.saveTunnelSnapshot()
        }
    }

    func testDelay(node: String) async {
        guard !isBusy, isConnected else { return }
        await perform {
            var components = URLComponents()
            components.percentEncodedPath = "/proxies/\(Self.pathComponent(node))/delay"
            components.queryItems = [URLQueryItem(name: "url", value: "https://www.gstatic.com/generate_204"), URLQueryItem(name: "timeout", value: "5000")]
            struct Delay: Decodable { let delay: Int }
            let response = try await self.tunnel.request(ControllerRequest(path: components.string!))
            self.delays[node] = try JSONDecoder().decode(Delay.self, from: response).delay
        }
    }

    func reload() async {
        guard !refreshing, !operationActive else { return }
        guard isConnected else {
            connectionCount = 0
            return
        }
        refreshing = true
        let revision = mutationRevision
        defer { refreshing = false }
        do {
            struct Proxy: Decodable { let name: String?; let type: String; let now: String?; let all: [String]? }
            struct Proxies: Decodable { let proxies: [String: Proxy] }
            struct Stats: Decodable { let downloadTotal: Int64; let uploadTotal: Int64; let connectionCount: Int }
            struct Config: Decodable { let mode: ProxyMode }
            let data = try await tunnel.request(ControllerRequest(path: "/proxies"))
            let snapshot = try JSONDecoder().decode(Proxies.self, from: data)
            let stats = try JSONDecoder().decode(Stats.self, from: await tunnel.request(ControllerRequest(path: "/verge/stats")))
            let config = try JSONDecoder().decode(Config.self, from: await tunnel.request(ControllerRequest(path: "/configs")))
            guard isConnected, !operationActive, revision == mutationRevision else { return }
            let order = groups.map(\.name)
            groups = snapshot.proxies.compactMap { name, proxy in
                guard let all = proxy.all else { return nil }
                return ProxyGroup(name: name, type: proxy.type, now: proxy.now, all: all)
            }.sorted {
                let left = order.firstIndex(of: $0.name) ?? Int.max
                let right = order.firstIndex(of: $1.name) ?? Int.max
                return left == right ? $0.name.localizedStandardCompare($1.name) == .orderedAscending : left < right
            }
            mode = config.mode
            downloadTotal = stats.downloadTotal
            uploadTotal = stats.uploadTotal
            connectionCount = stats.connectionCount
        } catch {
            if isConnected { errorMessage = error.localizedDescription }
        }
    }

    private func startSelectedProfile() async throws {
        guard let profile = profiles.selectedProfile else { throw ClientError(message: "Import and select a subscription first.") }
        let selected = selections[profile.id.uuidString] ?? [:]
        let yaml = try ProfileConfiguration.runtimeYAML(from: profiles.yaml(for: profile), mode: mode, selections: selected)
        try await tunnel.start(profile: profile, yaml: yaml, selections: selected)
        downloadTotal = 0
        uploadTotal = 0
    }

    private func loadOfflineGroups() throws {
        guard let profile = profiles.selectedProfile else { groups = []; return }
        groups = try ProfileConfiguration.groups(in: profiles.yaml(for: profile))
        for index in groups.indices {
            if let selected = selections[profile.id.uuidString]?[groups[index].name], groups[index].all.contains(selected) {
                groups[index].now = selected
            }
        }
    }

    private func persistSelections() throws {
        UserDefaults.standard.set(try JSONEncoder().encode(selections), forKey: "proxySelections")
    }

    private func saveTunnelSnapshot() async throws {
        let profile = profiles.selectedProfile
        let selected = profile.flatMap { selections[$0.id.uuidString] } ?? [:]
        let yaml = try profile.map {
            try ProfileConfiguration.runtimeYAML(from: profiles.yaml(for: $0), mode: mode, selections: selected)
        }
        do { try await tunnel.saveRuntime(profile: profile, yaml: yaml, selections: selected) }
        catch { throw ClientError(message: "Changes were saved in the app, but iOS could not update the VPN configuration. Open the app and reconnect before starting the VPN from Settings.") }
    }

    @discardableResult private func perform(_ operation: () async throws -> Void) async -> Bool {
        operationActive = true
        mutationRevision += 1
        errorMessage = nil
        defer { operationActive = false }
        do { try await operation(); return true }
        catch { errorMessage = error.localizedDescription; return false }
    }

    private static func pathComponent(_ name: String) -> String {
        name.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-._~"))) ?? name
    }
}
