import Testing
@testable import KeyboardCore

// Emoji search (ruling M3-R15): every word of the query begins one of an emoji's keywords, its English name's words or
// its tags. Exact matches come first, then name matches, then tag matches; within each, Recent first, then the catalog's
// order.

struct EmojiSearchTests {
    /// The bundled keywords, and the bundled catalog for an iOS that draws up to `maxVersion`.
    static func bundled(maxVersion: Double = 17.0) throws -> (search: EmojiSearch, catalog: EmojiData) {
        (try EmojiSearch.load(), try EmojiCatalog.load(maxVersion: maxVersion))
    }

    /// A one-category catalog of `bases`, in that order.
    static func catalog(_ bases: [String]) -> EmojiData {
        EmojiData(
            recentName: "Recent", recentIcon: "clock",
            categories: [
                EmojiCategory(id: "c", name: "C", icon: "i", items: bases.map { EmojiItem(base: $0, version: 1, skins: []) })
            ])
    }

    static func bases(_ search: EmojiSearch, _ query: String, _ catalog: EmojiData, recents: [String] = []) -> [String] {
        search.results(for: query, catalog: catalog, recents: recents).map(\.base)
    }

    // MARK: Matching

    @Test func laughFindsTearsOfJoyNearTheFront() throws {
        let (search, catalog) = try Self.bundled()
        let results = Self.bases(search, "lau", catalog)
        // 🤣's name says "laughing". The rest have only the tag "laugh", so they keep the catalog's order:
        // 😀 😄 😆 😂. Without a popularity signal, 😂 is fifth until Recent nudges it (`recentGoesFirstWithinItsTier`).
        #expect(results.first == "🤣")
        #expect(results.prefix(5).contains("😂"))
    }

    @Test func redHeartComesFirst() throws {
        let (search, catalog) = try Self.bundled()
        #expect(Self.bases(search, "red heart", catalog).first == "❤️")
        // Capitals and extra spaces make no difference.
        #expect(Self.bases(search, "  Red   HEART ", catalog).first == "❤️")
        // Every word must match: the red circle has no "heart".
        #expect(!Self.bases(search, "red heart", catalog).contains("🔴"))
    }

    @Test func wordBeginningsMatch() throws {
        let (search, catalog) = try Self.bundled()
        #expect(Self.bases(search, "hea", catalog).contains("❤️"))
        // Only beginnings: "eart" is inside "heart".
        #expect(!Self.bases(search, "eart", catalog).contains("❤️"))
    }

    @Test(arguments: ["zzzz", "", "   ", "!?", "red zzzz"])
    func noMatchGivesNothing(_ query: String) throws {
        let (search, catalog) = try Self.bundled()
        #expect(Self.bases(search, query, catalog).isEmpty)
    }

    @Test func punctuationSeparatesWords() throws {
        let (search, catalog) = try Self.bundled()
        // The data splits "T-Rex" into "rex" and the joined "trex", and drops accents from "Curaçao".
        #expect(Self.bases(search, "t-rex", catalog).first == "🦖")
        #expect(Self.bases(search, "trex", catalog) == ["🦖"])
        #expect(Self.bases(search, "o'clock", catalog).contains("🕐"))
        #expect(Self.bases(search, "wifi", catalog).contains("🛜"))
        #expect(Self.bases(search, "curacao", catalog) == ["🇨🇼"])
        #expect(Self.bases(search, "heart,", catalog) == Self.bases(search, "heart", catalog))
    }

    // MARK: Ranking

    @Test func exactThenNameThenTag() {
        let search = EmojiSearch(keywords: [
            "🅰️": (label: ["catalog"], tags: []),
            "🅱️": (label: ["dog"], tags: ["cats"]),
            "🆎": (label: ["kitten"], tags: ["cat"]),
            "🅾️": (label: ["cat"], tags: []),
            "🆑": (label: ["dog"], tags: []),
        ])
        let catalog = Self.catalog(["🅰️", "🅱️", "🆎", "🅾️", "🆑"])
        // An exact word, name or tag, first; then the beginning of a name word; then the beginning of a tag.
        // The catalog's order within each.
        #expect(Self.bases(search, "cat", catalog) == ["🆎", "🅾️", "🅰️", "🅱️"])
        #expect(Self.bases(search, "CATS", catalog) == ["🅱️"])
    }

    @Test func aQueryRanksByItsWeakestWord() {
        let search = EmojiSearch(keywords: [
            "🅰️": (label: ["grinning", "cat"], tags: ["face"]),
            "🅱️": (label: ["cat", "face"], tags: []),
        ])
        let catalog = Self.catalog(["🅰️", "🅱️"])
        // "cat" is exact for both; "fa" begins a name word only in 🅱️.
        #expect(Self.bases(search, "cat fa", catalog) == ["🅱️", "🅰️"])
        // Both words exact for both: the catalog's order.
        #expect(Self.bases(search, "face cat", catalog) == ["🅰️", "🅱️"])
    }

    @Test func recentGoesFirstWithinItsTier() throws {
        let (search, catalog) = try Self.bundled()
        #expect(Self.bases(search, "laugh", catalog) == ["😀", "😄", "😆", "🤣", "😂", "😹"])
        // Recent ones lead their tier, most recent first; 👍 matches nothing here.
        #expect(Self.bases(search, "laugh", catalog, recents: ["😹", "👍", "😆"]) == ["😹", "😆", "😀", "😄", "🤣", "😂"])
        // A recent tag match stays behind a name match.
        #expect(Self.bases(search, "lau", catalog, recents: ["😂"]).prefix(2) == ["🤣", "😂"])
        // Recent keeps the exact variant typed, with a skin tone or without U+FE0F; it counts for its emoji.
        #expect(Self.bases(search, "thumbs", catalog) == ["👍", "👎"])
        #expect(Self.bases(search, "thumbs", catalog, recents: ["👎🏽"]) == ["👎", "👍"])
        #expect(Self.bases(search, "heart", catalog, recents: ["❤"]).first == "❤️")
    }

    // MARK: Catalog and limit

    @Test func onlyTheCatalogsEmojiComeBack() throws {
        let (search, v17) = try Self.bundled()
        let v16 = try EmojiCatalog.load(maxVersion: 16.0)
        #expect(Self.bases(search, "orca", v17) == ["🫍"])
        #expect(Self.bases(search, "orca", v16).isEmpty)
        #expect(search.results(for: "whale", catalog: v16, recents: ["🫍"]).allSatisfy { $0.version <= 16.0 })
        // The catalog's own items come back, in its order and with their skins.
        let all = v17.categories.flatMap(\.items)
        let picked = ["👋", "😹", "😂"].compactMap { base in all.first { $0.base == base } }
        let small = EmojiData(
            recentName: "Recent", recentIcon: "clock", categories: [EmojiCategory(id: "c", name: "C", icon: "i", items: picked)])
        #expect(search.results(for: "laugh", catalog: small, recents: []).map(\.base) == ["😹", "😂"])
        #expect(search.results(for: "wave", catalog: small, recents: []).first?.skins.count == 5)
    }

    @Test func limitCapsTheResults() throws {
        let (search, catalog) = try Self.bundled()
        let all = search.results(for: "s", catalog: catalog, recents: [], limit: 10_000)
        #expect(all.count > 60)
        #expect(search.results(for: "s", catalog: catalog, recents: []) == Array(all.prefix(60)))
        #expect(search.results(for: "s", catalog: catalog, recents: [], limit: 3) == Array(all.prefix(3)))
        #expect(search.results(for: "s", catalog: catalog, recents: [], limit: 0).isEmpty)
    }

    // MARK: Data

    @Test func everyCatalogEmojiHasKeywords() throws {
        let (search, catalog) = try Self.bundled()
        let items = catalog.categories.flatMap(\.items)
        #expect(items.allSatisfy { search.keywords(for: $0.base) != nil })
        #expect(search.keywords(for: "🦖")?.label == ["rex", "trex"])
        #expect(search.keywords(for: "❤️")?.label == ["red", "heart"])
        // Skin variants have no keys of their own: Recent's variants reach their emoji through its base.
        #expect(search.keywords(for: "👋🏽") == nil)
    }
}

/// The keyword data is loaded when search first opens and kept for the keyboard process, like the catalog
/// (ruling M3-R11): loaded once, freed on request, loaded again after that, and never retried after a failure.
@MainActor struct EmojiSearchStoreTests {
    struct Broken: Error {}

    static let sample = EmojiSearch(keywords: ["😂": (label: ["face"], tags: ["laugh"])])

    @Test func loadsOnceAndReuses() throws {
        var loads = 0
        let store = EmojiSearchStore {
            loads += 1
            return Self.sample
        }
        #expect(!store.isLoaded && loads == 0)
        let search = try store.search()
        #expect(search.results(for: "lau", catalog: EmojiSearchTests.catalog(["😂"]), recents: []).map(\.base) == ["😂"])
        #expect(store.isLoaded)
        _ = try store.search()
        _ = try store.search()
        #expect(loads == 1)
    }

    @Test func releaseFreesAndTheNextUseLoadsAgain() throws {
        var loads = 0
        let store = EmojiSearchStore {
            loads += 1
            return Self.sample
        }
        _ = try store.search()
        store.release()
        #expect(!store.isLoaded && loads == 1)
        _ = try store.search()
        #expect(store.isLoaded && loads == 2)
    }

    @Test func failureIsKeptAndNotRetried() {
        var loads = 0
        let store = EmojiSearchStore {
            loads += 1
            throw Broken()
        }
        #expect(throws: Broken.self) { try store.search() }
        #expect(throws: Broken.self) { try store.search() }
        store.release()
        #expect(throws: Broken.self) { try store.search() }
        #expect(loads == 1 && !store.isLoaded)
    }

    @Test func sharedStoreLoadsTheBundledKeywords() throws {
        #expect(try EmojiSearchStore.shared.search().keywords(for: "😂") != nil)
    }
}
