import Foundation

/// The loaded search keywords, kept for the whole keyboard process as the catalog is (ruling M3-R11). They load the first
/// time search opens, not before (ruling M3-R15), and the keyboard frees them on a memory warning while search is closed;
/// the next search loads them again.
@MainActor public final class EmojiSearchStore {
    /// The bundled keywords.
    public static let shared = EmojiSearchStore { try EmojiSearch.load() }

    private let loader: () throws -> EmojiSearch
    private var loaded: EmojiSearch?
    /// The first load's error. A broken data file stays broken for the process, so it is never read again.
    private var failure: (any Error)?

    /// A store that loads with `loader` when first asked.
    public init(loader: @escaping () throws -> EmojiSearch) {
        self.loader = loader
    }

    /// Whether the keywords are held now.
    public var isLoaded: Bool {
        loaded != nil
    }

    /// The search, loaded on first use and kept. Throws the load's error, then the same error on every later call.
    public func search() throws -> EmojiSearch {
        if let loaded { return loaded }
        if let failure { throw failure }
        do {
            let search = try loader()
            loaded = search
            return search
        } catch {
            failure = error
            throw error
        }
    }

    /// Lets go of the keywords. A search view still holding them keeps them until it goes.
    public func release() {
        loaded = nil
    }
}
