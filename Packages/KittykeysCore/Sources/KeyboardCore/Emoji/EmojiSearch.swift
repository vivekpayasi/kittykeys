import Foundation

/// Finds emoji by the words of their names and tags, for the emoji panel's search (rulings M3-R15, M3-R17).
///
/// - **Data:** every `.json` file in the bundled `EmojiKeywords` folder, read in name order and merged. A file may hold
///   `keywords`, `{"<emoji>": [[name words], [tag words]]}`; `popular`, emoji most used first; and `stopwords`, its
///   language's words that no name holds. An emoji's words from every file are put together, matched without U+FE0F
///   or skin tones, and the popular and stopword lists are joined. `scripts/make-emoji-data.py` writes `en.json` from
///   Emojibase and `popular.json`; another language's words need only another file there. Joining the stopword lists is
///   safe because a stopword only ever lifts an emoji: English's "to" can be a Hinglish word and still find it.
/// - **Words:** the query is lowercased and split into words at every character that isn't a letter or a digit, as the
///   keywords were; a repeated word counts once. Every word must begin one of an emoji's keywords, except optional
///   ones: stopwords, and a last word still being typed that begins one ("face wi"). Those exclude nothing, so a whole
///   name typed out ("face with tears of joy") still matches, but an emoji that matches them ranks higher. A query of
///   nothing but optional words needs them all.
/// - **Ranking:** a needed word matches an emoji exactly (a name word or a tag is the word), by the beginning of a name
///   word, or by the beginning of a tag, best first, and an emoji ranks by its weakest needed word. Within each of
///   those: more optional words matched; Recent, most recent first; the popular list, in its order; fewer needed words
///   matched by a tag than by a name word; shorter matched keywords; fewer name words; the catalog's order.
/// - **Speed:** it runs on every keystroke. The keywords sit in one byte buffer, compared as UTF-8 with no per-keyword
///   strings, and `Prepared` ties a catalog's emoji to their keywords once, so a query looks nothing up per emoji.
///
/// Nothing is cached here: `EmojiSearchStore` holds it, and its `Prepared` form, for the keyboard process.
public struct EmojiSearch: Sendable {
    public enum LoadError: Error {
        /// The bundle has no keyword files.
        case missingFiles(String)
        /// An emoji whose value isn't a list of name words and a list of tag words.
        case malformed(String)
    }

    /// One emoji's keywords: those numbered `first..<end`, its name's words before `labelEnd`.
    private struct Entry: Sendable {
        var first: Int32, labelEnd: Int32, end: Int32
    }

    /// One emoji's words, as merged from the files.
    private struct Words {
        var base: String
        var label: [String]
        var tags: [String]

        /// Adds another file's words for the same emoji, each once, and none as both a name word and a tag.
        mutating func add(label more: [String], tags moreTags: [String]) {
            var seen = Set(label)
            label += more.filter { seen.insert($0).inserted }
            let names = seen
            tags.removeAll { names.contains($0) }
            seen.formUnion(tags)
            tags += moreTags.filter { seen.insert($0).inserted }
        }
    }

    /// How one query word matches an emoji's best keyword: `tier` 0 to 2 is exactly, the beginning of a name word and
    /// the beginning of a tag; `isTag` says whether the keyword is a tag, and `length` is its length in UTF-8 bytes.
    private struct WordMatch {
        var tier: UInt8
        var isTag: Bool
        var length: Int

        /// Whether this is a better match than `other`: a better tier, a name word over a tag, then a shorter keyword.
        func isBetter(than other: WordMatch) -> Bool {
            (tier, isTag ? 1 : 0, length) < (other.tier, other.isTag ? 1 : 0, other.length)
        }
    }

    /// How an emoji matches the whole query.
    private struct QueryMatch {
        /// Its weakest needed word's tier.
        var tier: UInt8 = 0
        /// How many optional words it matches, and how many needed words only a tag matches.
        var optionalWords = 0, tagWords = 0
        /// The matched keywords' total length.
        var length = 0
    }

    /// A query word, and whether it is optional: it then excludes nothing but ranks the emoji it matches higher.
    private struct QueryWord {
        var bytes: [UInt8]
        var isOptional: Bool
    }

    /// Every keyword's UTF-8, one after another. Keyword k is `bytes[keywordStarts[k]..<keywordStarts[k + 1]]`.
    private let bytes: [UInt8]
    private let keywordStarts: [Int32]
    private let entries: [Entry]
    /// Each entry's emoji, as the data first spells it.
    private let bases: [String]
    /// Each entry's place in the popular list, `Int32.max` when it isn't there.
    private let popularity: [Int32]
    /// Each entry by `EmojiPreferences.key` of its emoji, so any spelling finds it: a skin tone, or U+FE0F or not.
    private let indexByKey: [String: Int32]
    /// Stopwords and every beginning of one, as UTF-8.
    private let stopwords: Set<[UInt8]>, stopwordBeginnings: Set<[UInt8]>

    private init(words list: [Words], popular: [String], stopwords: [String]) {
        var bytes: [UInt8] = []
        var keywordStarts: [Int32] = [0]
        var entries: [Entry] = []
        var bases: [String] = []
        var indexByKey: [String: Int32] = [:]
        entries.reserveCapacity(list.count)
        bases.reserveCapacity(list.count)
        indexByKey.reserveCapacity(list.count)
        for words in list {
            let key = EmojiPreferences.key(words.base)
            guard indexByKey[key] == nil else { continue }
            let first = Int32(keywordStarts.count - 1)
            for word in words.label + words.tags {
                bytes.append(contentsOf: word.utf8)
                keywordStarts.append(Int32(bytes.count))
            }
            let end = Int32(keywordStarts.count - 1)
            indexByKey[key] = Int32(entries.count)
            entries.append(Entry(first: first, labelEnd: first + Int32(words.label.count), end: end))
            bases.append(words.base)
        }
        var popularity = [Int32](repeating: .max, count: entries.count)
        for (rank, emoji) in popular.enumerated() {
            guard let index = indexByKey[EmojiPreferences.key(emoji)], popularity[Int(index)] == .max else { continue }
            popularity[Int(index)] = Int32(rank)
        }
        self.bytes = bytes
        self.keywordStarts = keywordStarts
        self.entries = entries
        self.bases = bases
        self.popularity = popularity
        self.indexByKey = indexByKey
        let stopwordBytes = stopwords.map { Array($0.utf8) }
        self.stopwords = Set(stopwordBytes)
        stopwordBeginnings = Set(stopwordBytes.flatMap { word in word.indices.map { Array(word[...$0]) } })
    }

    /// A search over `keywords`, keyed by emoji, each with its name's words and its tags' other words, lowercase;
    /// `popular` is most used first.
    init(keywords: [String: (label: [String], tags: [String])], popular: [String] = [], stopwords: [String] = []) {
        let list = keywords.sorted { $0.key < $1.key }.map { Words(base: $0.key, label: $0.value.label, tags: $0.value.tags) }
        self.init(words: list, popular: popular, stopwords: stopwords)
    }

    private struct File: Decodable {
        var keywords: [String: [[String]]]?
        var popular: [String]?
        var stopwords: [String]?
    }

    /// Reads and merges every file in the bundled `EmojiKeywords` folder. The caller holds the result.
    public static func load() throws -> EmojiSearch {
        let urls = Bundle.module.urls(forResourcesWithExtension: "json", subdirectory: "EmojiKeywords") ?? []
        guard !urls.isEmpty else { throw LoadError.missingFiles("EmojiKeywords/*.json") }
        let ordered = urls.sorted { $0.lastPathComponent < $1.lastPathComponent }
        return try merged(ordered.map { try Data(contentsOf: $0) })
    }

    /// The search over keyword files' contents, merged in the order given.
    static func merged(_ files: [Data]) throws -> EmojiSearch {
        let decoder = JSONDecoder()
        var list: [Words] = []
        var indexByKey: [String: Int] = [:]
        var popular: [String] = []
        var stopwords: [String] = []
        for data in files {
            let file = try decoder.decode(File.self, from: data)
            popular += file.popular ?? []
            stopwords += file.stopwords ?? []
            for (base, lists) in file.keywords ?? [:] {
                guard lists.count == 2 else { throw LoadError.malformed(base) }
                let key = EmojiPreferences.key(base)
                if let index = indexByKey[key] {
                    list[index].add(label: lists[0], tags: lists[1])
                } else {
                    indexByKey[key] = list.count
                    list.append(Words(base: base, label: lists[0], tags: lists[1]))
                }
            }
        }
        return EmojiSearch(words: list, popular: popular, stopwords: stopwords)
    }

    // MARK: Searching

    /// The search tied to one catalog: the catalog's emoji in its order, each matched to its keywords once, so a query
    /// looks nothing up per emoji. Make one per catalog and query it on every keystroke;
    /// `EmojiSearchStore.prepared(for:)` keeps one.
    public struct Prepared: Sendable {
        /// The catalog it was made for.
        public let catalog: EmojiData
        fileprivate let search: EmojiSearch
        /// The catalog's emoji in its order, and the entry holding each one's keywords, or -1 when none does.
        fileprivate let items: [EmojiItem]
        fileprivate let entries: [Int32]

        /// The catalog's emoji that match `query`, best first, at most `limit` of them; none for a query with no
        /// words. `recents` are Recent's emoji, most recent first, in any spelling. Only the catalog's emoji come back,
        /// so emoji newer than the iOS version running never do.
        public func results(for query: String, recents: [String], limit: Int = 60) -> [EmojiItem] {
            search.results(for: query, items: items, entries: entries, recents: recents, limit: limit)
        }
    }

    /// This search tied to `catalog`.
    public func prepared(for catalog: EmojiData) -> Prepared {
        let count = catalog.categories.reduce(0) { $0 + $1.items.count }
        var items: [EmojiItem] = []
        var itemEntries: [Int32] = []
        items.reserveCapacity(count)
        itemEntries.reserveCapacity(count)
        for category in catalog.categories {
            for item in category.items {
                items.append(item)
                itemEntries.append(indexByKey[EmojiPreferences.key(item.base)] ?? -1)
            }
        }
        return Prepared(catalog: catalog, search: self, items: items, entries: itemEntries)
    }

    /// As `prepared(for: catalog).results(...)`, preparing the catalog on every call.
    public func results(for query: String, catalog: EmojiData, recents: [String], limit: Int = 60) -> [EmojiItem] {
        prepared(for: catalog).results(for: query, recents: recents, limit: limit)
    }

    /// One emoji that matches, with what ranks it.
    private struct Found {
        var match: QueryMatch
        var recent: Int, popular: Int32, nameWords: Int32
        /// Its place in the catalog.
        var position: Int

        /// Whether this ranks before `other`, as the ranking in `EmojiSearch`'s description says.
        func precedes(_ other: Found) -> Bool {
            let a = match, b = other.match
            if a.tier != b.tier { return a.tier < b.tier }
            if a.optionalWords != b.optionalWords { return a.optionalWords > b.optionalWords }
            return (recent, popular, a.tagWords, a.length, nameWords, position)
                < (other.recent, other.popular, b.tagWords, b.length, other.nameWords, other.position)
        }
    }

    private func results(
        for query: String, items: [EmojiItem], entries itemEntries: [Int32], recents: [String], limit: Int
    ) -> [EmojiItem] {
        let words = words(in: query)
        guard !words.isEmpty, limit > 0 else { return [] }
        var recentRanks: [Int32: Int] = [:]
        for (rank, emoji) in recents.enumerated() {
            if let index = indexByKey[EmojiPreferences.key(emoji)], recentRanks[index] == nil { recentRanks[index] = rank }
        }
        var found: [Found] = []
        bytes.withUnsafeBufferPointer { bytes in
            keywordStarts.withUnsafeBufferPointer { starts in
                for (position, index) in itemEntries.enumerated() where index >= 0 {
                    let entry = entries[Int(index)]
                    guard let match = Self.match(words, entry, bytes: bytes, starts: starts) else { continue }
                    found.append(Found(
                        match: match, recent: recentRanks.isEmpty ? .max : recentRanks[index] ?? .max,
                        popular: popularity[Int(index)], nameWords: entry.labelEnd - entry.first, position: position))
                }
            }
        }
        found.sort { $0.precedes($1) }
        return found.prefix(limit).map { items[$0.position] }
    }

    // MARK: Matching

    /// The query's distinct words as UTF-8: lowercased, NFC like the keywords, split at every character that isn't a
    /// letter or a digit (so "t-rex" is "t" and "rex", and "heart," is "heart"). Stopwords are optional, and so is the
    /// last word while it is still being typed (the query ends in it) and begins a stopword; unless every word is.
    private func words(in query: String) -> [QueryWord] {
        let split = query.lowercased().precomposedStringWithCanonicalMapping
            .split { !($0.isLetter || $0.isNumber) }
            .map { Array($0.utf8) }
        let typingLast = query.last.map { $0.isLetter || $0.isNumber } ?? false
        var seen: Set<[UInt8]> = []
        var words: [QueryWord] = []
        for (index, word) in split.enumerated() where seen.insert(word).inserted {
            let isTyping = typingLast && index == split.count - 1
            words.append(QueryWord(
                bytes: word, isOptional: stopwords.contains(word) || (isTyping && stopwordBeginnings.contains(word))))
        }
        if words.allSatisfy(\.isOptional) {
            for index in words.indices { words[index].isOptional = false }
        }
        return words
    }

    /// How `entry` matches the query: nil when a needed word matches none of its keywords.
    private static func match(
        _ words: [QueryWord], _ entry: Entry, bytes: UnsafeBufferPointer<UInt8>, starts: UnsafeBufferPointer<Int32>
    ) -> QueryMatch? {
        var total = QueryMatch()
        for word in words {
            let match = word.bytes.withUnsafeBufferPointer { Self.match($0, entry, bytes: bytes, starts: starts) }
            guard let match else {
                if word.isOptional { continue }
                return nil
            }
            total.length += match.length
            if word.isOptional {
                total.optionalWords += 1
            } else {
                total.tier = max(total.tier, match.tier)
                if match.isTag { total.tagWords += 1 }
            }
        }
        return total
    }

    /// How `word` matches `entry`: its best keyword.
    private static func match(
        _ word: UnsafeBufferPointer<UInt8>, _ entry: Entry, bytes: UnsafeBufferPointer<UInt8>,
        starts: UnsafeBufferPointer<Int32>
    ) -> WordMatch? {
        var best: WordMatch?
        for k in Int(entry.first)..<Int(entry.end) {
            let start = Int(starts[k]), length = Int(starts[k + 1]) - start
            guard length >= word.count, hasPrefix(word, in: bytes, at: start) else { continue }
            let isTag = k >= Int(entry.labelEnd), isExact = length == word.count
            let match = WordMatch(tier: isExact ? 0 : isTag ? 2 : 1, isTag: isTag, length: length)
            // An exact name word can't be beaten.
            if isExact && !isTag { return match }
            if let best, !match.isBetter(than: best) { continue }
            best = match
        }
        return best
    }

    /// Whether `bytes` from `start` begin with `prefix`. The caller checks that enough bytes follow.
    private static func hasPrefix(
        _ prefix: UnsafeBufferPointer<UInt8>, in bytes: UnsafeBufferPointer<UInt8>, at start: Int
    ) -> Bool {
        guard let base = bytes.baseAddress, let prefixBase = prefix.baseAddress else { return prefix.isEmpty }
        return memcmp(base + start, prefixBase, prefix.count) == 0
    }

    // MARK: For tests

    /// How many emoji have keywords.
    var emojiCount: Int {
        entries.count
    }

    /// The keywords of `emoji`, in any spelling; nil when it has none.
    func keywords(for emoji: String) -> (label: [String], tags: [String])? {
        guard let index = indexByKey[EmojiPreferences.key(emoji)] else { return nil }
        let entry = entries[Int(index)]
        let word = { (k: Int32) in
            String(decoding: bytes[Int(keywordStarts[Int(k)])..<Int(keywordStarts[Int(k) + 1])], as: UTF8.self)
        }
        return ((entry.first..<entry.labelEnd).map(word), (entry.labelEnd..<entry.end).map(word))
    }

    /// The popular emoji that have keywords, most used first, as the data spells them.
    var popularEmoji: [String] {
        entries.indices.filter { popularity[$0] != .max }.sorted { popularity[$0] < popularity[$1] }.map { bases[$0] }
    }
}
