/// Shift: off, on for the next letter, or caps lock.
public enum ShiftState: Sendable { case off, once, locked }

/// A key's long-press options on screen.
public struct AlternatesPopup: Equatable, Sendable {
    /// The key's id in the controller's current `frames`.
    public var keyID: Int
    /// The options in display order, left to right.
    public var options: [String]
    /// The highlighted option, an index into `options`.
    public var selected: Int
    /// Where the first cell starts.
    public var originX: Double
    /// Each option's cell width: `TouchTiming.alternateWidth`, times the key's `longPressWidth`.
    public var cellWidth: Double
}

/// What fills the keyboard below the suggestion row: the keys, the emoji panel in their place, or emoji search.
/// Search (ruling M3-R15) shows the letter keys again, without their number row, and they type into
/// `KeyboardState.searchQuery` rather than the document.
public enum KeyboardPanel: Equatable, Sendable { case keys, emoji, emojiSearch }

/// Everything the keyboard view draws apart from the key frames.
/// Key ids index the controller's current `frames`; a page or width change clears every one of them.
public struct KeyboardState: Equatable, Sendable {
    /// The emoji panel covers the keys without changing their page or frames, so closing it shows the same keys.
    /// Search has keys of its own, and the panel's keys come back when it closes.
    public var panel: KeyboardPanel = .keys
    public var pageID: String
    /// The document's shift. Emoji search leaves it alone for when the keys come back; the keys show `shownShift`.
    public var shift: ShiftState
    public var returnKey: ReturnKeyKind
    /// Keys with a finger on them.
    public var pressedKeyIDs: Set<Int>
    /// The key whose magnified preview shows: the latest pressed character key, while key popups are on in settings.
    public var previewKeyID: Int?
    public var alternates: AlternatesPopup?
    /// Whether space is moving the cursor; the view hides the key labels meanwhile.
    public var cursorMode: Bool
    /// What the user typed into emoji search: lowercase, at most 64 characters, never starting with a space or holding
    /// two in a row. Empty outside search.
    public var searchQuery = ""

    /// The shift the keys show: off in emoji search, whose query takes no capitals, and `shift` otherwise.
    public var shownShift: ShiftState {
        panel == .emojiSearch ? .off : shift
    }
}
