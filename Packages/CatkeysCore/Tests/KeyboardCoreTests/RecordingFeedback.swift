import KeyboardCore

/// A `FeedbackSink` for tests that counts its calls.
@MainActor final class RecordingFeedback: FeedbackSink {
    private(set) var keyDowns = 0, cursorTicks = 0

    func keyDown() { keyDowns += 1 }

    func cursorTick() { cursorTicks += 1 }
}
