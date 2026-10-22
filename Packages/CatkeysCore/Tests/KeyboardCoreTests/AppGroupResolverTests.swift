import Foundation
import Testing
import KeyboardCore

/// Each test gets its own folder to stand in for the app's bundle, so `resolve` can read an
/// `embedded.mobileprovision` from it. The folder is removed when the test ends.
final class AppGroupResolverTests {
    static let canonical = "group.com.example.catkeys"
    /// How SideStore renames the canonical group for the signing team.
    static let renamed = "group.com.example.catkeys.ABCDE12345"
    static let unrelated = "group.com.example.othergroup"

    let bundleFolder: URL

    init() {
        bundleFolder = FileManager.default.temporaryDirectory
            .appendingPathComponent("catkeys-tests-\(UUID())")
            .appendingPathComponent("CatkeysKeyboard.appex")
    }

    deinit {
        try? FileManager.default.removeItem(at: bundleFolder.deletingLastPathComponent())
    }

    /// A .mobileprovision stand-in: an XML plist between binary bytes, as in the CMS envelope of a real one.
    static func profile(groups: [String]) throws -> Data {
        let plist: [String: Any] = [
            "AppIDName": "Catkeys",
            "Entitlements": [
                "application-identifier": "ABCDE12345.com.example.catkeys.ABCDE12345",
                "com.apple.security.application-groups": groups,
            ],
        ]
        let xml = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        return Data([0x30, 0x82, 0x2F, 0x00, 0x06, 0x09, 0x2A, 0xFF, 0xFE, 0x00]) + xml
            + Data([0x00, 0xA0, 0x82, 0x0D, 0xFF, 0x3C, 0x2F, 0x00])
    }

    /// The test's bundle, holding a profile that lists `groups`, or no profile when `groups` is nil.
    func bundle(profileGroups groups: [String]?) throws -> Bundle {
        try FileManager.default.createDirectory(at: bundleFolder, withIntermediateDirectories: true)
        if let groups {
            try Self.profile(groups: groups)
                .write(to: bundleFolder.appendingPathComponent("embedded.mobileprovision"))
        }
        return try #require(Bundle(url: bundleFolder))
    }

    // MARK: Parsing

    @Test func profileGroupsPutTheRenamedGroupFirst() throws {
        let data = try Self.profile(groups: [Self.unrelated, Self.renamed])
        #expect(AppGroupResolver.groups(fromProvisioningProfile: data, canonical: Self.canonical)
            == [Self.renamed, Self.unrelated])
    }

    @Test func profileGroupsKeepTheirOrderWithoutACanonicalID() throws {
        let data = try Self.profile(groups: [Self.unrelated, Self.renamed])
        #expect(AppGroupResolver.groups(fromProvisioningProfile: data, canonical: nil)
            == [Self.unrelated, Self.renamed])
    }

    @Test func profileWithoutGroupsGivesNone() throws {
        let xml = try PropertyListSerialization.data(
            fromPropertyList: ["Entitlements": ["application-identifier": "X"]], format: .xml, options: 0)
        #expect(AppGroupResolver.groups(fromProvisioningProfile: xml, canonical: Self.canonical) == [])
    }

    @Test(arguments: [
        Data(),
        Data([0xDE, 0xAD, 0xBE, 0xEF]),
        Data("<?xml version=\"1.0\"?> no plist end".utf8),
        Data("<?xml version=\"1.0\"?><plist><dict><key>broken</plist>".utf8),
    ])
    func garbageGivesNoGroups(_ data: Data) {
        #expect(AppGroupResolver.groups(fromProvisioningProfile: data, canonical: Self.canonical) == [])
    }

    // MARK: Resolving

    @Test func prefersTheCanonicalID() throws {
        let bundle = try bundle(profileGroups: [Self.renamed])
        var checked: [String] = []
        let resolved = AppGroupResolver.resolve(canonical: Self.canonical, bundle: bundle) {
            checked.append($0)
            return true
        }
        #expect(resolved == Self.canonical)
        #expect(checked == [Self.canonical])   // the profile isn't consulted
    }

    @Test func fallsBackToTheProfileGroup() throws {
        let bundle = try bundle(profileGroups: [Self.renamed])
        let resolved = AppGroupResolver.resolve(canonical: Self.canonical, bundle: bundle) { $0 == Self.renamed }
        #expect(resolved == Self.renamed)
    }

    @Test func fallbackPrefersTheRenamedGroup() throws {
        let bundle = try bundle(profileGroups: [Self.unrelated, Self.renamed])
        let resolved = AppGroupResolver.resolve(canonical: Self.canonical, bundle: bundle) { $0 != Self.canonical }
        #expect(resolved == Self.renamed)
    }

    @Test func fallbackSkipsGroupsWithoutAContainer() throws {
        let bundle = try bundle(profileGroups: [Self.renamed, Self.unrelated])
        let resolved = AppGroupResolver.resolve(canonical: Self.canonical, bundle: bundle) { $0 == Self.unrelated }
        #expect(resolved == Self.unrelated)
    }

    @Test func nilWhenNoContainerExists() throws {
        let bundle = try bundle(profileGroups: [Self.renamed, Self.unrelated])
        #expect(AppGroupResolver.resolve(canonical: Self.canonical, bundle: bundle) { _ in false } == nil)
    }

    @Test func nilWithoutAProfileOrCanonicalContainer() throws {
        let bundle = try bundle(profileGroups: nil)
        #expect(AppGroupResolver.resolve(canonical: Self.canonical, bundle: bundle) { _ in false } == nil)
    }

    @Test func nilWithoutACanonicalID() throws {
        let bundle = try bundle(profileGroups: [Self.renamed])
        #expect(AppGroupResolver.resolve(canonical: nil, bundle: bundle) { _ in true } == nil)
    }
}
