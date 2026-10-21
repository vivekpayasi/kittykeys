import KeyboardCore

/// An in-memory `TextDocument` for tests: the text is a `[Character]` with a cursor counted in graphemes.
final class FakeTextDocument: TextDocument {
    private var characters: [Character]
    private(set) var cursor: Int

    /// A nil `cursor` puts it at the end of `text`.
    init(_ text: String, cursor: Int? = nil) {
        characters = Array(text)
        self.cursor = cursor ?? characters.count
        precondition((0...characters.count).contains(self.cursor), "cursor \(self.cursor) is outside \"\(text)\"")
    }

    var text: String { String(characters) }

    var textBefore: String? { String(characters[..<cursor]) }

    var textAfter: String? { String(characters[cursor...]) }

    func insert(_ text: String) {
        characters.insert(contentsOf: text, at: cursor)
        cursor += text.count
    }

    func deleteBackward(count: Int) {
        let removed = min(max(count, 0), cursor)
        characters.removeSubrange((cursor - removed)..<cursor)
        cursor -= removed
    }

    func moveCursor(by graphemes: Int) {
        cursor = min(max(cursor + graphemes, 0), characters.count)
    }
}
