import Foundation

enum SubscriptionClient {
    struct Download: Sendable {
        var data: Data
        var suggestedName: String?
        var usage: SubscriptionUsage?
    }

    static func url(from value: String) throws -> URL {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              ["https", "http"].contains(scheme),
              let host = url.host, !host.isEmpty else {
            throw ClientError(message: "Enter a valid HTTP or HTTPS subscription URL.")
        }
        return url
    }

    static func download(from url: URL) async throws -> Download {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.timeoutInterval = 60
        request.setValue("ClashVergeRev", forHTTPHeaderField: "User-Agent")
        request.setValue("application/yaml, text/yaml, text/plain, */*", forHTTPHeaderField: "Accept")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw ClientError(message: "Unable to download the subscription. Check the network and subscription URL.")
        }
        guard let response = response as? HTTPURLResponse else {
            throw ClientError(message: "The subscription server returned an invalid response.")
        }
        guard (200..<300).contains(response.statusCode) else {
            throw ClientError(message: "The subscription server returned HTTP \(response.statusCode).")
        }
        try ProfileConfiguration.validate(data)
        return Download(
            data: data,
            suggestedName: dispositionName(response.value(forHTTPHeaderField: "Content-Disposition")),
            usage: usage(subscriptionUserinfo(in: response))
        )
    }

    private static func subscriptionUserinfo(in response: HTTPURLResponse) -> String? {
        if let value = response.value(forHTTPHeaderField: "Subscription-Userinfo") {
            return value
        }
        return response.allHeaderFields.first { key, _ in
            String(describing: key).lowercased().hasSuffix("-subscription-userinfo")
        }.map { String(describing: $0.value) }
    }

    private static func dispositionName(_ value: String?) -> String? {
        guard let value else { return nil }
        var filename: String?
        let pattern = #"(?:^|;)\s*(filename\*|filename)\s*=\s*(?:"((?:\\.|[^"])*)"|([^;]*))"#
        guard let expression = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let source = value as NSString
        for match in expression.matches(in: value, range: NSRange(location: 0, length: source.length)) {
            let key = source.substring(with: match.range(at: 1)).lowercased()
            let valueRange = match.range(at: 2).location == NSNotFound ? match.range(at: 3) : match.range(at: 2)
            let candidate = source.substring(with: valueRange).trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: #"\""#, with: "\"")
            if key == "filename*" {
                let parts = candidate.split(separator: "'", maxSplits: 2, omittingEmptySubsequences: false)
                if parts.count == 3, let decoded = String(parts[2]).removingPercentEncoding,
                   !decoded.isEmpty {
                    return profileName(decoded)
                }
            } else if key == "filename", !candidate.isEmpty {
                filename = candidate.removingPercentEncoding ?? candidate
            }
        }
        return filename.map(profileName)
    }

    private static func profileName(_ filename: String) -> String {
        let name = (filename as NSString).lastPathComponent
        let path = name as NSString
        return ["yaml", "yml"].contains(path.pathExtension.lowercased())
            ? path.deletingPathExtension : name
    }

    private static func usage(_ value: String?) -> SubscriptionUsage? {
        guard let value else { return nil }
        var values: [String: Int64] = [:]
        for component in value.split(separator: ";") {
            let pair = component.split(separator: "=", maxSplits: 1)
            guard pair.count == 2,
                  let number = Int64(pair[1].trimmingCharacters(in: .whitespaces)), number >= 0 else { continue }
            values[pair[0].trimmingCharacters(in: .whitespaces).lowercased()] = number
        }
        guard !values.isEmpty else { return nil }
        let expiry = values["expire"].flatMap { $0 > 0 ? Date(timeIntervalSince1970: TimeInterval($0)) : nil }
        return SubscriptionUsage(
            upload: values["upload"] ?? 0,
            download: values["download"] ?? 0,
            total: values["total"] ?? 0,
            expiresAt: expiry
        )
    }
}
