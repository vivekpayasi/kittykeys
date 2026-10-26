/// The user's text replacements from iOS (Settings › General › Keyboard › Text Replacement), such as "omw" for
/// "On my way!". Typing a shortcut and then a word end (`isTrigger(_:)`) types the phrase in its place. The user made
/// every pair, so this is no autocorrect: nothing else is ever replaced.
public struct TextReplacements: Equatable, Sendable {
    public static let none = TextReplacements(pairs: [])

    /// Phrases by lowercased shortcut.
    private let phrases: [String: String]

    /// `pairs` as iOS lists them. iOS lists contact names too, each as its own shortcut; those are dropped, and so is a
    /// pair with an empty side or whitespace in its shortcut, which can't be typed as one word. Of two shortcuts that
    /// differ only in case, the first wins.
    public init(pairs: [(shortcut: String, phrase: String)]) {
        var phrases: [String: String] = [:]
        for (shortcut, phrase) in pairs
        where !shortcut.isEmpty && !phrase.isEmpty && shortcut != phrase && !shortcut.contains(where: \.isWhitespace) {
            let key = shortcut.lowercased()
            if phrases[key] == nil { phrases[key] = phrase }
        }
        self.phrases = phrases
    }

    public var isEmpty: Bool { phrases.isEmpty }

    /// The phrase for a shortcut that ends `textBefore`, and the shortcut's length in graphemes. The shortcut is the
    /// whole run of non-space characters before the cursor, or else that run's last word, so "(omw" finds "omw".
    /// It matches in any case, and a capital typed first capitalises the phrase. nil when no shortcut ends the text.
    public func replacement(before textBefore: String?) -> (length: Int, phrase: String)? {
        guard !phrases.isEmpty, let textBefore else { return nil }
        let run = String(textBefore.reversed().prefix { !$0.isWhitespace }.reversed())
        for length in [run.count, TextRules.trailingRunLength(before: run)] where length > 0 {
            let typed = run.suffix(length)
            if let phrase = phrases[typed.lowercased()] {
                return (length, Self.capitalized(phrase, after: typed))
            }
        }
        return nil
    }

    /// Whether typing `text` ends a word: whitespace, a sentence terminal from Unicode (".", "!", "?", "।" and others),
    /// or a comma, semicolon or colon.
    public static func isTrigger(_ text: String) -> Bool {
        guard text.count == 1, let character = text.first else { return false }
        if character.isWhitespace || [",", ";", ":"].contains(character) { return true }
        return character.unicodeScalars.count == 1 && character.unicodeScalars.first?.properties.isSentenceTerminal == true
    }

    /// `phrase` with its first letter capitalised when `typed` starts with a capital and the phrase with a small letter.
    private static func capitalized(_ phrase: String, after typed: Substring) -> String {
        guard typed.first?.isUppercase == true, let first = phrase.first, first.isLowercase else { return phrase }
        return first.uppercased() + phrase.dropFirst()
    }
}
