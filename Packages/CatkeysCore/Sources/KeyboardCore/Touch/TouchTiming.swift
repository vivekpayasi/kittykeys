/// How long touches are held and how far they travel before something happens. Times are in seconds, distances in points.
public struct TouchTiming: Sendable {
    /// Hold before a key's long-press options show (adjustable in settings), and before space starts cursor mode.
    public var longPress = 0.3, cursorHold = 0.33
    /// Backspace: the first repeat, the gap between character repeats,
    /// the hold after which repeats delete words, and the gap between word repeats.
    public var backspaceFirstRepeat = 0.4, backspaceRepeat = 0.07, backspaceWordsAfter = 1.5, backspaceWordRepeat = 0.2
    /// Cursor mode: travel per character, the speed in points per second above which each step
    /// moves `cursorFastMultiplier` characters, and travel per line.
    public var cursorStep = 9.0, cursorFastSpeed = 300.0, cursorFastMultiplier = 3, cursorLineStep = 30.0
    /// The leftward swipe on backspace that deletes the rest of the word, and the width of one long-press option cell.
    public var backspaceSwipe = 20.0, alternateWidth = 36.0

    public init() {}
}
