/// Converts grapheme counts into the UTF-16 offsets iOS's `adjustTextPosition(byCharacterOffset:)` takes.
public enum TextOffsets {
    /// The UTF-16 length of the `graphemes` grapheme clusters the cursor crosses: taken from the end of `before`
    /// when moving left (negative, and the result is negative) or the start of `after` when moving right.
    /// Graphemes beyond the known text count as one UTF-16 unit each, so the cursor still moves when the
    /// document only reports part of its text; iOS stops it at the ends of the field.
    public static func utf16Offset(graphemes: Int, before: String?, after: String?) -> Int {
        if graphemes < 0 {
            let crossed = (before ?? "").suffix(-graphemes)
            return -(crossed.utf16.count + (-graphemes - crossed.count))
        } else {
            let crossed = (after ?? "").prefix(graphemes)
            return crossed.utf16.count + (graphemes - crossed.count)
        }
    }
}
