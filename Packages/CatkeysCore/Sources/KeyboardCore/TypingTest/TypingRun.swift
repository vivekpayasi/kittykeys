import Foundation

/// The numbers from one run of the typing test. The typed text is never kept. A run is identified by its date.
public struct TypingRun: Codable, Equatable, Sendable, Identifiable {
    public var date: Date
    /// Which keyboard the run used, as the user picked it: "catkeys", "Apple" or "Other".
    public var keyboard: String
    /// The characters in the run's target sentences.
    public var targetCharacters: Int
    /// The characters submitted, summed over the run. Runs saved before this was kept read it as `targetCharacters`.
    public var typedCharacters: Int
    /// The edit distance between each target and what was submitted, summed over the run.
    public var errorsLeft: Int
    /// The characters deleted while typing.
    public var corrections: Int
    /// The time spent typing: each sentence from its first edit to Done, without time away from the app.
    public var seconds: Double

    public init(
        date: Date, keyboard: String, targetCharacters: Int, typedCharacters: Int, errorsLeft: Int, corrections: Int,
        seconds: Double
    ) {
        self.date = date
        self.keyboard = keyboard
        self.targetCharacters = targetCharacters
        self.typedCharacters = typedCharacters
        self.errorsLeft = errorsLeft
        self.corrections = corrections
        self.seconds = seconds
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        date = try container.decode(Date.self, forKey: .date)
        keyboard = try container.decode(String.self, forKey: .keyboard)
        targetCharacters = try container.decode(Int.self, forKey: .targetCharacters)
        typedCharacters = try container.decodeIfPresent(Int.self, forKey: .typedCharacters) ?? targetCharacters
        errorsLeft = try container.decode(Int.self, forKey: .errorsLeft)
        corrections = try container.decode(Int.self, forKey: .corrections)
        seconds = try container.decode(Double.self, forKey: .seconds)
    }

    public var id: Date { date }

    /// Errors left per target character, 0 to 1 when the errors are fewer than the characters. 0 with no target.
    public var errorRate: Double {
        targetCharacters > 0 ? Double(errorsLeft) / Double(targetCharacters) : 0
    }

    /// Speed over the characters actually typed.
    public var wordsPerMinute: Double {
        TypingMetrics.wordsPerMinute(characters: typedCharacters, seconds: seconds)
    }
}

/// The typing test's past runs in a `UserDefaults`, newest first, and which language last got the extra sentence.
/// In the app it sits on the app's own `.standard` defaults; the keyboard never reads it. Never traps: missing or
/// corrupt data reads as no runs.
public struct TypingRunStore {
    private static let runsKey = "catkeys.typingTest.runs"
    private static let lastMajorityKey = "catkeys.typingTest.lastMajority"

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

    /// Saves `run` in front of the others.
    public func append(_ run: TypingRun) {
        save([run] + load())
    }

    /// Saves `run` in place of the saved run with the same date, such as one relabelled with another keyboard.
    /// Returns false, changing nothing, if no saved run has that date.
    @discardableResult
    public func replace(_ run: TypingRun) -> Bool {
        var runs = load()
        guard let index = runs.firstIndex(where: { $0.id == run.id }) else { return false }
        runs[index] = run
        save(runs)
        return true
    }

    /// Deletes the saved run with this date, if there is one.
    public func remove(id: TypingRun.ID) {
        let runs = load()
        let kept = runs.filter { $0.id != id }
        if kept.count != runs.count { save(kept) }
    }

    /// The language that got the extra sentence in the last draw, so the next draw can give it to the other.
    public var lastMajorityLanguage: String? {
        get { defaults.object(forKey: Self.lastMajorityKey) as? String }
        nonmutating set { defaults.set(newValue, forKey: Self.lastMajorityKey) }
    }

    /// Seconds that aren't finite, which JSON can't hold, are saved as 0.
    private func save(_ runs: [TypingRun]) {
        let runs = runs.map { run in
            var run = run
            if !run.seconds.isFinite { run.seconds = 0 }
            return run
        }
        guard let data = try? JSONEncoder().encode(runs) else { return }
        defaults.set(data, forKey: Self.runsKey)
    }
}
