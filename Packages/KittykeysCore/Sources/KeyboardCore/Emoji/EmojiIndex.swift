/// Finds the catalog's emoji for any spelling of it. Recent keeps the exact variant typed, such as "👋🏽", and the panel
/// needs that emoji's catalog item to offer its skin tones. Built once per catalog load.
public struct EmojiIndex: Sendable {
    /// Every item, keyed by `EmojiPreferences.key(base)`. The first item wins should two share a key.
    private let items: [String: EmojiItem]

    public init(_ data: EmojiData) {
        var items: [String: EmojiItem] = [:]
        for category in data.categories {
            for item in category.items {
                let key = EmojiPreferences.key(item.base)
                if items[key] == nil { items[key] = item }
            }
        }
        self.items = items
    }

    /// The catalog item `emoji` is a spelling of, matched without U+FE0F and skin tones, and the catalog's own spelling
    /// of that variant: the matching skin, else the base. nil when the catalog has no such emoji, as for one newer than
    /// the catalog's version filter allows.
    public func lookup(_ emoji: String) -> (item: EmojiItem, variant: String)? {
        guard !emoji.isEmpty, let item = items[EmojiPreferences.key(emoji)] else { return nil }
        let wanted = EmojiPreferences.withoutVariationSelector(emoji)
        let variant = item.skins.first { EmojiPreferences.withoutVariationSelector($0) == wanted } ?? item.base
        return (item, variant)
    }
}
