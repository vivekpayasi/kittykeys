/// The things the app's Try it tab suggests, which the keyboard reports as the user does them. Only which ones were
/// done is kept, never what was typed. Raw values are saved in the shared settings (`SettingsStore.triedFeatures`).
public enum TryFeature: String, CaseIterable, Sendable {
    /// Holding space and sliding moved the cursor.
    case cursorMove
    /// A long-press option was typed.
    case longPressSymbol
    /// Sliding left from ⌫ deleted the rest of a word.
    case wordDelete
    /// A text replacement shortcut became its phrase.
    case textReplacement
    /// An emoji was typed from search's results.
    case emojiSearch
}
