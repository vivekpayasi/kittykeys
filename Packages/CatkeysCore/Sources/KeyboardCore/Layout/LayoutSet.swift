import Foundation

/// The pages of one layout, loaded from the bundled `Layouts` folder.
public struct LayoutSet: Sendable {
    public var lettersPageID: String
    /// The key that switches to the next keyboard, for devices where iOS draws none (`needsInputModeSwitchKey`).
    /// nil when the layout set has none.
    public var globeKey: KeySpec?
    private var pages: [String: LayoutPage]

    public enum LoadError: Error {
        case missingFile(String)
    }

    private struct Index: Decodable {
        var letters: String
        var pages: [String]
        var globeKey: KeySpec?
    }

    /// Reads `Layouts/index.json` and every page it lists.
    public static func bundled() throws -> LayoutSet {
        let decoder = JSONDecoder()
        let index = try decoder.decode(Index.self, from: try layoutFile("index"))
        var pages: [String: LayoutPage] = [:]
        for name in index.pages {
            let page = try decoder.decode(LayoutPage.self, from: try layoutFile(name))
            pages[page.id] = page
        }
        return LayoutSet(lettersPageID: index.letters, globeKey: index.globeKey, pages: pages)
    }

    private static func layoutFile(_ name: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Layouts") else {
            throw LoadError.missingFile("\(name).json")
        }
        return try Data(contentsOf: url)
    }

    public func page(_ id: String) -> LayoutPage? {
        pages[id]
    }

    /// The page id a `PageRef` points to.
    public func resolve(_ ref: PageRef) -> String {
        switch ref {
        case .letters: lettersPageID
        case .named(let id): id
        }
    }
}
