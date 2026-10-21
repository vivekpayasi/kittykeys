/// Places a page's keys on the keyboard and finds the key under a touch.
public enum KeyboardGeometry {
    /// A row of this many one-unit keys fills the keyboard from side padding to side padding.
    private static let unitsPerRow = 10.0

    /// The frames of `page`'s rows followed by `bottom`, in row-major order.
    ///
    /// Rows stack from the bottom of the suggestion row down, `rowGap` apart. Number rows are
    /// `numberRowHeight` tall and all other rows `keyHeight`. Each row is centred in `width`.
    public static func frames(page: LayoutPage, bottom: [KeySpec], width: Double, metrics: KeyboardMetrics) -> [KeyFrame] {
        let available = width - 2 * metrics.sidePadding
        let unit = (available - (unitsPerRow - 1) * metrics.keyGap) / unitsPerRow
        let rows = page.rows.map { (keys: $0.keys, height: $0.kind == .number ? metrics.numberRowHeight : metrics.keyHeight) }
            + [(keys: bottom, height: metrics.keyHeight)]

        var frames: [KeyFrame] = []
        var y = metrics.suggestionRowHeight
        for (rowIndex, row) in rows.enumerated() {
            let widths = keyWidths(row.keys, available: available, unit: unit, gap: metrics.keyGap)
            let rowWidth = widths.reduce(0, +) + gapsWidth(keyCount: widths.count, gap: metrics.keyGap)
            var x = (width - rowWidth) / 2
            for (key, keyWidth) in zip(row.keys, widths) {
                let rect = Rect(x: x, y: y, width: keyWidth, height: row.height)
                frames.append(KeyFrame(id: frames.count, key: key, rect: rect, row: rowIndex))
                x += keyWidth + metrics.keyGap
            }
            y += row.height + metrics.rowGap
        }
        return frames
    }

    /// The frame nearest to `p`, so touches in gaps and past the edges still hit a key.
    ///
    /// Returns nil for touches in the suggestion row, or when `frames` is empty.
    /// When two frames are equally near, the earlier one wins.
    public static func hitTest(_ p: Point, in frames: [KeyFrame], metrics: KeyboardMetrics) -> KeyFrame? {
        guard p.y >= metrics.suggestionRowHeight else { return nil }
        var nearest: KeyFrame?
        var nearestDistance = Double.infinity
        for frame in frames {
            let distance = frame.rect.distance(to: p)
            if distance < nearestDistance {
                nearest = frame
                nearestDistance = distance
            }
        }
        return nearest
    }

    /// Each key's width in points. A key `w` units wide spans `w` units and the `w - 1` gaps between them.
    /// Width-0 keys split whatever `available` space the other keys and the gaps leave.
    private static func keyWidths(_ keys: [KeySpec], available: Double, unit: Double, gap: Double) -> [Double] {
        let fixed = keys.map { $0.width == 0 ? 0 : unit * $0.width + gap * ($0.width - 1) }
        let fillCount = keys.count(where: { $0.width == 0 })
        guard fillCount > 0 else { return fixed }
        let leftover = available - fixed.reduce(0, +) - gapsWidth(keyCount: keys.count, gap: gap)
        let fillWidth = max(0, leftover / Double(fillCount))
        return zip(keys, fixed).map { key, width in key.width == 0 ? fillWidth : width }
    }

    private static func gapsWidth(keyCount: Int, gap: Double) -> Double {
        Double(max(keyCount - 1, 0)) * gap
    }
}
