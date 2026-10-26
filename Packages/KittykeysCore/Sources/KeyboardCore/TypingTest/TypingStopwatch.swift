import Foundation

/// Times the typing in a run of the typing test. Each sentence is timed from its first edit to Done, and the clock
/// stops while the app isn't active, so time spent away doesn't count. Times are seconds on a clock that only goes
/// forward, such as `ProcessInfo.systemUptime`.
public struct TypingStopwatch: Equatable, Sendable {
    /// The time counted so far, up to the last pause or finished sentence.
    public private(set) var seconds = 0.0
    /// Whether the current sentence has had its first edit.
    private var sentenceStarted = false
    private var appActive = true
    /// When the running stretch began; nil while the clock is stopped.
    private var runningSince: TimeInterval?

    public init() {}

    /// The text changed. The first edit of a sentence starts its clock, or, while the app isn't active, has it
    /// start when the app comes back.
    public mutating func edit(at now: TimeInterval) {
        guard !sentenceStarted else { return }
        sentenceStarted = true
        if appActive { runningSince = now }
    }

    /// The app stopped being active.
    public mutating func pause(at now: TimeInterval) {
        appActive = false
        stopClock(at: now)
    }

    /// The app is active again.
    public mutating func resume(at now: TimeInterval) {
        appActive = true
        if sentenceStarted && runningSince == nil { runningSince = now }
    }

    /// Done: the sentence's time is added, and the next sentence waits for its first edit.
    public mutating func finishSentence(at now: TimeInterval) {
        stopClock(at: now)
        sentenceStarted = false
    }

    private mutating func stopClock(at now: TimeInterval) {
        if let runningSince { seconds += max(0, now - runningSince) }
        runningSince = nil
    }
}
