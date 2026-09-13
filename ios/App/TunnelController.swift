import Foundation
import NetworkExtension
import Observation

@MainActor @Observable
final class TunnelController {
    private(set) var status: NEVPNStatus = .invalid
    private(set) var activeProfileID: UUID?
    var onFailure: ((String) -> Void)?
    @ObservationIgnored private var manager: NETunnelProviderManager?
    @ObservationIgnored private var observer: NSObjectProtocol?
    private var starting = false

    func prepare() async throws {
        let configurations = try await NETunnelProviderManager.loadAllFromPreferences()
        let manager = configurations.first {
            ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier
                == AppConfiguration.tunnelIdentifier
        } ?? NETunnelProviderManager()
        self.manager = manager
        observe(manager)
        refreshStatus()
    }

    func start(profile: ClashProfile, yaml: Data, selections: [String: String]) async throws {
        if manager == nil { try await prepare() }
        guard let manager else { throw ClientError(message: "VPN preferences are unavailable.") }
        let snapshot = TunnelConfiguration(profileID: profile.id, yaml: yaml, selections: selections)
        try TunnelConfigurationStore.shared().write(snapshot)
        let configuration = NETunnelProviderProtocol()
        configuration.providerBundleIdentifier = AppConfiguration.tunnelIdentifier
        configuration.serverAddress = "Clash Verge"
        configuration.providerConfiguration = snapshot.providerConfiguration
        manager.protocolConfiguration = configuration
        manager.localizedDescription = "Clash Verge"
        manager.isEnabled = true
        try await manager.saveToPreferences()
        try await manager.loadFromPreferences()
        observe(manager)
        starting = true
        do {
            try manager.connection.startVPNTunnel()
            status = .connecting
        } catch {
            starting = false
            status = manager.connection.status
            throw error
        }
    }

    func stop() async throws {
        starting = false
        manager?.connection.stopVPNTunnel()
        for _ in 0..<100 {
            refreshStatus()
            if status == .disconnected || status == .invalid { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw ClientError(message: "The VPN is still disconnecting. Please try again shortly.")
    }

    func saveRuntime(profile: ClashProfile?, yaml: Data?, selections: [String: String]) async throws {
        guard let manager, let configuration = manager.protocolConfiguration as? NETunnelProviderProtocol else { return }
        guard let profile, let yaml else {
            let previousID = (configuration.providerConfiguration?["profileID"] as? String).flatMap(UUID.init(uuidString:))
            try await manager.removeFromPreferences()
            if let previousID { try? TunnelConfigurationStore.shared().remove(profileID: previousID) }
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
            self.manager = nil
            status = .invalid
            activeProfileID = nil
            return
        }
        let snapshot = TunnelConfiguration(profileID: profile.id, yaml: yaml, selections: selections)
        try TunnelConfigurationStore.shared().write(snapshot)
        configuration.providerConfiguration = snapshot.providerConfiguration
        manager.protocolConfiguration = configuration
        try await manager.saveToPreferences()
    }

    func request(_ request: ControllerRequest) async throws -> Data {
        guard status == .connected,
              let session = manager?.connection as? NETunnelProviderSession else {
            throw ClientError(message: "Connect the VPN to access the running core.")
        }
        let data = try JSONEncoder().encode(request)
        let responseData: Data = try await withCheckedThrowingContinuation { continuation in
            let reply = ProviderReply(continuation)
            reply.deadline = Task { @MainActor in
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled else { return }
                reply.finish(.failure(ClientError(message: "The VPN core did not respond in time.")))
            }
            do {
                try session.sendProviderMessage(data) { response in
                    Task { @MainActor in
                        if let response { reply.finish(.success(response)) }
                        else { reply.finish(.failure(ClientError(message: "The VPN connection ended."))) }
                    }
                }
            } catch { reply.finish(.failure(error)) }
        }
        let response = try JSONDecoder().decode(ControllerResponse.self, from: responseData)
        guard (200..<300).contains(response.status), response.error == nil else {
            struct APIError: Decodable { let message: String? }
            let detail = try? JSONDecoder().decode(APIError.self, from: response.body).message
            throw ClientError(message: response.error ?? detail ?? "The core returned HTTP \(response.status).")
        }
        return response.body
    }

    private func observe(_ manager: NETunnelProviderManager) {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange, object: manager.connection, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshStatus() }
        }
    }

    private func refreshStatus() {
        guard let manager else { return }
        status = manager.connection.status
        let id = (manager.protocolConfiguration as? NETunnelProviderProtocol)?
            .providerConfiguration?["profileID"] as? String
        activeProfileID = id.flatMap(UUID.init(uuidString:))
        if status == .connected { starting = false }
        if starting && (status == .disconnected || status == .invalid) {
            starting = false
            manager.connection.fetchLastDisconnectError { [weak self] error in
                Task { @MainActor [weak self] in
                    self?.onFailure?(error?.localizedDescription ?? "The VPN failed to start. Check your subscription configuration.")
                }
            }
        }
    }
}

@MainActor
private final class ProviderReply {
    private var continuation: CheckedContinuation<Data, Error>?
    var deadline: Task<Void, Never>?

    init(_ continuation: CheckedContinuation<Data, Error>) { self.continuation = continuation }

    func finish(_ result: Result<Data, Error>) {
        let pending = continuation
        continuation = nil
        deadline?.cancel()
        deadline = nil
        pending?.resume(with: result)
    }
}
