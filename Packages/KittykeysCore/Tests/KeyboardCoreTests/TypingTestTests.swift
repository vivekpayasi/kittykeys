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

@Test func normalizedTrimsTheEndOnlyAndStraightensQuotes() {
    #expect(TypingMetrics.normalized("I\u{2019}ll call you.\n") == "I'll call you.")
    #expect(TypingMetrics.normalized("ok  \t\n ") == "ok")
    #expect(TypingMetrics.normalized("\u{2018}ok\u{2019} \u{201C}fine\u{201D}") == "'ok' \"fine\"")
    #expect(TypingMetrics.normalized("two  spaces inside") == "two  spaces inside")
    #expect(TypingMetrics.normalized(" \n ") == "")
}

@Test func normalizedKeepsLeadingSpaces() {
    // A space typed before the sentence is a real tap error, so it stays and counts.
    #expect(TypingMetrics.normalized("  I\u{2019}ll call you. ") == "  I'll call you.")
    #expect(TypingMetrics.normalized("\nok") == "\nok")
    #expect(TypingMetrics.editDistance("Ok.", TypingMetrics.normalized(" Ok. ")) == 1)
}

// MARK: - Stopwatch

@Test func stopwatchStartsAtTheFirstEdit() {
    var watch = TypingStopwatch()
    watch.finishSentence(at: 5)              // Done with no edit: nothing timed
    #expect(watch.seconds == 0)
    watch.edit(at: 10)
    watch.edit(at: 12)                        // later edits don't restart it
    watch.finishSentence(at: 25)
    #expect(watch.seconds == 15)
}

@Test func stopwatchAddsUpSentences() {
    var watch = TypingStopwatch()
    watch.edit(at: 0)
    watch.finishSentence(at: 10)
    watch.edit(at: 30)                        // the gap between Done and the next first edit isn't timed
    watch.finishSentence(at: 34)
    #expect(watch.seconds == 14)
}

@Test func stopwatchSkipsTimeAway() {
    var watch = TypingStopwatch()
    watch.edit(at: 0)
    watch.pause(at: 5)
    watch.resume(at: 65)
    watch.finishSentence(at: 70)
    #expect(watch.seconds == 10)
}

@Test func stopwatchPausedBeforeTheFirstEditWaitsForIt() {
    var watch = TypingStopwatch()
    watch.pause(at: 1)
    watch.resume(at: 50)
    watch.edit(at: 60)
    watch.finishSentence(at: 63)
    #expect(watch.seconds == 3)
}

@Test func stopwatchEditWhilePausedStartsOnResume() {
    var watch = TypingStopwatch()
    watch.pause(at: 0)
    watch.edit(at: 2)
    watch.resume(at: 20)
    watch.finishSentence(at: 26)
    #expect(watch.seconds == 6)
}

@Test func stopwatchPauseTwiceCountsOnce() {
    var watch = TypingStopwatch()
    watch.edit(at: 0)
    watch.pause(at: 4)
    watch.pause(at: 9)
    watch.resume(at: 10)
    watch.resume(at: 11)
    watch.finishSentence(at: 12)
    #expect(watch.seconds == 6)
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
        #expect(text.first?.isWhitespace == false, "\(text)")
    }
    #expect(Set(texts).count == texts.count)
}

/// SplitMix64: a seeded generator, so a draw can be repeated.
struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

let drawPool = (1...6).map { TypingSentence(text: "en \($0)", language: "en") }
    + (1...6).map { TypingSentence(text: "hi \($0)", language: "hi-Latn") }

@Test(arguments: ["en", "hi-Latn"])
func balancedDrawIsThreeAndTwoInterleaved(_ majority: String) {
    for seed in UInt64(0)..<20 {
        var generator = SeededGenerator(state: seed)
        let drawn = TypingSentences.balancedDraw(drawPool, count: 5, majority: majority, using: &generator)
        #expect(drawn.map { $0.language == majority } == [true, false, true, false, true])
        #expect(Set(drawn.map(\.text)).count == 5)
        #expect(drawn.allSatisfy(drawPool.contains))
    }
}

@Test func balancedDrawRepeatsForASeedAndVariesAcrossSeeds() {
    func draw(seed: UInt64) -> [String] {
        var generator = SeededGenerator(state: seed)
        return TypingSentences.balancedDraw(drawPool, count: 5, majority: "en", using: &generator).map(\.text)
    }
    #expect(draw(seed: 7) == draw(seed: 7))
    #expect(Set((UInt64(0)..<20).map(draw(seed:))).count > 10)
}

@Test func balancedDrawFillsFromTheOtherLanguageWhenOneRunsShort() {
    var generator = SeededGenerator(state: 1)
    let oneEnglish = [TypingSentence(text: "en 1", language: "en")] + drawPool.filter { $0.language == "hi-Latn" }
    let drawn = TypingSentences.balancedDraw(oneEnglish, count: 5, majority: "en", using: &generator)
    #expect(drawn.map(\.language) == ["en", "hi-Latn", "hi-Latn", "hi-Latn", "hi-Latn"])

    let two = Array(drawPool.prefix(2))
    #expect(TypingSentences.balancedDraw(two, count: 5, majority: "hi-Latn", using: &generator).count == 2)
    #expect(TypingSentences.balancedDraw([], count: 5, majority: "en", using: &generator).isEmpty)
}

@Test func nextMajorityTakesTurns() {
    #expect(TypingSentences.nextMajority(after: nil, in: drawPool) == "en")
    #expect(TypingSentences.nextMajority(after: "en", in: drawPool) == "hi-Latn")
    #expect(TypingSentences.nextMajority(after: "hi-Latn", in: drawPool) == "en")
    #expect(TypingSentences.nextMajority(after: "fr", in: drawPool) == "en")
    #expect(TypingSentences.nextMajority(after: "en", in: []) == nil)
}

// MARK: - Runs

@Test func errorRateAndSpeedOfARun() {
    let run = TypingRun(date: .now, keyboard: "catkeys", targetCharacters: 200, typedCharacters: 150, errorsLeft: 4,
                        corrections: 7, seconds: 60)
    #expect(run.errorRate == 0.02)        // over the target
    #expect(run.wordsPerMinute == 30.0)   // over what was typed
}

@Test func errorRateWithZeroTargetCharactersIsZero() {
    let run = TypingRun(date: .now, keyboard: "Apple", targetCharacters: 0, typedCharacters: 0, errorsLeft: 0,
                        corrections: 0, seconds: 0)
    #expect(run.errorRate == 0)
    #expect(run.wordsPerMinute == 0)
}

@Test func aRunIsIdentifiedByItsDate() {
    let date = Date(timeIntervalSinceReferenceDate: 800_000_000)
    let run = TypingRun(date: date, keyboard: "Apple", targetCharacters: 10, typedCharacters: 10, errorsLeft: 0,
                        corrections: 0, seconds: 5)
    #expect(run.id == date)
}

@Test func anOldRunWithoutTypedCharactersDecodes() throws {
    let json = #"{"date":800000000,"keyboard":"Apple","targetCharacters":190,"errorsLeft":2,"corrections":5,"seconds":45}"#
    let run = try JSONDecoder().decode(TypingRun.self, from: Data(json.utf8))
    #expect(run.typedCharacters == 190)
    #expect(run.keyboard == "Apple" && run.errorsLeft == 2 && run.corrections == 5 && run.seconds == 45)
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
        targetCharacters: 214, typedCharacters: 211, errorsLeft: 3, corrections: 9, seconds: 61.5)
    static let second = TypingRun(
        date: Date(timeIntervalSinceReferenceDate: 800_000_600.5), keyboard: "Apple",
        targetCharacters: 198, typedCharacters: 199, errorsLeft: 1, corrections: 4, seconds: 48.125)

    init() {
        suiteFolder = FileManager.default.temporaryDirectory.appendingPathComponent("kittykeys-tests-\(UUID())")
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
        #expect(store.lastMajorityLanguage == nil)
    }

    @Test func appendThenLoadRoundTrips() {
        store.append(Self.first)
        #expect(store.load() == [Self.first])
        #expect(TypingRunStore(defaults: UserDefaults(suiteName: suiteName)!).load() == [Self.first])
        #expect(defaults.object(forKey: "catkeys.typingTest.runs") != nil)
    }

    @Test func aRunOfNowRoundTripsExactly() {
        // The app relabels the run it holds in memory, so its date must survive saving to the last bit.
        let run = TypingRun(date: .now, keyboard: "Apple", targetCharacters: 187, typedCharacters: 186, errorsLeft: 1,
                            corrections: 3, seconds: 41.123456789)
        store.append(run)
        #expect(store.load() == [run])
    }

    @Test func newestFirst() {
        store.append(Self.first)
        store.append(Self.second)
        #expect(store.load() == [Self.second, Self.first])
    }

    @Test func corruptDataLoadsEmpty() {
        defaults.set(Data([0xDE, 0xAD, 0xBE, 0xEF]), forKey: "catkeys.typingTest.runs")
        #expect(store.load().isEmpty)
        defaults.set(Data(#"[{"keyboard":"kittykeys"}]"#.utf8), forKey: "catkeys.typingTest.runs")
        #expect(store.load().isEmpty)
        defaults.set(Data(#"{"runs":[]}"#.utf8), forKey: "catkeys.typingTest.runs")
        #expect(store.load().isEmpty)
        defaults.set("not data", forKey: "catkeys.typingTest.runs")
        #expect(store.load().isEmpty)

        store.append(Self.first)   // a new run replaces what couldn't be read
        #expect(store.load() == [Self.first])
    }

    @Test func oldRunsWithoutTypedCharactersLoad() {
        let old = #"[{"date":800000000,"keyboard":"Apple","targetCharacters":190,"errorsLeft":2,"corrections":5,"seconds":45}]"#
        defaults.set(Data(old.utf8), forKey: "catkeys.typingTest.runs")
        let expected = TypingRun(date: Date(timeIntervalSinceReferenceDate: 800_000_000), keyboard: "Apple",
                                 targetCharacters: 190, typedCharacters: 190, errorsLeft: 2, corrections: 5, seconds: 45)
        #expect(store.load() == [expected])

        store.append(Self.first)   // saving again keeps the old run, now with the field
        #expect(store.load() == [Self.first, expected])
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

    @Test func replaceUpdatesTheRunWithTheSameDate() {
        store.append(Self.first)
        store.append(Self.second)
        var relabelled = Self.second
        relabelled.keyboard = "kittykeys"
        #expect(store.replace(relabelled))
        #expect(store.load() == [relabelled, Self.first])
    }

    @Test func replaceOfAnUnknownRunChangesNothing() {
        store.append(Self.first)
        #expect(!store.replace(Self.second))
        #expect(store.load() == [Self.first])
    }

    @Test func removeDeletesOnlyThatRun() {
        store.append(Self.first)
        store.append(Self.second)
        store.remove(id: Self.second.id)
        #expect(store.load() == [Self.first])
        store.remove(id: Self.second.id)   // already gone
        #expect(store.load() == [Self.first])
        store.remove(id: Self.first.id)
        #expect(store.load().isEmpty)
    }

    @Test func lastMajorityLanguageRoundTrips() {
        store.lastMajorityLanguage = "hi-Latn"            // nonmutating: works on a `let` store
        #expect(store.lastMajorityLanguage == "hi-Latn")
        #expect(TypingRunStore(defaults: UserDefaults(suiteName: suiteName)!).lastMajorityLanguage == "hi-Latn")
        store.lastMajorityLanguage = nil
        #expect(store.lastMajorityLanguage == nil)
        defaults.set(42, forKey: "catkeys.typingTest.lastMajority")
        #expect(store.lastMajorityLanguage == nil)
    }
}
