/// Which automatic capitals the text field asks for (its `autocapitalizationType`).
public enum AutoCapMode: Sendable { case none, words, sentences, all }

/// Pure rules read from the text before the cursor. nil text means unknown or the start of the field.
public enum TextRules {
    /// Whether the next letter should be a capital.
    /// - `.sentences`: at the start of the field, after a line break, or after a sentence terminal and whitespace.
    ///   Sentence terminals come from Unicode (`.`, `!`, `?`, `।` and others), so no language is hard-coded.
    /// - `.words`: at the start of the field or after whitespace.
    public static func shouldCapitalize(before: String?, mode: AutoCapMode) -> Bool {
        switch mode {
        case .none:
            return false
        case .all:
            return true
        case .words:
            guard let last = before?.last else { return true }
            return last.isWhitespace
        case .sentences:
            guard let before, let last = before.last else { return true }
            if last.isNewline { return true }
            guard last.isWhitespace else { return false }
            // Only whitespace before the cursor counts as the start of the field.
            guard let lastTyped = before.last(where: { !$0.isWhitespace }) else { return true }
            return lastTyped.unicodeScalars.last?.properties.isSentenceTerminal == true
        }
    }

    /// Whether a second space should become a full stop: the text ends in a letter or digit and exactly one space.
    public static func isDoubleSpaceCandidate(before: String?) -> Bool {
        guard let before, before.last == " " else { return false }
        guard let previous = before.dropLast().last else { return false }
        return isWordCharacter(previous)
    }

    /// How many graphemes a word delete removes: the trailing whitespace, then one run of letters and digits
    /// or one run of other non-space characters (punctuation, emoji).
    /// An apostrophe (`'` or `’`) between two letters or digits stays inside the word, so "don't" goes in one delete.
    public static func previousWordLength(before: String?) -> Int {
        guard let before else { return 0 }
        let characters = Array(before)
        var end = characters.endIndex
        while end > 0, characters[end - 1].isWhitespace { end -= 1 }
        guard end > 0 else { return characters.count }
        return characters.count - runStart(in: characters, end: end)
    }

    /// How many graphemes the backspace swipe removes: the run touching the cursor, taken as `previousWordLength`
    /// takes it, but without skipping whitespace. 0 when the text is nil or empty or ends in whitespace,
    /// since then the touch-down delete already finished the word and the one before is a different word.
    public static func trailingRunLength(before: String?) -> Int {
        guard let before, let last = before.last, !last.isWhitespace else { return 0 }
        let characters = Array(before)
        return characters.count - runStart(in: characters, end: characters.endIndex)
    }

    /// Where the run ending just before `end` starts: letters and digits (with apostrophes inside the word),
    /// or else other non-space characters. `characters[end - 1]` must exist and not be whitespace.
    private static func runStart(in characters: [Character], end: Int) -> Int {
        var start = end
        if isWordCharacter(characters[start - 1]) {
            while start > 0, isWordCharacter(characters[start - 1]) || isApostropheInsideWord(characters, at: start - 1) {
                start -= 1
            }
        } else {
            while start > 0, !characters[start - 1].isWhitespace, !isWordCharacter(characters[start - 1]) { start -= 1 }
        }
        return start
    }

    private static let apostrophes: Set<Character> = ["'", "\u{2019}"]

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber
    }

    /// Whether `characters[index]` is an apostrophe with a letter or digit just before it. Called only while
    /// scanning a word backwards, so the character after it is already part of the word.
    private static func isApostropheInsideWord(_ characters: [Character], at index: Int) -> Bool {
        index > 0 && apostrophes.contains(characters[index]) && isWordCharacter(characters[index - 1])
    }
}
