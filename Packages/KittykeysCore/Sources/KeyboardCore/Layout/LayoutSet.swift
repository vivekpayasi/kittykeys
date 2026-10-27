import Foundation

/// The pages of one layout, loaded from the bundled `Layouts` folder.
public struct LayoutSet: Sendable {
    public var lettersPageID: String
    /// The key that switches to the next keyboard, for devices where iOS draws none (`needsInputModeSwitchKey`).
    /// nil when the layout set has none.
    public var globeKey: KeySpec?
    /// The currencies the keys can offer, in their usual order (`CurrencyOrder`).
    public var currencies: [String]
    /// Which of `currencies` each ISO 4217 code names, such as "INR" for "₹". Several codes can share one symbol.
    private var currencyCodes: [String: String]
    private var pages: [String: LayoutPage]
    /// The page ids in the index's order.
    private var pageOrder: [String]

    public enum LoadError: Error {
        case missingFile(String)
    }

    private struct Index: Decodable {
        var letters: String
        var pages: [String]
        var globeKey: KeySpec?
        var currencies: [String]?
        var currencyCodes: [String: String]?
    }

    /// Reads `Layouts/index.json` and every page it lists.
    public static func bundled() throws -> LayoutSet {
        let decoder = JSONDecoder()
        let index = try decoder.decode(Index.self, from: try layoutFile("index"))
        var pages: [String: LayoutPage] = [:]
        var pageOrder: [String] = []
        for name in index.pages {
            let page = try decoder.decode(LayoutPage.self, from: try layoutFile(name))
            if pages[page.id] == nil { pageOrder.append(page.id) }
            pages[page.id] = page
        }
        return LayoutSet(
            lettersPageID: index.letters, globeKey: index.globeKey, currencies: index.currencies ?? [],
            currencyCodes: index.currencyCodes ?? [:], pages: pages, pageOrder: pageOrder)
    }

    private static func layoutFile(_ name: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Layouts") else {
            throw LoadError.missingFile("\(name).json")
        }
        return try Data(contentsOf: url)
    }

    /// The symbol among `currencies` for an ISO 4217 code, such as "₹" for "INR"; nil for a code the layout doesn't
    /// list. Regions are matched by code, since their own symbols vary, such as Japan's full-width "￥".
    public func currencySymbol(forCode code: String?) -> String? {
        code.flatMap { currencyCodes[$0] }
    }

    /// The page as its file has it, with any currency placeholders unfilled.
    public func page(_ id: String) -> LayoutPage? {
        pages[id]
    }

    /// The page with its currency placeholders filled from `currencies`, in `CurrencyOrder`'s order.
    public func page(_ id: String, currencies: [String]) -> LayoutPage? {
        pages[id]?.mappingKeys { $0.resolvingCurrencies(currencies) }
    }

    /// The first key `matches` accepts, looking through the pages in the index's order, each from its number row
    /// down to its bottom rows (standard, email, URL, then URL with .com). The emoji panel copies its ABC and ⌫ labels from the keys
    /// that do the same jobs, so they come from the layout's data.
    public func firstKey(where matches: (KeySpec) -> Bool) -> KeySpec? {
        for id in pageOrder {
            guard let page = pages[id] else { continue }
            let rows = page.rows.map(\.keys) + BottomVariant.allCases.map { page.bottomRow($0) }
            for row in rows {
                if let key = row.first(where: matches) { return key }
            }
        }
        return nil
    }

    /// The page id a `PageRef` points to.
    public func resolve(_ ref: PageRef) -> String {
        switch ref {
        case .letters: lettersPageID
        case .named(let id): id
        }
    }
}
