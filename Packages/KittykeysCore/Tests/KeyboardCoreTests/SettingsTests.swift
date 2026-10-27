import Foundation
import Testing
import KeyboardCore

/// Each test gets its own defaults suite, named by an absolute path inside its own temporary folder, so
/// nothing lands in ~/Library/Preferences. The suite and the folder are removed when the test ends.
final class SettingsTests {
    let suiteFolder: URL
    let suiteName: String
    let defaults: UserDefaults
    let store: SettingsStore

    init() {
        suiteFolder = FileManager.default.temporaryDirectory.appendingPathComponent("kittykeys-tests-\(UUID())")
        suiteName = suiteFolder.appendingPathComponent("settings").path
        defaults = UserDefaults(suiteName: suiteName)!
        store = SettingsStore(defaults: defaults)
    }

    deinit {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: suiteFolder)
    }

    func writeSettingsJSON(_ json: String) {
        defaults.set(Data(json.utf8), forKey: "catkeys.settings")
    }

    @Test func defaultsMatchDesign() {
        let s = KeyboardSettings()
        #expect(s.haptics && !s.sound && s.keyPopup && s.doubleSpacePeriod)
        #expect(s.longPressDelay == 0.3)
        #expect(s.handOffCodeFields)
        #expect(!s.showDotComKey && s.currency == "")
        #expect(s.themeID == "automatic" && s.darkThemeID == "")
        #expect(store.load() == s)   // nothing saved yet
        #expect(store.customThemes.isEmpty)
    }

    @Test func saveThenLoadRoundTrips() {
        var s = KeyboardSettings()
        s.haptics = false
        s.sound = true
        s.keyPopup = false
        s.doubleSpacePeriod = false
        s.longPressDelay = 0.45
        s.handOffCodeFields = false
        s.showDotComKey = true
        s.currency = "€"
        s.themeID = "neon"
        s.darkThemeID = "midnight"
        store.save(s)
        #expect(store.load() == s)
        #expect(SettingsStore(defaults: UserDefaults(suiteName: suiteName)!).load() == s)
    }

    @Test func corruptDataLoadsDefaults() {
        defaults.set(Data([0xDE, 0xAD, 0xBE, 0xEF]), forKey: "catkeys.settings")
        #expect(store.load() == KeyboardSettings())
        writeSettingsJSON(#"{"haptics":"yes"}"#)
        #expect(store.load() == KeyboardSettings())
        defaults.set("not data", forKey: "catkeys.settings")
        #expect(store.load() == KeyboardSettings())
    }

    @Test func longPressDelayIsClampedOnLoad() {
        writeSettingsJSON(#"{"haptics":true,"sound":false,"keyPopup":true,"doubleSpacePeriod":true,"longPressDelay":5}"#)
        #expect(store.load().longPressDelay == 0.6)
        writeSettingsJSON(#"{"longPressDelay":0.05}"#)
        #expect(store.load().longPressDelay == 0.2)

        var s = KeyboardSettings()
        s.longPressDelay = 5
        store.save(s)
        #expect(store.load().longPressDelay == 0.6)
    }

    @Test func longPressDelayIsClampedWhenDecoded() throws {
        let s = try JSONDecoder().decode(KeyboardSettings.self, from: Data(#"{"longPressDelay":0.1}"#.utf8))
        #expect(s.longPressDelay == 0.2)
    }

    @Test(arguments: [Double.nan, .infinity, -.infinity])
    func nonFiniteDelayDecodesToDefault(_ delay: Double) throws {
        // JSON can't carry NaN or infinity; a property list can.
        let plist = try PropertyListSerialization.data(
            fromPropertyList: ["longPressDelay": delay, "sound": true], format: .binary, options: 0)
        let s = try PropertyListDecoder().decode(KeyboardSettings.self, from: plist)
        #expect(s.longPressDelay == 0.3)
        #expect(s.sound)
    }

    @Test(arguments: [Double.nan, .infinity])
    func saveKeepsTheOtherFieldsWhenTheDelayIsNotFinite(_ delay: Double) {
        var s = KeyboardSettings()
        s.haptics = false
        s.keyPopup = false
        s.longPressDelay = delay
        store.save(s)
        s.longPressDelay = 0.3
        #expect(store.load() == s)
    }

    @Test func handOffCodeFieldsDecodes() {
        writeSettingsJSON(#"{"handOffCodeFields":false}"#)
        var expected = KeyboardSettings()
        expected.handOffCodeFields = false
        #expect(store.load() == expected)
    }

    @Test func oneBadFieldKeepsTheOthers() {
        writeSettingsJSON(#"{"haptics":"yes","sound":true}"#)
        var expected = KeyboardSettings()
        expected.sound = true
        #expect(store.load() == expected)
    }

    @Test func missingFieldsTakeDefaults() {
        writeSettingsJSON(#"{"haptics":false}"#)
        var expected = KeyboardSettings()
        expected.haptics = false
        #expect(store.load() == expected)

        writeSettingsJSON("{}")
        #expect(store.load() == KeyboardSettings())
    }

    @Test func heartbeatRoundTrips() {
        #expect(store.lastKeyboardOpen == nil)
        let opened = Date(timeIntervalSinceReferenceDate: 800_000_000)
        store.lastKeyboardOpen = opened                  // nonmutating: works on a `let` store
        #expect(store.lastKeyboardOpen == opened)
        #expect(defaults.object(forKey: "catkeys.keyboardOpenedAt") as? Date == opened)
        #expect(SettingsStore(defaults: UserDefaults(suiteName: suiteName)!).lastKeyboardOpen == opened)

        store.lastKeyboardOpen = nil
        #expect(store.lastKeyboardOpen == nil)
    }

    // MARK: Themes

    private func customTheme(_ name: String) -> ThemeSpec {
        var spec = Themes.newCustom(from: Themes.presets[3], existing: [])
        spec.name = name
        return spec
    }

    @Test func customThemesRoundTrip() {
        let themes = [customTheme("B"), customTheme("A")]
        store.saveCustomThemes(themes)
        #expect(store.customThemes == themes)
        #expect(SettingsStore(defaults: UserDefaults(suiteName: suiteName)!).customThemes == themes)
        #expect(defaults.data(forKey: "kittykeys.customThemes") != nil)
    }

    @Test func customThemesSkipBadEntries() throws {
        let good = customTheme("Good")
        let goodJSON = try #require(String(data: JSONEncoder().encode(good), encoding: .utf8))
        defaults.set(Data(#"[42, {"name":"No id"}, \#(goodJSON)]"#.utf8), forKey: "kittykeys.customThemes")
        #expect(store.customThemes == [good])

        defaults.set(Data([0xDE, 0xAD]), forKey: "kittykeys.customThemes")
        #expect(store.customThemes.isEmpty)
        defaults.set("not data", forKey: "kittykeys.customThemes")
        #expect(store.customThemes.isEmpty)
    }

    @Test func addingAThemeKeepsChangesSavedElsewhere() {
        var first = customTheme("First")
        store.saveCustomThemes([first])
        // The editor, through another store on the same defaults, renames it meanwhile.
        first.name = "Renamed"
        SettingsStore(defaults: UserDefaults(suiteName: suiteName)!).saveCustomThemes([first])

        let added = store.addCustomTheme(copying: Themes.presets[3])
        #expect(added.id.hasPrefix(Themes.customIDPrefix))
        #expect(added.name == "My theme")
        #expect(added.light == Themes.presets[3].light)
        #expect(store.customThemes == [first, added])
    }

    @Test func removingAPickedThemeResetsTheSlot() {
        let picked = customTheme("Picked"), other = customTheme("Other")
        store.saveCustomThemes([picked, other])
        var s = KeyboardSettings()
        s.themeID = picked.id
        s.darkThemeID = picked.id
        s.sound = true
        store.save(s)

        store.removeCustomTheme(id: picked.id)
        #expect(store.customThemes == [other])
        var expected = s
        expected.themeID = "automatic"
        expected.darkThemeID = ""
        #expect(store.load() == expected)

        // Removing a theme no slot picked leaves the settings alone.
        s = expected
        s.themeID = "neon"
        s.darkThemeID = "midnight"
        store.save(s)
        store.removeCustomTheme(id: other.id)
        #expect(store.customThemes.isEmpty)
        #expect(store.load() == s)
    }

    @Test func appGroupNeedsAnID() throws {
        #expect(SettingsStore.appGroup(id: nil) == nil)

        let group = try #require(SettingsStore.appGroup(id: suiteName))
        var s = KeyboardSettings()
        s.sound = true
        group.save(s)
        #expect(store.load() == s)   // same suite as the test's store
    }
}
