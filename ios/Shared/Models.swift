import Foundation

struct ClashProfile: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var name: String
    var sourceURL: URL?
    var updatedAt: Date
    var usage: SubscriptionUsage?

}

struct SubscriptionUsage: Codable, Hashable, Sendable {
    var upload: Int64
    var download: Int64
    var total: Int64
    var expiresAt: Date?

    var usedBytes: Int64 {
        let sum = upload.addingReportingOverflow(download)
        return sum.overflow ? Int64.max : sum.partialValue
    }
}

enum ProxyMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case rule, global, direct
    var id: String { rawValue }
    var title: String {
        switch self {
        case .rule: "Rule"
        case .global: "Global"
        case .direct: "Direct"
        }
    }
}

struct ProxyGroup: Codable, Identifiable, Sendable {
    var name: String
    var type: String
    var now: String?
    var all: [String]
    var id: String { name }
    var canSelect: Bool { type == "Selector" || type == "select" }
}

struct ControllerRequest: Codable, Sendable {
    var method: String = "GET"
    var path: String
    var body: Data?
}

struct ControllerResponse: Codable, Sendable {
    var status: Int
    var body: Data
    var error: String?
}

struct ClientError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum AppConfiguration {
    static var tunnelIdentifier: String {
        Bundle.main.object(forInfoDictionaryKey: "TunnelBundleIdentifier") as? String
            ?? "io.github.chikage.clashverge.ios.PacketTunnel"
    }
}
