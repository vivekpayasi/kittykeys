import Testing
import KeyboardCore

@Test func loadsAllCategoriesInOrder() throws {
    let data = try EmojiCatalog.load(maxVersion: 17.0)
    #expect(data.categories.map(\.id) == [
        "smileys-people", "animals-nature", "food-drink", "activity",
        "travel-places", "objects", "symbols", "flags",
    ])
    #expect(data.categories.allSatisfy { !$0.items.isEmpty && !$0.name.isEmpty && !$0.icon.isEmpty })
    #expect(data.categories.first?.items.first?.base == "😀")
    #expect(data.categories.first?.name == "Smileys & People")
    #expect(data.categories.first?.icon == "face.smiling")
}

@Test func recentNameComesFromData() throws {
    #expect(try EmojiCatalog.load(maxVersion: 17.0).recentName == "Recent")
}

@Test func recentIconComesFromData() throws {
    #expect(try EmojiCatalog.load(maxVersion: 17.0).recentIcon == "clock")
}

@Test func versionFilterDropsNewer() throws {
    let v16 = try EmojiCatalog.load(maxVersion: 16.0).categories.flatMap(\.items)
    let v17 = try EmojiCatalog.load(maxVersion: 17.0).categories.flatMap(\.items)
    #expect(!v16.isEmpty)
    #expect(v16.allSatisfy { $0.version <= 16.0 })
    #expect(v16.contains { $0.version == 16.0 })
    #expect(v17.count > v16.count)
    #expect(v17.allSatisfy { $0.version <= 17.0 })
}

@Test(arguments: [
    (26, 0, 16.0), (26, 3, 16.0), (26, 4, 17.0), (26, 5, 17.0), (27, 0, 17.0), (28, 2, 17.0),
    (25, 9, 16.0), (18, 4, 16.0),
])
func maxSupportedVersion(_ major: Int, _ minor: Int, _ expected: Double) {
    #expect(EmojiCatalog.maxSupportedVersion(osMajor: major, osMinor: minor) == expected)
}

@Test func skinsAreFiveOrNone() throws {
    let items = try EmojiCatalog.load(maxVersion: 17.0).categories.flatMap(\.items)
    #expect(items.allSatisfy { $0.skins.isEmpty || $0.skins.count == 5 })
    let wave = try #require(items.first { $0.base == "👋" })
    #expect(wave.version == 0.6)
    #expect(wave.skins == ["👋🏻", "👋🏼", "👋🏽", "👋🏾", "👋🏿"])
    #expect(items.first { $0.base == "😀" }?.skins == [])
}

@Test func indexFindsTheItemForAnyVariant() throws {
    let index = EmojiIndex(try EmojiCatalog.load(maxVersion: 17.0))
    let wave = try #require(index.lookup("👋🏽"))
    #expect(wave.item.base == "👋" && wave.variant == "👋🏽")
    #expect(index.lookup("👋")?.variant == "👋")
    // Recent may hold a spelling without U+FE0F; the catalog's own spelling is shown.
    let smile = try #require(index.lookup("☺"))
    #expect(smile.item.base == "☺️" && smile.variant == "☺️")
    #expect(index.lookup("☝🏾")?.item.base == "☝️")
    #expect(index.lookup("🇮🇳")?.variant == "🇮🇳")
    #expect(index.lookup("👨‍👩‍👧")?.item.skins == [])
    #expect(index.lookup("x") == nil)
    #expect(index.lookup("") == nil)
    // A skin spelling the item lacks still finds the item, shown as its base.
    #expect(index.lookup("😀🏽")?.variant == "😀")
}

@Test func indexLeavesOutEmojiNewerThanTheCatalog() throws {
    let v16 = EmojiIndex(try EmojiCatalog.load(maxVersion: 16.0))
    let v17 = try EmojiCatalog.load(maxVersion: 17.0)
    let newer = try #require(v17.categories.flatMap(\.items).first { $0.version > 16.0 })
    #expect(v16.lookup(newer.base) == nil)
}
