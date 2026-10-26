import Foundation

/// The decoded emoji data and its index, kept for the whole keyboard process (ruling M3-R11). iOS makes a new keyboard
/// view each time the keyboard appears, so the panel takes the catalog from here rather than decoding it on every first
/// open. The keyboard frees it on a memory warning while the panel is closed; the next open decodes it again.
@MainActor public final class EmojiCatalogStore {
    /// The decoded data and an index over it.
    public struct Catalog: Sendable {
        public let data: EmojiData
        public let index: EmojiIndex
    }

    /// The bundled emoji, filtered for the iOS version running.
    public static let shared = EmojiCatalogStore {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return try EmojiCatalog.load(
            maxVersion: EmojiCatalog.maxSupportedVersion(osMajor: os.majorVersion, osMinor: os.minorVersion))
    }

    private let loader: () throws -> EmojiData
    private var loaded: Catalog?
    /// The first load's error. A broken data file stays broken for the process, so it is never decoded again.
    private var failure: (any Error)?

    /// A store that decodes with `loader` when first asked.
    public init(loader: @escaping () throws -> EmojiData) {
        self.loader = loader
    }

    /// Whether the decoded catalog is held now.
    public var isLoaded: Bool {
        loaded != nil
    }

    /// The catalog, decoded on first use and kept. Throws the load's error, then the same error on every later call.
    public func catalog() throws -> Catalog {
        if let loaded { return loaded }
        if let failure { throw failure }
        do {
            let data = try loader()
            let catalog = Catalog(data: data, index: EmojiIndex(data))
            loaded = catalog
            return catalog
        } catch {
            failure = error
            throw error
        }
    }

    /// Lets go of the decoded catalog. A panel still holding it keeps it until that panel goes.
    public func release() {
        loaded = nil
    }
}
