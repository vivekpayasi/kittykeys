import Foundation

/// The Recent emoji and the skin tone last picked for each emoji, in a `UserDefaults`. In the keyboard it
/// sits on the extension's own `.standard` defaults, so it needs no Full Access.
/// Never traps: missing or corrupt values read as empty, and entries that aren't strings are dropped.
///
/// Emoji are matched by a key with U+FE0F and the skin-tone modifiers removed, so "☺️" and "☺" are one
/// emoji, and so are "👋" and "👋🏽".
public final class EmojiPreferences {
    private static let recentsKey = "catkeys.emoji.recents"
    private static let skinsKey = "catkeys.emoji.skins"
    private static let maxRecents = 32

    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// The exact variants last inserted, most recent first: at most 32, one per base emoji.
    public var recents: [String] {
        let stored = (defaults.array(forKey: Self.recentsKey) ?? []).compactMap { $0 as? String }
        return Self.cleaned(stored)
    }

    /// Puts `emoji`, the exact variant inserted, at the front of Recent, replacing any earlier variant of
    /// the same base emoji.
    public func recordUse(_ emoji: String, base: String) {
        guard !emoji.isEmpty else { return }
        let key = Self.key(base.isEmpty ? emoji : base)
        let rest = recents.filter { Self.key($0) != key }
        defaults.set(Self.cleaned([emoji] + rest), forKey: Self.recentsKey)
    }

    /// The skin tone last picked for `item`, or its base. A stored choice that isn't one of the item's
    /// variants is ignored.
    public func preferredVariant(for item: EmojiItem) -> String {
        skinChoices.preferredVariant(for: item)
    }

    /// Remembers `variant` as the skin tone for `base`. Picking the base itself forgets the choice.
    public func setPreferredVariant(_ variant: String, for base: String) {
        var choices = skinChoices
        choices.setPreferredVariant(variant, for: base)
        defaults.set(choices.variants, forKey: Self.skinsKey)
    }

    /// Every stored skin choice, read once. `preferredVariant(for:)` reads the defaults on each call, so the panel
    /// reads this instead before showing many emoji, and keeps it up to date as the user picks.
    public var skinChoices: EmojiSkinChoices {
        var variants: [String: String] = [:]
        for case let (base, variant as String) in defaults.dictionary(forKey: Self.skinsKey) ?? [:] {
            variants[Self.key(base)] = variant
        }
        return EmojiSkinChoices(variants: variants)
    }

    /// Drops empty strings and later variants of the same base, and keeps the first 32.
    private static func cleaned(_ list: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for emoji in list where !emoji.isEmpty && seen.insert(key(emoji)).inserted {
            result.append(emoji)
            if result.count == maxRecents { break }
        }
        return result
    }

    /// The base emoji a string stands for: U+FE0F and the skin-tone modifiers (U+1F3FB to U+1F3FF) removed.
    static func key(_ emoji: String) -> String {
        let key = removingScalars(from: emoji) { $0.value == 0xFE0F || (0x1F3FB...0x1F3FF).contains($0.value) }
        return key.isEmpty ? emoji : key
    }

    static func withoutVariationSelector(_ emoji: String) -> String {
        removingScalars(from: emoji) { $0.value == 0xFE0F }
    }

    private static func removingScalars(from emoji: String, where remove: (Unicode.Scalar) -> Bool) -> String {
        String(String.UnicodeScalarView(emoji.unicodeScalars.filter { !remove($0) }))
    }
}

/// The skin tones picked so far, as `EmojiPreferences.skinChoices` read them: a value, so reading it never touches the
/// defaults, and changing it changes only this copy. It follows the same rules as `EmojiPreferences`.
public struct EmojiSkinChoices: Equatable, Sendable {
    /// The picked variant of each emoji, keyed by `EmojiPreferences.key(base)`.
    fileprivate var variants: [String: String]

    /// No choices: every emoji shows its base.
    public init() {
        variants = [:]
    }

    fileprivate init(variants: [String: String]) {
        self.variants = variants
    }

    /// The skin tone picked for `item`, or its base. A choice that isn't one of the item's variants is ignored.
    public func preferredVariant(for item: EmojiItem) -> String {
        guard !item.skins.isEmpty, let stored = variants[EmojiPreferences.key(item.base)] else { return item.base }
        let wanted = EmojiPreferences.withoutVariationSelector(stored)
        return item.skins.first { EmojiPreferences.withoutVariationSelector($0) == wanted } ?? item.base
    }

    /// Picks `variant` for `base`. Picking the base itself forgets the choice.
    public mutating func setPreferredVariant(_ variant: String, for base: String) {
        let key = EmojiPreferences.key(base)
        guard !key.isEmpty else { return }
        if EmojiPreferences.withoutVariationSelector(variant) == EmojiPreferences.withoutVariationSelector(base) {
            variants[key] = nil
        } else {
            variants[key] = variant
        }
    }
}
