/// One finger, from touch-down to lift or cancel. The caller picks the ids; fingers down at the same time need different ones.
public typealias TouchID = Int

/// What the keyboard does in response to touches.
public enum TouchEvent: Equatable, Sendable {
    /// A finger landed on the key: highlight it and give feedback.
    case keyDown(KeyFrame)
    /// The finger left the key: clear its highlight, its key preview and any long-press popup.
    case keyUp(KeyFrame)
    /// Perform the key's action. `landing` is where the finger touched down.
    case activate(KeyFrame, landing: Point)
    /// Show the key's long-press options in cells starting at `originX`, with `selected` highlighted.
    case alternatesShown(KeyFrame, options: [String], selected: Int, originX: Double)
    /// Highlight a different long-press option.
    case alternateSelected(KeyFrame, selected: Int)
    /// Type the chosen long-press option.
    case activateAlternate(KeyFrame, text: String)
    /// Delete the character before the cursor, or the word before it.
    case deleteBackward(word: Bool)
    /// Space-bar cursor mode started or ended.
    case cursorModeBegan, cursorModeEnded
    /// Move the cursor this many characters; negative is backward.
    case cursorMoved(characters: Int)
    /// Move the cursor this many lines; negative is up.
    case cursorMovedLines(Int)
}
