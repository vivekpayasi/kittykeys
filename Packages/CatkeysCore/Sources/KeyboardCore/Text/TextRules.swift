/// Which automatic capitals the text field asks for (its `autocapitalizationType`).
public enum AutoCapMode: Sendable { case none, words, sentences, all }

/// Pure rules read from the text before the cursor. nil text means unknown or the start of the field.
public enum TextRules {
    /// Whether the next letter should be a capital.
    /// - `.sentences`: at the start of the field, after a line break, or after `.`, `!` or `?` and whitespace.
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
            return sentenceEnders.contains(lastTyped)
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
    public static func previousWordLength(before: String?) -> Int {
        guard let before else { return 0 }
        var length = 0
        var runIsWord: Bool?    // nil while still in the trailing whitespace
        for character in before.reversed() {
            if character.isWhitespace {
                if runIsWord != nil { break }
            } else {
                let isWord = isWordCharacter(character)
                if let runIsWord, runIsWord != isWord { break }
                runIsWord = isWord
            }
            length += 1
        }
        return length
    }

    private static let sentenceEnders: Set<Character> = [".", "!", "?"]

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber
    }
}
