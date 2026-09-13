import Foundation
import Observation

@MainActor
@Observable
final class ProfileRepository {
    private(set) var profiles: [ClashProfile] = []
    private(set) var selectedID: UUID?

    var selectedProfile: ClashProfile? {
        profiles.first { $0.id == selectedID }
    }

    private struct Index: Codable {
        var profiles: [ClashProfile]
        var selectedID: UUID?
        var files: [String: String]
    }

    @ObservationIgnored private var files: [String: String] = [:]
    @ObservationIgnored private let directory: URL

    init() {
        directory = URL.applicationSupportDirectory.appendingPathComponent("Profiles", isDirectory: true)
    }

    func load() throws {
        let indexURL = directory.appendingPathComponent("index.json")
        guard FileManager.default.fileExists(atPath: indexURL.path) else { return }
        do {
            let index = try JSONDecoder().decode(Index.self, from: Data(contentsOf: indexURL))
            for profile in index.profiles {
                guard let file = index.files[profile.id.uuidString],
                      file == (file as NSString).lastPathComponent,
                      FileManager.default.fileExists(atPath: directory.appendingPathComponent(file).path) else {
                    throw ClientError(message: "A saved profile file is missing. Import the profile again.")
                }
            }
            profiles = index.profiles
            files = index.files
            selectedID = index.selectedID.flatMap { id in index.profiles.contains { $0.id == id } ? id : nil }
        } catch let error as ClientError {
            throw error
        } catch {
            throw ClientError(message: "Unable to read saved profiles.")
        }
    }

    func importSubscription(url: String, name: String) async throws {
        let sourceURL = try SubscriptionClient.url(from: url)
        let download = try await SubscriptionClient.download(from: sourceURL)
        try Task.checkCancellation()
        let requestedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let profile = ClashProfile(
            id: UUID(),
            name: requestedName.isEmpty ? download.suggestedName ?? "Subscription" : requestedName,
            sourceURL: sourceURL,
            updatedAt: Date(),
            usage: download.usage
        )
        try store(profile, data: download.data, replacing: false)
    }

    func importFile(url: URL) async throws {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ClientError(message: "Unable to read the selected profile file.")
        }
        try ProfileConfiguration.validate(data)
        try Task.checkCancellation()
        let profile = ClashProfile(
            id: UUID(),
            name: url.deletingPathExtension().lastPathComponent,
            sourceURL: nil,
            updatedAt: Date(),
            usage: nil
        )
        try store(profile, data: data, replacing: false)
    }

    func update(_ profile: ClashProfile) async throws {
        guard let current = profiles.first(where: { $0.id == profile.id }) else {
            throw ClientError(message: "This profile is no longer available.")
        }
        guard let sourceURL = current.sourceURL else {
            throw ClientError(message: "Import the local YAML file again to update this profile.")
        }
        let download = try await SubscriptionClient.download(from: sourceURL)
        try Task.checkCancellation()
        guard profiles.contains(where: { $0.id == current.id }) else {
            throw ClientError(message: "This profile is no longer available.")
        }
        var updated = current
        updated.updatedAt = Date()
        updated.usage = download.usage
        try store(updated, data: download.data, replacing: true)
    }

    func select(_ profile: ClashProfile) throws {
        guard profiles.contains(where: { $0.id == profile.id }) else {
            throw ClientError(message: "This profile is no longer available.")
        }
        try save(Index(profiles: profiles, selectedID: profile.id, files: files))
        selectedID = profile.id
    }

    func delete(_ profile: ClashProfile) throws {
        let remaining = profiles.filter { $0.id != profile.id }
        let selection = selectedID == profile.id ? remaining.first?.id : selectedID
        var remainingFiles = files
        let removedFile = remainingFiles.removeValue(forKey: profile.id.uuidString)
        try save(Index(profiles: remaining, selectedID: selection, files: remainingFiles))
        profiles = remaining
        selectedID = selection
        files = remainingFiles
        if let removedFile {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(removedFile))
        }
    }

    func yaml(for profile: ClashProfile) throws -> Data {
        guard let file = files[profile.id.uuidString] else {
            throw ClientError(message: "This profile is no longer available.")
        }
        do {
            return try Data(contentsOf: directory.appendingPathComponent(file))
        } catch {
            throw ClientError(message: "Unable to read the saved profile.")
        }
    }

    private func store(_ profile: ClashProfile, data: Data, replacing: Bool) throws {
        let filename = "\(profile.id.uuidString)-\(UUID().uuidString).yaml"
        let fileURL = directory.appendingPathComponent(filename)
        let oldFile = files[profile.id.uuidString]
        var nextProfiles = profiles
        if replacing, let index = nextProfiles.firstIndex(where: { $0.id == profile.id }) {
            nextProfiles[index] = profile
        } else {
            nextProfiles.append(profile)
        }
        var nextFiles = files
        nextFiles[profile.id.uuidString] = filename
        let selection = selectedID ?? profile.id
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
            try save(Index(profiles: nextProfiles, selectedID: selection, files: nextFiles))
        } catch {
            try? FileManager.default.removeItem(at: fileURL)
            throw ClientError(message: "Unable to save the profile. The previously saved profiles are unchanged.")
        }
        profiles = nextProfiles
        selectedID = selection
        files = nextFiles
        if let oldFile {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(oldFile))
        }
    }

    private func save(_ index: Index) throws {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(index)
            try data.write(to: directory.appendingPathComponent("index.json"), options: .atomic)
        } catch {
            throw ClientError(message: "Unable to save profile changes.")
        }
    }
}
