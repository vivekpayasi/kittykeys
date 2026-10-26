/// Haptics and sound for key presses. The keyboard extension plays them; tests count the calls.
/// Main-actor isolated, like the controller that calls it and UIKit's feedback generators.
@MainActor public protocol FeedbackSink: AnyObject {
    /// A finger landed on a key.
    func keyDown()
    /// Cursor mode moved the cursor one step.
    func cursorTick()
}
