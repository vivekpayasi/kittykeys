import Foundation
import Testing
import KeyboardCore

/// Each test gets its own defaults suite, removed when the test ends.
final class SettingsTests {
    let suiteName = "catkeys-test-\(UUID())"
    let defaults: UserDefaults
    let store: SettingsStore

    init() {
        defaults = UserDefaults(suiteName: suiteName)!
        store = SettingsStore(defaults: defaults)
    }

    deinit { defaults.removePersistentDomain(forName: suiteName) }

    func writeSettingsJSON(_ json: String) {
        defaults.set(Data(json.utf8), forKey: "catkeys.settings")
    }

    @Test func defaultsMatchDesign() {
        let s = KeyboardSettings()
        #expect(s.haptics && !s.sound && s.keyPopup && s.doubleSpacePeriod)
        #expect(s.longPressDelay == 0.3)
        #expect(store.load() == s)   // nothing saved yet
    }

    @Test func saveThenLoadRoundTrips() {
        var s = KeyboardSettings()
        s.haptics = false
        s.sound = true
        s.keyPopup = false
        s.doubleSpacePeriod = false
        s.longPressDelay = 0.45
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

    @Test func appGroupNeedsAnID() throws {
        #expect(SettingsStore.appGroup(id: nil) == nil)

        let group = try #require(SettingsStore.appGroup(id: suiteName))
        var s = KeyboardSettings()
        s.sound = true
        group.save(s)
        #expect(store.load() == s)   // same suite as the test's store
    }
}
