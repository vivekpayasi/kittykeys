// UIKit only, so that `swift test` still builds the package on macOS.
#if canImport(UIKit)
import CoreText
import KeyboardCore
import OSLog
import UIKit

/// Gets the emoji panel's first open ready ahead of time (ruling M3-R12). The keys never draw an emoji, so otherwise the
/// first open in a keyboard process pays on the main thread for loading the emoji font, drawing each of its first
/// screen's glyphs for the first time, and looking up its tab icons: about 150 ms on the simulator.
///
/// A moment after the keys are first drawn, once per keyboard process:
/// 1. **Off the main thread**, at utility priority, with Core Text and Core Graphics only: the emoji the panel shows
///    first (Recent, then the first category's first rows) are drawn one by one into a small offscreen bitmap, at the
///    cells' font and size. The emoji data is decoded there only to learn that category's emoji and the tab icons, and
///    dropped again; the panel still decodes it when it first opens.
/// 2. **On the main thread**, one per turn of the run loop so typing never waits: each tab icon is rendered once and
///    thrown away, which loads its symbol.
///
/// After a memory warning, the next keyboard appearance does it again.
enum EmojiFontWarmup {
    private static let logger = Logger(subsystem: "catkeys", category: "emoji")
    /// How long after the keys' first draw the warm-up starts, so it never competes with that frame.
    private static let delay = 0.3
    /// Drawn when the emoji data can't be read: it still loads the font.
    private static let fallbackSample = "😀"
    /// How many of the first category's emoji to draw: more rows than the panel shows at once.
    private static let firstCategoryCount = 64

    @MainActor private static var isWarm = false
    @MainActor private static var isScheduled = false
    /// Bumped by a memory warning, so a warm-up scheduled before it stops.
    @MainActor private static var generation = 0

    /// Warms up unless this process already has, or a warm-up is under way. `scale` is the screen's, so the glyphs are
    /// drawn at the size the cells draw them. `recent` gives Recent's emoji, which the panel shows first; it is read on
    /// the main thread when the warm-up starts.
    @MainActor static func scheduleIfNeeded(scale: CGFloat, recent: @escaping @MainActor @Sendable () -> [String]) {
        guard !isWarm, !isScheduled else { return }
        isScheduled = true
        let scheduledGeneration = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            MainActor.assumeIsolated {
                guard scheduledGeneration == generation else { return finish(scheduledGeneration) }
                let recent = recent()
                DispatchQueue.global(qos: .utility).async {
                    let start = DispatchTime.now().uptimeNanoseconds
                    let (count, icons) = drawFirstScreen(scale: scale, recent: recent)
                    let milliseconds = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
                    logger.notice(
                        "Warmed \(count) emoji off the main thread in \(milliseconds, format: .fixed(precision: 1)) ms")
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated {
                            loadIcons(icons[...], scale: scale, generation: scheduledGeneration)
                        }
                    }
                }
            }
        }
    }

    /// A memory warning may have purged the caches: the next keyboard appearance warms up again, and a warm-up under
    /// way stops at its next step.
    @MainActor static func forget() {
        isWarm = false
        generation += 1
    }

    /// Renders the first of `icons` as the tab bar does, then comes back on the next turn of the run loop for the rest.
    @MainActor private static func loadIcons(_ icons: ArraySlice<String>, scale: CGFloat, generation: Int) {
        guard generation == self.generation, let name = icons.first else { return finish(generation) }
        _ = KeyIconCache().image(named: name, fontSize: EmojiTabBar.iconFontSize, color: .gray, scale: scale)
        DispatchQueue.main.async {
            MainActor.assumeIsolated { loadIcons(icons.dropFirst(), scale: scale, generation: generation) }
        }
    }

    @MainActor private static func finish(_ generation: Int) {
        isScheduled = false
        if generation == self.generation { isWarm = true }
    }

    /// Draws Recent and the first category's first emoji, each in turn over the last, in the system font at the cells'
    /// size, letting Core Text fall back to the emoji font as the cells' labels do. Returns how many it drew, and the tab
    /// icons' names from the emoji data.
    private static func drawFirstScreen(scale: CGFloat, recent: [String]) -> (count: Int, icons: [String]) {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let maxVersion = EmojiCatalog.maxSupportedVersion(osMajor: os.majorVersion, osMinor: os.minorVersion)
        let data = try? EmojiCatalog.load(maxVersion: maxVersion)
        let icons = data.map { [$0.recentIcon] + $0.categories.map(\.icon) } ?? []
        var sample = recent + (data?.categories.first?.items.prefix(firstCategoryCount).map(\.base) ?? [])
        if sample.isEmpty { sample = [fallbackSample] }

        let size = EmojiCell.fontSize, scale = max(scale, 1)
        let side = Int((size * 1.5 * scale).rounded(.up))
        guard let context = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return (0, icons) }
        context.scaleBy(x: scale, y: scale)
        var attributes: [NSAttributedString.Key: Any] = [:]
        if let font = CTFontCreateUIFontForLanguage(.system, size, nil) {
            attributes[NSAttributedString.Key(kCTFontAttributeName as String)] = font
        }
        // Each one inside the bitmap, so none is skipped as out of sight.
        for emoji in sample {
            context.textPosition = CGPoint(x: 0, y: size * 0.3)
            CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: emoji, attributes: attributes)), context)
        }
        return (sample.count, icons)
    }
}
#endif
