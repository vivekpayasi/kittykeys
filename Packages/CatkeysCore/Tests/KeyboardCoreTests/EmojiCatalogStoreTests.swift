import Testing
import KeyboardCore

/// The decoded catalog is kept for the whole keyboard process (ruling M3-R11): decoded once, freed on request,
/// decoded again after that, and never retried after a failure.
@MainActor struct EmojiCatalogStoreTests {
    struct Broken: Error {}

    static let sample = EmojiData(
        recentName: "Recent", recentIcon: "clock", searchPlaceholder: "Search", searchIcon: "s", searchClearIcon: "x",
        categories: [EmojiCategory(id: "c", name: "C", icon: "i", items: [EmojiItem(base: "👋", version: 0.6, skins: [])])])

    @Test func decodesOnceAndReuses() throws {
        var loads = 0
        let store = EmojiCatalogStore {
            loads += 1
            return Self.sample
        }
        #expect(!store.isLoaded)
        #expect(loads == 0)
        let first = try store.catalog()
        #expect(first.data == Self.sample)
        #expect(first.index.lookup("👋")?.item.base == "👋")
        #expect(store.isLoaded)
        _ = try store.catalog()
        _ = try store.catalog()
        #expect(loads == 1)
    }

    @Test func releaseFreesAndTheNextUseDecodesAgain() throws {
        var loads = 0
        let store = EmojiCatalogStore {
            loads += 1
            return Self.sample
        }
        _ = try store.catalog()
        store.release()
        #expect(!store.isLoaded)
        #expect(loads == 1)
        _ = try store.catalog()
        #expect(store.isLoaded)
        #expect(loads == 2)
    }

    /// A broken data file stays broken for the process, so it isn't decoded again on every open.
    @Test func failureIsKeptAndNotRetried() {
        var loads = 0
        let store = EmojiCatalogStore {
            loads += 1
            throw Broken()
        }
        #expect(throws: Broken.self) { try store.catalog() }
        #expect(throws: Broken.self) { try store.catalog() }
        store.release()
        #expect(throws: Broken.self) { try store.catalog() }
        #expect(loads == 1)
        #expect(!store.isLoaded)
    }

    @Test func sharedStoreLoadsTheBundledData() throws {
        let catalog = try EmojiCatalogStore.shared.catalog()
        #expect(catalog.data.recentIcon == "clock")
        #expect(!catalog.data.categories.isEmpty)
    }
}
