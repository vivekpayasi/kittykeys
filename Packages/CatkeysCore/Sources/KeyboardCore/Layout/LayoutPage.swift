public enum RowKind: String, Sendable, Decodable {
    case number, keys
}

public struct LayoutRow: Equatable, Sendable, Decodable {
    public var kind: RowKind
    public var keys: [KeySpec]
}

/// Which bottom row a text field gets. Raw values are the keys under `bottom` in a layout file.
public enum BottomVariant: String, Sendable, CaseIterable {
    case standard = "default", email, url
}

/// One keyboard page, as a layout file describes it.
public struct LayoutPage: Equatable, Sendable, Decodable {
    public var id: String
    /// The rows above the bottom row. `rows[0]` is the number row.
    public var rows: [LayoutRow]
    private var bottom: [String: [KeySpec]]

    /// The bottom row for `variant`, or the standard one when the page has no such variant.
    public func bottomRow(_ variant: BottomVariant) -> [KeySpec] {
        bottom[variant.rawValue] ?? bottom[BottomVariant.standard.rawValue] ?? []
    }
}
