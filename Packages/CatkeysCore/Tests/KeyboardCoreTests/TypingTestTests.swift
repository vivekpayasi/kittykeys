import Foundation
import Testing
import KeyboardCore

// MARK: - Metrics

@Test(arguments: [
    ("kitten", "sitting", 3),
    ("sitting", "kitten", 3),
    ("flaw", "lawn", 2),
    ("same text", "same text", 0),
    ("kal milte hain", "kal milet hain", 2),
])
func editDistance(_ a: String, _ b: String, _ expected: Int) {
    #expect(TypingMetrics.editDistance(a, b) == expected)
}

@Test func editDistanceOfEmptyStrings() {
    #expect(TypingMetrics.editDistance("", "") == 0)
    #expect(TypingMetrics.editDistance("", "abc") == 3)
    #expect(TypingMetrics.editDistance("abc", "") == 3)
}

@Test func editDistanceCountsAnEmojiAsOneCharacter() {
    #expect(TypingMetrics.editDistance("👍", "👎") == 1)
    #expect(TypingMetrics.editDistance("ok 👋🏽", "ok 👋") == 1)        // a skin tone is part of one grapheme
    #expect(TypingMetrics.editDistance("hi 👩‍👧‍👦", "hi ") == 1)       // a family is one grapheme
    #expect(TypingMetrics.editDistance("🇮🇳🇮🇳", "🇮🇳") == 1)
    #expect(TypingMetrics.editDistance("caf\u{E9}", "cafe\u{301}") == 0)  // canonically equal
}

@Test func wordsPerMinute() {
    #expect(TypingMetrics.wordsPerMinute(characters: 50, seconds: 60) == 10.0)
    #expect(TypingMetrics.wordsPerMinute(characters: 25, seconds: 15) == 20.0)
    #expect(TypingMetrics.wordsPerMinute(characters: 0, seconds: 60) == 0)
}

@Test(arguments: [0.0, -5.0, .nan])
func wordsPerMinuteWithoutTimeIsZero(_ seconds: Double) {
    #expect(TypingMetrics.wordsPerMinute(characters: 50, seconds: seconds) == 0)
}

@Test func normalizedTrimsTheEndsAndStraightensQuotes() {
    #expect(TypingMetrics.normalized("  I\u{2019}ll call you.\n") == "I'll call you.")
    #expect(TypingMetrics.normalized("\u{2018}ok\u{2019} \u{201C}fine\u{201D}") == "'ok' \"fine\"")
    #expect(TypingMetrics.normalized("two  spaces inside") == "two  spaces inside")
    #expect(TypingMetrics.normalized(" \n ") == "")
}

// MARK: - Sentences

@Test func bundledSentencesLoad() throws {
    let sentences = try TypingSentences.bundled()
    #expect((10...14).contains(sentences.count))
    #expect(Set(sentences.map(\.language)) == ["en", "hi-Latn"])
    for sentence in sentences {
        #expect((25...60).contains(sentence.text.count), "\(sentence.text.count) characters: \(sentence.text)")
    }
}

@Test func bundledSentencesAreHalfEnglishHalfHinglish() throws {
    let sentences = try TypingSentences.bundled()
    let english = sentences.filter { $0.language == "en" }.count
    #expect(english > 0)
    #expect(english * 2 == sentences.count)
}

@Test func bundledSentencesAreAlreadyNormalized() throws {
    // The typed text is normalized before it is compared, so a target with curly quotes or spaces at its ends could
    // never be matched.
    let texts = try TypingSentences.bundled().map(\.text)
    #expect(!texts.isEmpty)
    for text in texts {
        #expect(TypingMetrics.normalized(text) == text, "\(text)")
    }
    #expect(Set(texts).count == texts.count)
}

// MARK: - Runs

@Test func errorRateAndSpeedOfARun() {
    let run = TypingRun(date: .now, keyboard: "catkeys", targetCharacters: 200, errorsLeft: 4, corrections: 7, seconds: 60)
    #expect(run.errorRate == 0.02)
    #expect(run.wordsPerMinute == 40.0)
}

@Test func errorRateWithZeroTargetCharactersIsZero() {
    let run = TypingRun(date: .now, keyboard: "Apple", targetCharacters: 0, errorsLeft: 0, corrections: 0, seconds: 0)
    #expect(run.errorRate == 0)
    #expect(run.wordsPerMinute == 0)
}

/// Each test gets its own defaults suite, named by an absolute path inside its own temporary folder, as in
/// `SettingsTests`. The suite and the folder are removed when the test ends.
final class TypingRunStoreTests {
    let suiteFolder: URL
    let suiteName: String
    let defaults: UserDefaults
    let store: TypingRunStore

    static let first = TypingRun(
        date: Date(timeIntervalSinceReferenceDate: 800_000_000.25), keyboard: "catkeys",
        targetCharacters: 214, errorsLeft: 3, corrections: 9, seconds: 61.5)
    static let second = TypingRun(
        date: Date(timeIntervalSinceReferenceDate: 800_000_600.5), keyboard: "Apple",
        targetCharacters: 198, errorsLeft: 1, corrections: 4, seconds: 48.125)

    init() {
        suiteFolder = FileManager.default.temporaryDirectory.appendingPathComponent("catkeys-tests-\(UUID())")
        suiteName = suiteFolder.appendingPathComponent("typing").path
        defaults = UserDefaults(suiteName: suiteName)!
        store = TypingRunStore(defaults: defaults)
    }

    deinit {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: suiteFolder)
    }

    @Test func startsEmpty() {
        #expect(store.load().isEmpty)
    }

    @Test func appendThenLoadRoundTrips() {
        store.append(Self.first)
        #expect(store.load() == [Self.first])
        #expect(TypingRunStore(defaults: UserDefaults(suiteName: suiteName)!).load() == [Self.first])
        #expect(defaults.object(forKey: "catkeys.typingTest.runs") != nil)
    }

    @Test func newestFirst() {
        store.append(Self.first)
        store.append(Self.second)
        #expect(store.load() == [Self.second, Self.first])
    }

    @Test func corruptDataLoadsEmpty() {
        defaults.set(Data([0xDE, 0xAD, 0xBE, 0xEF]), forKey: "catkeys.typingTest.runs")
        #expect(store.load().isEmpty)
        defaults.set(Data(#"[{"keyboard":"catkeys"}]"#.utf8), forKey: "catkeys.typingTest.runs")
        #expect(store.load().isEmpty)
        defaults.set(Data(#"{"runs":[]}"#.utf8), forKey: "catkeys.typingTest.runs")
        #expect(store.load().isEmpty)
        defaults.set("not data", forKey: "catkeys.typingTest.runs")
        #expect(store.load().isEmpty)

        store.append(Self.first)   // a new run replaces what couldn't be read
        #expect(store.load() == [Self.first])
    }

    @Test(arguments: [Double.nan, .infinity])
    func nonFiniteSecondsAreSavedAsZero(_ seconds: Double) {
        // JSON can't carry NaN or infinity; the run is still saved.
        var run = Self.first
        run.seconds = seconds
        store.append(run)
        run.seconds = 0
        #expect(store.load() == [run])
    }
}
