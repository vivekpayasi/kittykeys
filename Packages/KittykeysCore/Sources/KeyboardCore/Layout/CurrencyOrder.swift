/// The order the keys offer currencies in: the user's choice, or else their region's, first, then the layout's list
/// (`LayoutSet.currencies`) in its own order. Layout files name the slots with placeholders, so no currency is
/// hard-coded in a key: a key labelled `{currency1}` shows the first, `{currency2}` the second, and a long-press
/// option `{currencies}` stands for the first `holdCount`.
public enum CurrencyOrder {
    /// How many currencies a `{currencies}` long-press offers.
    public static let holdCount = 5

    /// `all` with `choice` first, or else `region` (from `LayoutSet.currencySymbol(forCode:)`) first. A choice or a
    /// region currency the list lacks leaves the list's order.
    public static func ordered(choice: String, region: String?, all: [String]) -> [String] {
        let first = all.contains(choice) ? choice : region.flatMap { all.contains($0) ? $0 : nil }
        guard let first else { return all }
        return [first] + all.filter { $0 != first }
    }
}

extension KeySpec {
    /// The key with its currency placeholders filled from `ordered`. A placeholder with no currency to fill it stays.
    func resolvingCurrencies(_ ordered: [String]) -> KeySpec {
        var key = self
        if let symbol = Self.currency(named: label, in: ordered) {
            key.label = symbol
            key.output = symbol
        }
        key.longPress = longPress.flatMap { $0 == "{currencies}" ? Array(ordered.prefix(CurrencyOrder.holdCount)) : [$0] }
        return key
    }

    /// The currency a `{currencyN}` placeholder names, counting from 1, or nil for any other text.
    private static func currency(named placeholder: String, in ordered: [String]) -> String? {
        let prefix = "{currency", suffix = "}"
        guard placeholder.hasPrefix(prefix), placeholder.hasSuffix(suffix),
              let n = Int(placeholder.dropFirst(prefix.count).dropLast(suffix.count)), n >= 1,
              ordered.indices.contains(n - 1)
        else { return nil }
        return ordered[n - 1]
    }
}
