/// Cursor moves worked out from the text around the cursor, in grapheme clusters.
public enum CursorMath {
    /// The grapheme offset that moves the cursor `lines` hard line breaks up (negative) or down (positive),
    /// keeping its column: the number of graphemes since the last line break. On a shorter line the cursor
    /// goes to that line's end. A move past the last known line break stops at that line;
    /// with no hard line break that way the offset is 0. Soft-wrapped lines are invisible here.
    public static func verticalMove(before: String?, after: String?, lines: Int) -> Int {
        let linesBefore = hardLines(before)     // the last one is the cursor's line up to the cursor
        let column = linesBefore.last?.count ?? 0
        if lines < 0 {
            let steps = min(-lines, linesBefore.count - 1)
            guard steps > 0 else { return 0 }
            let target = linesBefore.count - 1 - steps
            let crossed = linesBefore[target..<(linesBefore.count - 1)]
            let backToTargetStart = column + crossed.reduce(0) { $0 + $1.count + 1 }
            return -backToTargetStart + min(column, linesBefore[target].count)
        } else {
            let linesAfter = hardLines(after)   // the first one is the rest of the cursor's line
            let steps = min(lines, linesAfter.count - 1)
            guard steps > 0 else { return 0 }
            let onToTargetStart = linesAfter[..<steps].reduce(0) { $0 + $1.count + 1 }
            return onToTargetStart + min(column, linesAfter[steps].count)
        }
    }

    /// The text split at hard line breaks, keeping empty lines; always at least one element.
    private static func hardLines(_ text: String?) -> [Substring] {
        (text ?? "").split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
    }
}
