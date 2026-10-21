/// The text field the keyboard edits. The keyboard extension wraps `UITextDocumentProxy`; tests use a fake.
/// Positions and counts are in grapheme clusters (`Character`s), never UTF-16 units.
/// Main-actor isolated, like `UITextDocumentProxy` and the keyboard controller.
@MainActor public protocol TextDocument: AnyObject {
    /// The text before the cursor. nil = unknown/start of field.
    var textBefore: String? { get }
    /// The text after the cursor. nil = unknown/end of field.
    var textAfter: String? { get }
    /// Inserts `text` at the cursor and leaves the cursor after it.
    func insert(_ text: String)
    /// Deletes up to `count` grapheme clusters before the cursor.
    func deleteBackward(count: Int)
    /// Moves the cursor by `graphemes` grapheme clusters; negative = left.
    func moveCursor(by graphemes: Int)
}
