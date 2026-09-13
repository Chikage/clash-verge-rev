import Foundation

struct TunnelConfiguration: Codable, Equatable, Sendable {
    let profileID: UUID
    let yaml: Data
    let selections: [String: String]

    var providerConfiguration: [String: Any] {
        ["profileID": profileID.uuidString, "configurationFile": "\(profileID.uuidString).plist"]
    }
}

struct TunnelConfigurationStore: Sendable {
    let directory: URL

    static func shared() throws -> Self {
        guard let identifier = Bundle.main.object(forInfoDictionaryKey: "SharedAppGroupIdentifier") as? String,
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) else {
            throw ClientError(message: "The shared VPN container is unavailable. Enable the same App Group for the app and Packet Tunnel, then rebuild both targets.")
        }
        return Self(directory: container.appendingPathComponent("Library/Application Support/TunnelConfigurations", isDirectory: true))
    }

    func write(_ configuration: TunnelConfiguration) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let data = try encoder.encode(configuration)
        var options: Data.WritingOptions = [.atomic]
        #if os(iOS)
        // The system may restart the VPN while the device is locked after its first unlock.
        options.insert(.completeFileProtectionUntilFirstUserAuthentication)
        #endif
        try data.write(to: fileURL(for: configuration.profileID), options: options)
    }

    func read(providerConfiguration values: [String: Any]) throws -> TunnelConfiguration {
        guard let value = values["profileID"] as? String, let profileID = UUID(uuidString: value) else {
            throw ClientError(message: "Select a subscription before connecting.")
        }
        if let file = values["configurationFile"] as? String {
            guard file == "\(profileID.uuidString).plist" else {
                throw ClientError(message: "The shared VPN configuration reference is invalid. Reconnect from the app.")
            }
            let data: Data
            do { data = try Data(contentsOf: fileURL(for: profileID)) }
            catch { throw ClientError(message: "The shared VPN configuration is missing or unavailable. Open the app and connect again.") }
            let configuration = try PropertyListDecoder().decode(TunnelConfiguration.self, from: data)
            guard configuration.profileID == profileID else {
                throw ClientError(message: "The shared VPN configuration belongs to a different profile. Reconnect from the app.")
            }
            return configuration
        }
        if let yaml = values["profileYAML"] as? Data {
            return TunnelConfiguration(profileID: profileID, yaml: yaml, selections: values["selections"] as? [String: String] ?? [:])
        }
        throw ClientError(message: "The VPN configuration is missing. Open the app and connect again.")
    }

    func remove(profileID: UUID) throws {
        let file = fileURL(for: profileID)
        if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
    }

    private func fileURL(for profileID: UUID) -> URL {
        directory.appendingPathComponent("\(profileID.uuidString).plist")
    }
}
