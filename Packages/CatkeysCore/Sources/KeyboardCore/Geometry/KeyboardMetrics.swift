/// Fixed sizes for laying out the keyboard, in points.
public struct KeyboardMetrics: Sendable {
    public var suggestionRowHeight = 44.0, numberRowHeight = 36.0, keyHeight = 42.0
    public var rowGap = 10.0, keyGap = 6.0, sidePadding = 3.0, bottomPadding = 4.0

    public static let standard = KeyboardMetrics()

    /// The keyboard's full height for `rowCount` rows, counting the number row and the bottom row.
    ///
    /// That is the suggestion row, the number row, `rowCount - 1` key rows with a row gap above each,
    /// and the bottom padding.
    public func totalHeight(rowCount: Int) -> Double {
        suggestionRowHeight + numberRowHeight + Double(rowCount - 1) * (rowGap + keyHeight) + bottomPadding
    }
}
