import Foundation
import Testing
import KeyboardCore

/// The things to try in the app's Try it tab: the controller reports each as it's used, and the shared settings keep
/// which ones the user has tried. `Harness` is in ControllerTests.
@MainActor struct TryFeatureControllerTests {
    final class Recorder {
        var used: [TryFeature] = []
    }

    func harness(_ text: String = "", cursor: Int? = nil) throws -> (Harness, Recorder) {
        let k = try Harness(text, cursor: cursor)
        let recorder = Recorder()
        k.controller.onFeatureUsed = { recorder.used.append($0) }
        return (k, recorder)
    }

    @Test func movingTheCursorCounts() throws {
        let (k, recorder) = try harness("abcdef", cursor: 3)
        let p = try k.down("space")
        k.wait(0.33)
        #expect(recorder.used.isEmpty)
        k.now += 0.67
        k.move(to: Point(x: p.x + 18, y: p.y))
        k.up(at: Point(x: p.x + 18, y: p.y))
        #expect(Set(recorder.used) == [.cursorMove])
    }

    @Test func holdingForASymbolCounts() throws {
        let (k, recorder) = try harness()
        let p = try k.down("a")
        k.wait(0.5)
        k.up(at: p)
        #expect(k.doc.text == "@" && recorder.used == [.longPressSymbol])
    }

    @Test func slidingFromBackspaceCounts() throws {
        let (k, recorder) = try harness("hi there")
        let p = try k.down("⌫")
        k.wait(0.05)
        k.move(to: Point(x: p.x - 25, y: p.y))
        #expect(k.doc.text == "hi " && recorder.used == [.wordDelete])
    }

    @Test func aShortcutCounts() throws {
        let (k, recorder) = try harness("omw")
        k.controller.textReplacements = TextReplacements(pairs: [(shortcut: "omw", phrase: "On my way!")])
        try k.tap("space")
        #expect(recorder.used == [.textReplacement])
    }

    /// Only an emoji typed from search's results counts, not one from the panel.
    @Test func anEmojiFromSearchCounts() throws {
        let (k, recorder) = try harness()
        try k.tap("😊")
        k.controller.insertEmoji("😂")
        #expect(recorder.used.isEmpty)
        k.controller.openEmojiSearch()
        try k.tap("l")
        k.controller.insertEmoji("😂")
        #expect(recorder.used == [.emojiSearch])
    }

    /// Search starts with Recent in its results: an emoji from there isn't a search yet.
    @Test func anEmojiFromSearchCountsOnlyAfterTypingAQuery() throws {
        let (k, recorder) = try harness()
        try k.tap("😊")
        k.controller.openEmojiSearch()
        k.controller.insertEmoji("😂")
        #expect(recorder.used.isEmpty)
        for label in ["l", "a", "u"] { try k.tap(label) }
        k.controller.insertEmoji("😂")
        #expect(recorder.used == [.emojiSearch])
    }

    /// In search the keys type into the query: a long-press option or a ⌫ swipe there isn't the feature.
    @Test func searchKeysReportNothing() throws {
        let (k, recorder) = try harness()
        try k.tap("😊")
        k.controller.openEmojiSearch()
        for label in ["h", "i"] { try k.tap(label) }
        let a = try k.down("a")
        k.wait(0.5)
        k.up(at: a)
        let p = try k.down("⌫")
        k.wait(0.05)
        k.move(to: Point(x: p.x - 25, y: p.y))
        k.up(at: Point(x: p.x - 25, y: p.y))
        #expect(recorder.used.isEmpty)
    }

    @Test func aSwipeWithNothingToDeleteCountsNothing() throws {
        let (k, recorder) = try harness()
        let p = try k.down("⌫")
        k.wait(0.05)
        k.move(to: Point(x: p.x - 25, y: p.y))
        #expect(recorder.used.isEmpty)
    }

    /// The phrase replaced the shortcut even when the field ignored the return after it.
    @Test func aReplacementCountsEvenIfTheWordEndDidNotLand() throws {
        let (k, recorder) = try harness("omw")
        k.controller.textReplacements = TextReplacements(pairs: [(shortcut: "omw", phrase: "On my way!")])
        k.doc.ignoredInsertions = ["\n"]
        try k.tap("return")
        #expect(k.doc.text == "On my way!" && recorder.used == [.textReplacement])
    }

    @Test func noReplacementNoReport() throws {
        let (k, recorder) = try harness("omw")
        k.controller.textReplacements = TextReplacements(pairs: [(shortcut: "omw", phrase: "On my way!")])
        k.controller.fieldDidChange(FieldTraits(kind: .email, autoCap: .none))
        try k.tap(".")
        k.controller.fieldDidChange(FieldTraits(kind: .url, autoCap: .none))
        try k.tap("space")
        #expect(recorder.used.isEmpty)
    }

    @Test func plainTypingCountsNothing() throws {
        let (k, recorder) = try harness("hi")
        for label in ["o", "k", "space", "⌫", "123", "1"] { try k.tap(label) }
        #expect(recorder.used.isEmpty)
    }
}

/// Each test gets its own defaults suite, as in `SettingsTests`.
final class TriedFeaturesTests {
    let suiteFolder: URL
    let suiteName: String
    let defaults: UserDefaults
    let store: SettingsStore

    init() {
        suiteFolder = FileManager.default.temporaryDirectory.appendingPathComponent("kittykeys-tests-\(UUID())")
        suiteName = suiteFolder.appendingPathComponent("tried").path
        defaults = UserDefaults(suiteName: suiteName)!
        store = SettingsStore(defaults: defaults)
    }

    deinit {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: suiteFolder)
    }

    @Test func triedFeaturesRoundTrip() {
        #expect(store.triedFeatures.isEmpty)
        store.markTried(.cursorMove)
        store.markTried(.emojiSearch)
        store.markTried(.cursorMove)
        #expect(store.triedFeatures == [.cursorMove, .emojiSearch])
        #expect(SettingsStore(defaults: UserDefaults(suiteName: suiteName)!).triedFeatures == [.cursorMove, .emojiSearch])
    }

    @Test func startingOverForgetsThem() {
        store.markTried(.wordDelete)
        store.resetTried()
        #expect(store.triedFeatures.isEmpty)
    }

    @Test func unknownOrCorruptEntriesAreIgnored() {
        defaults.set(["cursorMove", "flying", 3], forKey: "kittykeys.triedFeatures")
        #expect(store.triedFeatures == [.cursorMove])
        defaults.set("junk", forKey: "kittykeys.triedFeatures")
        #expect(store.triedFeatures.isEmpty)
    }
}
