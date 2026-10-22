import Foundation

/// The numbers from one run of the typing test. The typed text is never kept.
public struct TypingRun: Codable, Equatable, Sendable {
    public var date: Date
    /// Which keyboard the run used, as the user picked it: "catkeys", "Apple" or "Other".
    public var keyboard: String
    /// The characters in the run's target sentences.
    public var targetCharacters: Int
    /// The edit distance between each target and what was submitted, summed over the run.
    public var errorsLeft: Int
    /// The characters deleted while typing.
    public var corrections: Int
    /// The time spent typing, each sentence timed from its first edit to Done.
    public var seconds: Double

    public init(date: Date, keyboard: String, targetCharacters: Int, errorsLeft: Int, corrections: Int, seconds: Double) {
        self.date = date
        self.keyboard = keyboard
        self.targetCharacters = targetCharacters
        self.errorsLeft = errorsLeft
        self.corrections = corrections
        self.seconds = seconds
    }

    /// Errors left per target character, 0 to 1 when the errors are fewer than the characters. 0 with no target.
    public var errorRate: Double {
        targetCharacters > 0 ? Double(errorsLeft) / Double(targetCharacters) : 0
    }

    public var wordsPerMinute: Double {
        TypingMetrics.wordsPerMinute(characters: targetCharacters, seconds: seconds)
    }
}

/// The typing test's past runs in a `UserDefaults`, newest first. In the app it sits on the app's own `.standard`
/// defaults; the keyboard never reads it. Never traps: missing or corrupt data reads as no runs.
public struct TypingRunStore {
    private static let runsKey = "catkeys.typingTest.runs"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// The saved runs, newest first.
    public func load() -> [TypingRun] {
        guard let data = defaults.data(forKey: Self.runsKey),
              let runs = try? JSONDecoder().decode([TypingRun].self, from: data)
        else { return [] }
        return runs
    }

    /// Saves `run` in front of the others. Seconds that aren't finite, which JSON can't hold, are saved as 0.
    public func append(_ run: TypingRun) {
        var run = run
        if !run.seconds.isFinite { run.seconds = 0 }
        guard let data = try? JSONEncoder().encode([run] + load()) else { return }
        defaults.set(data, forKey: Self.runsKey)
    }
}
