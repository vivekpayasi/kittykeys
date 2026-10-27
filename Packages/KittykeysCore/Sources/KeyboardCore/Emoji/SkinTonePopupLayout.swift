/// Where the emoji panel's skin-tone popup puts its options: one row of equal cells, the base option and then its skins,
/// laid out like a key's long-press options (ruling R13).
///
/// The anchor, the option the held cell shows (ruling M3-R10), is centred under the finger. The options run in order
/// when that fits between `minX` and `maxX`; otherwise mirrored, right to left, when that fits. A row that fits neither
/// way goes the way that needs less shifting, and is shifted inside. With a width from
/// `cellWidth(count:available:preferred:)` an anchor at either end (the base, or the last skin) always stays under the
/// finger; a middle anchor can be pushed away from the finger near an edge, so `SkinTonePick` keeps it picked until the
/// finger moves. Distances are in points.
public struct SkinTonePopupLayout: Equatable, Sendable {
    /// How many options there are: the base and its skins.
    public let count: Int
    /// The option placed under the finger, an index into the options (0 is the base).
    public let anchor: Int
    public let cellWidth: Double
    /// Where the leftmost cell starts.
    public let originX: Double
    /// Whether the options run right to left, with the base in the rightmost cell.
    public let isMirrored: Bool

    /// The widest cell, at most `preferred`, that keeps an end anchor under the finger wherever the finger is in
    /// `available` points. Shifting a row that fits neither way moves it less than half a cell when
    /// `(2 * count - 2) * width < available`. 0 when nothing fits.
    public static func cellWidth(count: Int, available: Double, preferred: Double) -> Double {
        guard available.isFinite, available > 0, preferred.isFinite, preferred > 0 else { return 0 }
        let limit = count > 1 ? available / Double(2 * count - 2) : available
        // Half a point under the limit, so the finger is never exactly on the anchor cell's edge.
        return max(0, min(preferred, (limit - 0.5).rounded(.down)))
    }

    /// `count` options in `cellWidth` cells, option `anchor` centred on `fingerX`, inside `minX...maxX` where they fit.
    /// An anchor out of range is taken as the nearest end. Unusable numbers never trap: they give a row from `minX`
    /// whose every point picks the anchor.
    public init(count: Int, anchor: Int, cellWidth: Double, fingerX: Double, minX: Double, maxX: Double) {
        self.count = max(count, 1)
        self.anchor = min(max(anchor, 0), self.count - 1)
        self.cellWidth = cellWidth
        let minX = minX.isFinite ? minX : 0
        let maxX = maxX.isFinite ? max(maxX, minX) : minX
        guard cellWidth > 0, cellWidth.isFinite, fingerX.isFinite else {
            originX = minX
            isMirrored = false
            return
        }
        let total = Double(self.count) * cellWidth
        func overflow(_ start: Double) -> Double {
            max(0, minX - start) + max(0, start + total - maxX)
        }
        // The row's left edge when the anchor's cell, at `position` from the left, is centred on the finger.
        func start(anchorAt position: Int) -> Double {
            fingerX - (Double(position) + 0.5) * cellWidth
        }
        let inOrder = start(anchorAt: self.anchor)
        let mirrored = start(anchorAt: self.count - 1 - self.anchor)
        // In order wins a tie, so it is used whenever it fits, as R13 has it.
        isMirrored = overflow(mirrored) < overflow(inOrder)
        originX = max(min(isMirrored ? mirrored : inOrder, maxX - total), minX)
    }

    /// The option shown in cell `position`, counted from the left: 0 is the base, then the skins in order.
    /// Mirrored, the mapping is its own inverse: it also gives an option's position.
    public func option(atPosition position: Int) -> Int {
        isMirrored ? count - 1 - position : position
    }

    /// The cell under `x`, counted from the left; past either end, the end one. nil when `x` or the cell width is unusable.
    public func position(atX x: Double) -> Int? {
        let cell = ((x - originX) / cellWidth).rounded(.down)
        guard cellWidth > 0, cellWidth.isFinite, cell.isFinite else { return nil }
        // Clamped while still a Double: `Int(_:)` traps on values out of range.
        return Int(min(max(cell, 0), Double(count - 1)))
    }

    /// The option under `x`; past either end, the end one. The anchor when `x` or the cell width is unusable.
    public func option(atX x: Double) -> Int {
        position(atX: x).map(option(atPosition:)) ?? anchor
    }
}

/// What a hold on the skin-tone popup has picked as the finger slides: the anchor at first, then, once the finger
/// leaves the cell it began over, the option under the finger for the rest of the hold. So a hold lifted without
/// sliding types the anchor, even where an edge pushed the anchor's cell away from the finger.
public struct SkinTonePick: Equatable, Sendable {
    public let layout: SkinTonePopupLayout
    public private(set) var selected: Int
    /// The cell the finger began over; nil when its position was unusable.
    private let startPosition: Int?
    private var followsFinger = false

    public init(layout: SkinTonePopupLayout, fingerX: Double) {
        self.layout = layout
        selected = layout.anchor
        startPosition = layout.position(atX: fingerX)
    }

    /// The finger is now at `x`.
    public mutating func move(toX x: Double) {
        guard let position = layout.position(atX: x), followsFinger || position != startPosition else { return }
        followsFinger = true
        selected = layout.option(atPosition: position)
    }
}
