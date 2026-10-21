import Foundation

/// The pages of one layout, loaded from the bundled `Layouts` folder.
public struct LayoutSet: Sendable {
    public var lettersPageID: String
    private var pages: [String: LayoutPage]

    public enum LoadError: Error {
        case missingFile(String)
    }

    private struct Index: Decodable {
        var letters: String
        var pages: [String]
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
        return LayoutSet(lettersPageID: index.letters, pages: pages)
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
