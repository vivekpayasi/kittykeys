/// Where the emoji panel's skin-tone popup puts its options: one row of equal cells, the base option and then its skins,
/// laid out like a key's long-press options (ruling R13).
///
/// The base cell is centred under the finger, and the skins run rightward from it when they fit between `minX` and `maxX`.
/// Otherwise they run leftward, mirrored, so the base stays under the finger at the right edge too. A row that fits
/// neither way goes the way that needs less shifting, and is shifted inside. With a width from `cellWidth(count:available:preferred:)`
/// the base cell always stays under the finger. Distances are in points.
public struct SkinTonePopupLayout: Equatable, Sendable {
    /// How many options there are: the base and its skins.
    public let count: Int
    public let cellWidth: Double
    /// Where the leftmost cell starts.
    public let originX: Double
    /// Whether the options run right to left, with the base in the rightmost cell.
    public let isMirrored: Bool

    /// The widest cell, at most `preferred`, that keeps the base cell under the finger wherever the finger is in
    /// `available` points. Shifting a row that fits neither way moves it less than half a cell when
    /// `(2 * count - 2) * width < available`. 0 when nothing fits.
    public static func cellWidth(count: Int, available: Double, preferred: Double) -> Double {
        guard available.isFinite, available > 0, preferred.isFinite, preferred > 0 else { return 0 }
        let limit = count > 1 ? available / Double(2 * count - 2) : available
        // Half a point under the limit, so the finger is never exactly on the base cell's edge.
        return max(0, min(preferred, (limit - 0.5).rounded(.down)))
    }

    /// `count` options in `cellWidth` cells, the base centred on `fingerX`, inside `minX...maxX` where they fit.
    /// Unusable numbers never trap: they give a row from `minX` whose every point picks the base.
    public init(count: Int, cellWidth: Double, fingerX: Double, minX: Double, maxX: Double) {
        self.count = max(count, 1)
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
        let rightward = fingerX - cellWidth / 2
        let leftward = fingerX + cellWidth / 2 - total
        // Rightward wins a tie, so it is used whenever it fits, as R13 has it.
        isMirrored = overflow(leftward) < overflow(rightward)
        let start = isMirrored ? leftward : rightward
        originX = max(min(start, maxX - total), minX)
    }

    /// The option shown in cell `position`, counted from the left: 0 is the base, then the skins in order.
    public func option(atPosition position: Int) -> Int {
        isMirrored ? count - 1 - position : position
    }

    /// The option under `x`; past either end, the end one. The base when `x` or the cell width is unusable.
    public func option(atX x: Double) -> Int {
        let cell = ((x - originX) / cellWidth).rounded(.down)
        guard cellWidth > 0, cell.isFinite else { return 0 }
        // Clamped while still a Double: `Int(_:)` traps on values out of range.
        return option(atPosition: Int(min(max(cell, 0), Double(count - 1))))
    }
}
