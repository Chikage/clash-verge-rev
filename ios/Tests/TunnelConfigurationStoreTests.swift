import Foundation
import XCTest
@testable import ClashVerge

final class TunnelConfigurationStoreTests: XCTestCase {
    func testLargeProfileAndSelectionsStayOutOfVPNPreferences() throws {
        let store = try makeStore()
        let yaml = Data(("proxies: []\n" + String(repeating: "# subscription rule\n", count: 35_000)).utf8)
        let selections = Dictionary(uniqueKeysWithValues: (0..<4_096).map {
            ("Group \($0)", String(repeating: "香港节点", count: 20) + " \($0)")
        })
        let configuration = TunnelConfiguration(profileID: UUID(), yaml: yaml, selections: selections)
        let legacy: [String: Any] = [
            "profileID": configuration.profileID.uuidString,
            "profileYAML": yaml,
            "selections": selections,
        ]
        XCTAssertGreaterThan(yaml.count, 627_807)
        XCTAssertGreaterThan(try plistData(legacy).count, 524_288)
        XCTAssertGreaterThan(try plistData(selections).count, 524_288)

        try store.write(configuration)

        XCTAssertEqual(try store.read(providerConfiguration: configuration.providerConfiguration), configuration)
        XCTAssertEqual(configuration.providerConfiguration.keys.sorted(), ["configurationFile", "profileID"])
        XCTAssertLessThan(try plistData(configuration.providerConfiguration).count, 1_024)
        let file = store.directory.appendingPathComponent("\(configuration.profileID.uuidString).plist")
        XCTAssertEqual(try Data(contentsOf: file).prefix(8), Data("bplist00".utf8))
    }

    func testUpdatingOneProfileKeepsItsReferenceStableAndOtherProfilesIntact() throws {
        let store = try makeStore()
        let first = configuration(yaml: "proxies: []", selections: ["Select": "Original"])
        let second = configuration(yaml: "proxy-providers: {}", selections: ["Select": "Other"])
        try store.write(first)
        try store.write(second)
        let updated = TunnelConfiguration(
            profileID: first.profileID,
            yaml: Data("proxies: [{name: Updated}]".utf8),
            selections: ["Select": "Updated", "Media": "DIRECT"]
        )

        try store.write(updated)

        XCTAssertEqual(first.providerConfiguration as NSDictionary, updated.providerConfiguration as NSDictionary)
        XCTAssertEqual(try store.read(providerConfiguration: first.providerConfiguration), updated)
        XCTAssertEqual(try store.read(providerConfiguration: second.providerConfiguration), second)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: store.directory.path).count, 2)
    }

    func testMissingOrInvalidConfigurationReferencesFail() throws {
        let store = try makeStore()
        let profile = configuration()
        XCTAssertThrowsError(try store.read(providerConfiguration: profile.providerConfiguration))
        XCTAssertThrowsError(try store.read(providerConfiguration: [:]))
        XCTAssertThrowsError(try store.read(providerConfiguration: ["profileID": "invalid"]))
        XCTAssertThrowsError(try store.read(providerConfiguration: ["profileID": profile.profileID.uuidString]))
        try store.write(profile)
        for filename in ["../outside.plist", "\(UUID().uuidString).plist", "/tmp/profile.plist"] {
            XCTAssertThrowsError(try store.read(providerConfiguration: [
                "profileID": profile.profileID.uuidString,
                "configurationFile": filename,
            ]))
        }
    }

    func testCorruptOrMismatchedSnapshotFailsWithoutUsingStaleInlineData() throws {
        let store = try makeStore()
        let profile = configuration()
        try store.write(profile)
        let file = store.directory.appendingPathComponent("\(profile.profileID.uuidString).plist")
        var metadata = profile.providerConfiguration
        metadata["profileYAML"] = Data("stale inline profile".utf8)
        try Data("not a property list".utf8).write(to: file)
        XCTAssertThrowsError(try store.read(providerConfiguration: metadata))

        let other = configuration(yaml: "another profile")
        try PropertyListEncoder().encode(other).write(to: file)
        XCTAssertThrowsError(try store.read(providerConfiguration: metadata))

        try FileManager.default.removeItem(at: file)
        XCTAssertThrowsError(try store.read(providerConfiguration: metadata))
    }

    func testLegacyInlineProfilesRemainReadable() throws {
        let store = try makeStore()
        let profile = configuration(yaml: "proxies: []\n", selections: ["选择节点": "香港 01", "Media": "DIRECT"])
        var metadata: [String: Any] = [
            "profileID": profile.profileID.uuidString,
            "profileYAML": profile.yaml,
            "selections": profile.selections,
        ]
        XCTAssertEqual(try store.read(providerConfiguration: metadata), profile)

        metadata.removeValue(forKey: "selections")
        XCTAssertEqual(
            try store.read(providerConfiguration: metadata),
            TunnelConfiguration(profileID: profile.profileID, yaml: profile.yaml, selections: [:])
        )
    }

    func testRemovingSnapshotPreservesOtherProfilesAndCanBeRepeated() throws {
        let store = try makeStore()
        let first = configuration()
        let second = configuration(yaml: "proxies: []\n")
        try store.write(first)
        try store.write(second)

        try store.remove(profileID: first.profileID)
        try store.remove(profileID: first.profileID)

        XCTAssertThrowsError(try store.read(providerConfiguration: first.providerConfiguration))
        XCTAssertEqual(try store.read(providerConfiguration: second.providerConfiguration), second)
    }

    private func makeStore() throws -> TunnelConfigurationStore {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TunnelConfigurationStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        return TunnelConfigurationStore(directory: directory)
    }

    private func configuration(
        yaml: String = "proxies: []",
        selections: [String: String] = [:]
    ) -> TunnelConfiguration {
        TunnelConfiguration(profileID: UUID(), yaml: Data(yaml.utf8), selections: selections)
    }

    private func plistData(_ value: Any) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: value, format: .binary, options: 0)
    }
}
