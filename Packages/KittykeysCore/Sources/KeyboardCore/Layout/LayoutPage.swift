public enum RowKind: String, Sendable, Decodable {
    case number, keys
}

public struct LayoutRow: Equatable, Sendable, Decodable {
    public var kind: RowKind
    public var keys: [KeySpec]
}

/// Which bottom row a text field gets. Raw values are the keys under `bottom` in a layout file.
public enum BottomVariant: String, Sendable, CaseIterable {
    /// `urlWithDotCom` is the web-address row with a .com key, for `KeyboardSettings.showDotComKey`.
    case standard = "default", email, url, urlWithDotCom = "url-com"

    /// The variant a page without this one uses instead.
    var fallback: BottomVariant? {
        switch self {
        case .standard: nil
        case .email, .url: .standard
        case .urlWithDotCom: .url
        }
    }
}

/// One keyboard page, as a layout file describes it.
public struct LayoutPage: Equatable, Sendable, Decodable {
    public var id: String
    /// The rows above the bottom row. `rows[0]` is the number row.
    public var rows: [LayoutRow]
    private var bottom: [String: [KeySpec]]

    /// The bottom row for `variant`, or else its fallback's, down to the standard one.
    public func bottomRow(_ variant: BottomVariant) -> [KeySpec] {
        if let row = bottom[variant.rawValue] { return row }
        return variant.fallback.map(bottomRow) ?? []
    }

    /// The page with `transform` applied to every key, as to fill in currency placeholders.
    func mappingKeys(_ transform: (KeySpec) -> KeySpec) -> LayoutPage {
        var page = self
        page.rows = rows.map { LayoutRow(kind: $0.kind, keys: $0.keys.map(transform)) }
        page.bottom = bottom.mapValues { $0.map(transform) }
        return page
    }
}
