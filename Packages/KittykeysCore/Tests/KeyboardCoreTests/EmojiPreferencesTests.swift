import Foundation
import Testing
import KeyboardCore

/// Each test gets its own defaults suite, named by an absolute path inside its own temporary folder, as in
/// `SettingsTests`. The suite and the folder are removed when the test ends.
final class EmojiPreferencesTests {
    let suiteFolder: URL
    let suiteName: String
    let defaults: UserDefaults
    let prefs: EmojiPreferences

    static let wave = EmojiItem(base: "👋", version: 0.6, skins: ["👋🏻", "👋🏼", "👋🏽", "👋🏾", "👋🏿"])
    static let grin = EmojiItem(base: "😀", version: 1.0, skins: [])

    init() {
        suiteFolder = FileManager.default.temporaryDirectory.appendingPathComponent("kittykeys-tests-\(UUID())")
        suiteName = suiteFolder.appendingPathComponent("emoji").path
        defaults = UserDefaults(suiteName: suiteName)!
        prefs = EmojiPreferences(defaults: defaults)
    }

    deinit {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: suiteFolder)
    }

    /// 40 distinct single-scalar faces, U+1F600 to U+1F627.
    static let faces: [String] = (0..<40).map { String(Character(Unicode.Scalar(0x1F600 + $0)!)) }

    @Test func recentsStartEmpty() {
        #expect(prefs.recents.isEmpty)
    }

    @Test func recentsMostRecentFirstAndCapped() {
        for face in Self.faces { prefs.recordUse(face, base: face) }
        #expect(prefs.recents.count == 32)
        #expect(prefs.recents == Array(Self.faces.reversed().prefix(32)))

        let reused = Self.faces[20]
        prefs.recordUse(reused, base: reused)
        #expect(prefs.recents.count == 32)
        #expect(prefs.recents.first == reused)
        #expect(prefs.recents.filter { $0 == reused }.count == 1)
        #expect(EmojiPreferences(defaults: UserDefaults(suiteName: suiteName)!).recents == prefs.recents)
    }

    @Test func recentsDeduplicateByBaseAndKeepTheVariant() {
        prefs.recordUse("😀", base: "😀")
        prefs.recordUse("👋", base: "👋")
        prefs.recordUse("👋🏽", base: "👋")
        #expect(prefs.recents == ["👋🏽", "😀"])
        prefs.recordUse("😀", base: "😀")
        prefs.recordUse("👋🏿", base: "👋")
        #expect(prefs.recents == ["👋🏿", "😀"])
        #expect(defaults.stringArray(forKey: "catkeys.emoji.recents") == ["👋🏿", "😀"])
    }

    @Test func recentsIgnoreVariationSelector() {
        prefs.recordUse("☺️", base: "☺️")            // U+263A U+FE0F
        prefs.recordUse("☺", base: "☺")              // bare U+263A, as text from elsewhere may carry
        #expect(prefs.recents == ["☺"])
        prefs.recordUse("☝🏽", base: "☝️")            // the skin variant has no FE0F; its base does
        prefs.recordUse("☝️", base: "☝️")
        #expect(prefs.recents == ["☝️", "☺"])
    }

    @Test func preferredVariantRemembered() {
        #expect(prefs.preferredVariant(for: Self.wave) == "👋")
        prefs.setPreferredVariant("👋🏽", for: "👋")
        #expect(prefs.preferredVariant(for: Self.wave) == "👋🏽")
        #expect(EmojiPreferences(defaults: UserDefaults(suiteName: suiteName)!).preferredVariant(for: Self.wave) == "👋🏽")
        #expect(prefs.preferredVariant(for: Self.grin) == "😀")

        prefs.setPreferredVariant("👋", for: "👋")
        #expect(prefs.preferredVariant(for: Self.wave) == "👋")
    }

    @Test func preferredVariantIgnoresVariationSelector() {
        let point = EmojiItem(base: "☝️", version: 0.6, skins: ["☝🏻", "☝🏼", "☝🏽", "☝🏾", "☝🏿"])
        prefs.setPreferredVariant("☝🏾", for: "☝")      // bare base from elsewhere
        #expect(prefs.preferredVariant(for: point) == "☝🏾")
    }

    @Test func preferredVariantMustBeOneOfTheItemsSkins() {
        prefs.setPreferredVariant("🙂", for: "👋")
        #expect(prefs.preferredVariant(for: Self.wave) == "👋")
        defaults.set(["👋": "x"], forKey: "catkeys.emoji.skins")
        #expect(prefs.preferredVariant(for: Self.wave) == "👋")
    }

    /// The panel reads the choices once and then per cell, without touching the defaults.
    @Test func skinChoicesAreASnapshot() {
        prefs.setPreferredVariant("👋🏽", for: "👋")
        var choices = prefs.skinChoices
        #expect(choices.preferredVariant(for: Self.wave) == "👋🏽")
        #expect(choices.preferredVariant(for: Self.grin) == "😀")

        prefs.setPreferredVariant("👋🏿", for: "👋")
        #expect(choices.preferredVariant(for: Self.wave) == "👋🏽")
        #expect(prefs.skinChoices.preferredVariant(for: Self.wave) == "👋🏿")

        choices.setPreferredVariant("👋🏻", for: "👋")
        #expect(choices.preferredVariant(for: Self.wave) == "👋🏻")
        choices.setPreferredVariant("🙂", for: "👋")
        #expect(choices.preferredVariant(for: Self.wave) == "👋")
        choices.setPreferredVariant("👋🏼", for: "👋")
        choices.setPreferredVariant("👋", for: "👋")
        #expect(choices.preferredVariant(for: Self.wave) == "👋")
        let point = EmojiItem(base: "☝️", version: 0.6, skins: ["☝🏻", "☝🏼", "☝🏽", "☝🏾", "☝🏿"])
        choices.setPreferredVariant("☝🏾", for: "☝")
        #expect(choices.preferredVariant(for: point) == "☝🏾")
        #expect(prefs.preferredVariant(for: Self.wave) == "👋🏿")
        #expect(EmojiSkinChoices().preferredVariant(for: Self.wave) == "👋")
    }

    @Test(arguments: [0, 1])
    func corruptRecentsLoadEmpty(_ kind: Int) {
        let junk: Any = kind == 0 ? Data([0xDE, 0xAD, 0xBE, 0xEF]) : 42
        defaults.set(junk, forKey: "catkeys.emoji.recents")
        defaults.set(junk, forKey: "catkeys.emoji.skins")
        #expect(prefs.recents.isEmpty)
        #expect(prefs.preferredVariant(for: Self.wave) == "👋")

        prefs.recordUse("👋🏽", base: "👋")
        prefs.setPreferredVariant("👋🏽", for: "👋")
        #expect(prefs.recents == ["👋🏽"])
        #expect(prefs.preferredVariant(for: Self.wave) == "👋🏽")
    }

    @Test func nonStringEntriesAreDropped() {
        defaults.set(["😀", 5, Data([1]), "👋🏽", ["nested"]], forKey: "catkeys.emoji.recents")
        defaults.set(["👋": 3, "☝️": "☝🏽"], forKey: "catkeys.emoji.skins")
        #expect(prefs.recents == ["😀", "👋🏽"])
        #expect(prefs.preferredVariant(for: Self.wave) == "👋")
        let point = EmojiItem(base: "☝️", version: 0.6, skins: ["☝🏻", "☝🏼", "☝🏽", "☝🏾", "☝🏿"])
        #expect(prefs.preferredVariant(for: point) == "☝🏽")

        prefs.recordUse("🙂", base: "🙂")
        #expect(prefs.recents == ["🙂", "😀", "👋🏽"])
    }

    @Test func storedRecentsAreCappedAndDeduplicatedOnLoad() {
        defaults.set(Self.faces + ["😀", "", "👋", "👋🏽"], forKey: "catkeys.emoji.recents")
        #expect(prefs.recents == Array(Self.faces.prefix(32)))
        defaults.set(["👋", "", "👋🏽", "😀"], forKey: "catkeys.emoji.recents")
        #expect(prefs.recents == ["👋", "😀"])
    }
}
