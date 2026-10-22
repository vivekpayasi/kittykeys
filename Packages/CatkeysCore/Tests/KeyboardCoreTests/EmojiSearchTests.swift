import Foundation
import Testing
@testable import KeyboardCore

// Emoji search (rulings M3-R15, M3-R17): every word of the query begins one of an emoji's keywords, its name's words or
// its tags. Tiers: a keyword exactly, the beginning of a name word, the beginning of a tag; a query ranks by its weakest
// word. Stopwords are optional and only lift the emoji they match. Within a tier: more optional words matched, Recent,
// the popular list, name matches before tag matches, shorter matched keywords, fewer name words, the catalog.

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

    @Test func laughFindsTearsOfJoyInTheTopThree() throws {
        let (search, catalog) = try Self.bundled()
        let results = Self.bases(search, "lau", catalog)
        // 🤣's name says "laughing". The rest only have tags beginning "lau"; popular 😂 leads them, and "laugh" is
        // shorter than the 🚀's "launch" and the 🧺's "laundry".
        #expect(results.first == "🤣")
        #expect(results.prefix(3).contains("😂"))
        #expect(results.firstIndex(of: "😀")! < results.firstIndex(of: "🚀")!)
    }

    @Test func commonWordsFindTheCommonEmoji() throws {
        let (search, catalog) = try Self.bundled()
        #expect(Self.bases(search, "heart", catalog).first == "❤️")
        #expect(Self.bases(search, "fire", catalog).first == "🔥")
        let cats: Set = ["🐈", "🐱", "😺", "😸", "😹", "😻", "😼", "😽", "🙀", "😿", "😾", "🐈‍⬛"]
        #expect(Self.bases(search, "cat", catalog).prefix(3).allSatisfy { cats.contains($0) })
        // A tag that is the word counts as exactly as a name word does.
        #expect(Self.bases(search, "thumb", catalog).prefix(2).contains("👍"))
        #expect(Self.bases(search, "pray", catalog).first == "🙏")
        #expect(Self.bases(search, "lol", catalog).first == "😂")
        #expect(Self.bases(search, "love", catalog).first == "❤️")
        let smiles: Set = ["😊", "🙂", "😀", "😄"]
        #expect(Self.bases(search, "smile", catalog).prefix(3).contains { smiles.contains($0) })
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

    @Test func stopwordsAreOptional() throws {
        let (search, catalog) = try Self.bundled()
        // The data's stopwords are in no name, so they exclude nothing: a whole name typed out still finds its emoji.
        #expect(Self.bases(search, "face with tears of joy", catalog).first == "😂")
        #expect(Self.bases(search, "heart on fire", catalog).first == "❤️‍🔥")
        // Nor does a last word that may be a stopword still being typed.
        #expect(Self.bases(search, "face with tears o", catalog).contains("😂"))
        #expect(Self.bases(search, "face wi", catalog).contains("😂"))
        // An emoji that matches one ranks higher: 🇮🇳 has the tag "in".
        #expect(Self.bases(search, "flag in", catalog).prefix(3).contains("🇮🇳"))
        // A query of nothing but stopwords needs them: 🔛 has the tag "on".
        #expect(Self.bases(search, "on", catalog).prefix(3).contains("🔛"))
        #expect(!Self.bases(search, "the", catalog).isEmpty)
    }

    @Test func optionalWordsRankJustAfterTheTier() {
        let search = EmojiSearch(
            keywords: [
                "🅰️": (label: ["cat"], tags: []),
                "🅱️": (label: ["cat"], tags: ["in"]),
                "🆎": (label: ["catalog"], tags: ["in"]),
            ],
            stopwords: ["in"])
        let catalog = Self.catalog(["🅰️", "🅱️", "🆎"])
        // A matched stopword lifts 🅱️ above Recent's 🅰️, but not 🆎 above the better tier.
        #expect(Self.bases(search, "cat in", catalog, recents: ["🅰️"]) == ["🅱️", "🅰️", "🆎"])
        // Alone, a stopword is needed.
        #expect(Self.bases(search, "in", catalog) == ["🅱️", "🆎"])
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

    @Test func exactThenNamePrefixThenTagPrefix() {
        let search = EmojiSearch(keywords: [
            "🅰️": (label: ["catalog"], tags: []),
            "🅱️": (label: ["dog"], tags: ["cats"]),
            "🆎": (label: ["kitten"], tags: ["cat"]),
            "🅾️": (label: ["cat"], tags: []),
            "🆑": (label: ["dog"], tags: []),
        ])
        let catalog = Self.catalog(["🅰️", "🅱️", "🆎", "🅾️", "🆑"])
        // Exact, a name word before a tag; then the beginning of a name word; then the beginning of a tag.
        #expect(Self.bases(search, "cat", catalog) == ["🅾️", "🆎", "🅰️", "🅱️"])
        #expect(Self.bases(search, "CATS", catalog) == ["🅱️"])
        // A repeated word counts once.
        #expect(Self.bases(search, "cat cat", catalog) == Self.bases(search, "cat", catalog))
    }

    @Test func withinATierRecentThenPopularThenShorterThenFewerWordsThenCatalog() {
        let search = EmojiSearch(
            keywords: [
                "🅰️": (label: ["cattle"], tags: []),
                "🅱️": (label: ["catfish"], tags: []),
                "🆎": (label: ["cats", "and", "dogs"], tags: []),
                "🅾️": (label: ["cats"], tags: []),
                "🆑": (label: ["cats", "eyes"], tags: []),
                "🆘": (label: ["catapult"], tags: []),
            ],
            popular: ["🆘", "🅱️"])
        let catalog = Self.catalog(["🅰️", "🅱️", "🆎", "🅾️", "🆑", "🆘"])
        // All begin a name word with "cat". Popular ones lead, in the list's order; then the shorter matched word
        // ("cats" before "cattle"); then fewer name words; then the catalog's order.
        #expect(Self.bases(search, "cat", catalog) == ["🆘", "🅱️", "🅾️", "🆑", "🆎", "🅰️"])
        // Recent leads even the popular ones, most recent first.
        #expect(Self.bases(search, "cat", catalog, recents: ["🅰️", "🆎"]) == ["🅰️", "🆎", "🆘", "🅱️", "🅾️", "🆑"])
        // Equal on every count: the catalog's order.
        let twins = EmojiSearch(keywords: ["🅰️": (label: ["cat"], tags: []), "🅱️": (label: ["cat"], tags: [])])
        #expect(Self.bases(twins, "cat", Self.catalog(["🅱️", "🅰️"])) == ["🅱️", "🅰️"])
        // Both exact: the name match first, though the catalog has the tag match first.
        let exact = EmojiSearch(keywords: ["🅰️": (label: ["dog"], tags: ["cat"]), "🅱️": (label: ["cat"], tags: [])])
        #expect(Self.bases(exact, "cat", Self.catalog(["🅰️", "🅱️"])) == ["🅱️", "🅰️"])
    }

    @Test func aQueryRanksByItsWeakestWord() {
        let search = EmojiSearch(keywords: [
            "🅰️": (label: ["grinning", "cat"], tags: ["face"]),
            "🅱️": (label: ["cat", "face"], tags: []),
        ])
        let catalog = Self.catalog(["🅰️", "🅱️"])
        // "cat" is a name word of both; "fa" begins a name word only in 🅱️, and "face" is one only in 🅱️.
        #expect(Self.bases(search, "cat fa", catalog) == ["🅱️", "🅰️"])
        #expect(Self.bases(search, "face cat", catalog) == ["🅱️", "🅰️"])
    }

    @Test func recentGoesFirstWithinItsTier() throws {
        let (search, catalog) = try Self.bundled()
        // All six have the tag "laugh": popular 😂 🤣 😆 😀 first, then 😹 (three name words) and 😄 (four).
        #expect(Self.bases(search, "laugh", catalog) == ["😂", "🤣", "😆", "😀", "😹", "😄"])
        // Recent ones lead their tier, most recent first; 👍 matches nothing here.
        #expect(Self.bases(search, "laugh", catalog, recents: ["😹", "👍", "😆"]) == ["😹", "😆", "😂", "🤣", "😀", "😄"])
        // But not a better tier: 🤣's name begins "lau", the others' tags do.
        #expect(Self.bases(search, "lau", catalog, recents: ["🧺"]).prefix(3) == ["🤣", "🧺", "😂"])
        // Recent keeps the exact variant typed, with a skin tone or without U+FE0F; it counts for its emoji.
        #expect(Self.bases(search, "thumbs", catalog) == ["👍", "👎"])
        #expect(Self.bases(search, "thumbs", catalog, recents: ["👎🏽"]) == ["👎", "👍"])
        #expect(Self.bases(search, "heart", catalog, recents: ["💔"]).first == "💔")
        #expect(Self.bases(search, "smiling", catalog, recents: ["☺"]).first == "☺️")
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
        #expect(search.results(for: "laugh", catalog: small, recents: []).map(\.base) == ["😂", "😹"])
        #expect(search.results(for: "wave", catalog: small, recents: []).first?.skins.count == 5)
        // A prepared catalog gives the same results.
        let prepared = search.prepared(for: v17)
        #expect(prepared.results(for: "lau", recents: ["🧺"]) == search.results(for: "lau", catalog: v17, recents: ["🧺"]))
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
        // One entry per emoji: skin variants have none of their own and reach their emoji's.
        #expect(search.emojiCount == items.count)
        #expect(search.keywords(for: "👋🏽")?.label == search.keywords(for: "👋")?.label)
        #expect(search.keywords(for: "🦖")?.label == ["rex", "trex"])
        #expect(search.keywords(for: "❤️")?.label == ["red", "heart"])
        // English stopwords never make a name word: "face with tears of joy".
        #expect(search.keywords(for: "😂")?.label == ["face", "tears", "joy"])
    }

    @Test func popularListIsLoadedAndDrawable() throws {
        let (search, _) = try Self.bundled()
        let popular = search.popularEmoji
        #expect(popular.count == 50 && popular.first == "😂" && Set(popular).count == 50)
        // Every one is in the catalog for the oldest supported iOS, in its own spelling.
        let v16 = EmojiIndex(try EmojiCatalog.load(maxVersion: 16.0))
        #expect(popular.allSatisfy { v16.lookup($0)?.variant == $0 })
    }

    @Test func filesMergeByEmoji() throws {
        // A later language file adds words to an emoji, spelled with or without U+FE0F, and a shared file adds the
        // popular list.
        let en = #"{"language":"en","stopwords":["of","to"],"keywords":{"❤️":[["red","heart"],["love"]],"😂":[["face","joy"],["laugh"]],"👅":[["tongue"],[]]}}"#
        let hi = #"{"language":"hi-Latn","keywords":{"❤":[["dil","heart"],["pyaar","love","red"]],"🙏":[["namaste"],[]],"🤷":[["to","kya"],[]]}}"#
        let popular = #"{"popular":["🙏","❤️"]}"#
        let search = try EmojiSearch.merged([en, hi, popular].map { Data($0.utf8) })
        #expect(search.emojiCount == 5)
        let heart = try #require(search.keywords(for: "❤️"))
        #expect(heart.label == ["red", "heart", "dil"] && heart.tags == ["love", "pyaar"])
        #expect(search.popularEmoji == ["🙏", "❤️"])
        let catalog = Self.catalog(["❤️", "😂", "👅", "🙏", "🤷"])
        #expect(Self.bases(search, "dil", catalog) == ["❤️"] && Self.bases(search, "namaste", catalog) == ["🙏"])
        #expect(Self.bases(search, "face of joy", catalog) == ["😂"])
        // English's stopword "to" is a Hinglish word: alone it is needed and finds 🤷 first; after "kya" it only lifts.
        #expect(Self.bases(search, "to", catalog) == ["🤷", "👅"])
        #expect(Self.bases(search, "kya to", catalog) == ["🤷"])
        // A value that isn't two lists is refused.
        #expect(throws: EmojiSearch.LoadError.self) {
            try EmojiSearch.merged([Data(#"{"keywords":{"😂":[["face"]]}}"#.utf8)])
        }
    }
}

/// The keyword data is loaded when search first opens and kept for the keyboard process, like the catalog
/// (ruling M3-R11): loaded once, freed on request, loaded again after that, and never retried after a failure.
@MainActor struct EmojiSearchStoreTests {
    struct Broken: Error {}

    static let sample = EmojiSearch(keywords: ["😂": (label: ["face"], tags: ["laugh"]), "😹": (label: ["cat"], tags: ["laugh"])])

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

    @Test func preparedFollowsTheCatalogAskedFor() throws {
        var loads = 0
        let store = EmojiSearchStore {
            loads += 1
            return Self.sample
        }
        let one = EmojiSearchTests.catalog(["😂"]), both = EmojiSearchTests.catalog(["😹", "😂"])
        #expect(try store.prepared(for: one).results(for: "laugh", recents: []).map(\.base) == ["😂"])
        #expect(try store.prepared(for: one).catalog == one)
        #expect(try store.prepared(for: both).results(for: "laugh", recents: []).map(\.base) == ["😹", "😂"])
        #expect(loads == 1)
        store.release()
        #expect(try store.prepared(for: both).catalog == both && loads == 2)
    }

    @Test func sharedStoreLoadsTheBundledKeywords() throws {
        #expect(try EmojiSearchStore.shared.search().keywords(for: "😂") != nil)
    }
}
