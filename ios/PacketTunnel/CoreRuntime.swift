import Foundation

actor CoreRuntime {
    private var bridge: PacketBridge?
    private var startupID: UUID?

    func start(yaml: Data, bridge: PacketBridge, selections: [String: String]) throws -> UUID {
        guard self.bridge == nil else { throw ClientError(message: "The core is already running.") }
        let directory = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        ).appendingPathComponent("Mihomo", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        PacketDestination.shared.install(bridge)
        var bytes = [UInt8](yaml)
        let status = directory.path.withCString { home in
            bytes.withUnsafeMutableBufferPointer { buffer in
                SwihomoCoreStart(buffer.baseAddress, buffer.count, home)
            }
        }
        guard status == 0 else {
            let error = Self.lastError()
            SwihomoCoreStop()
            PacketDestination.shared.install(nil)
            throw ClientError(message: error)
        }
        self.bridge = bridge
        let startupID = UUID()
        self.startupID = startupID
        // Provider membership can change between subscription updates; restore only available nodes.
        for (group, node) in selections {
            guard let name = group.addingPercentEncoding(withAllowedCharacters: .urlPathComponent) else { continue }
            let body = try JSONEncoder().encode(["name": node])
            _ = request(ControllerRequest(method: "PUT", path: "/proxies/\(name)", body: body))
        }
        return startupID
    }

    func activate(startupID: UUID) throws {
        guard self.startupID == startupID, let bridge else { throw CancellationError() }
        bridge.beginReading()
    }

    func stop(startupID: UUID? = nil) {
        if let startupID, startupID != self.startupID { return }
        self.startupID = nil
        bridge?.stop()
        SwihomoCoreStop()
        PacketDestination.shared.install(nil)
        bridge = nil
    }

    func request(_ request: ControllerRequest) -> ControllerResponse {
        guard bridge != nil else {
            return ControllerResponse(status: 503, body: Data(), error: "The VPN core is not running.")
        }
        let path = request.path == "/verge/stats" ? "/connections" : request.path
        var bytes = [UInt8](request.body ?? Data())
        var result: UnsafeMutablePointer<UInt8>?
        var count = 0
        let status = request.method.withCString { method in
            path.withCString { target in
                bytes.withUnsafeMutableBufferPointer { buffer in
                    SwihomoCoreAPIRequest(method, target, buffer.baseAddress, buffer.count, &result, &count)
                }
            }
        }
        defer { if let result { SwihomoCoreFreeData(result) } }
        guard status >= 100 else {
            return ControllerResponse(status: 500, body: Data(), error: Self.lastError())
        }
        var data = result.map { Data(bytes: $0, count: count) } ?? Data()
        if request.path == "/verge/stats", status == 200,
           let connections = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let summary: [String: Any] = [
                "downloadTotal": connections["downloadTotal"] ?? 0,
                "uploadTotal": connections["uploadTotal"] ?? 0,
                "connectionCount": (connections["connections"] as? [Any])?.count ?? 0
            ]
            data = (try? JSONSerialization.data(withJSONObject: summary)) ?? Data()
        }
        return ControllerResponse(status: Int(status), body: data)
    }

    private static func lastError() -> String {
        guard let pointer = SwihomoCoreLastError() else { return "Mihomo failed to start." }
        defer { SwihomoCoreFreeString(pointer) }
        return String(cString: pointer)
    }
}

private extension CharacterSet {
    static let urlPathComponent = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
}
