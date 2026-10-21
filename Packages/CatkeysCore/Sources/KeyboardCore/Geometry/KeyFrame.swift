/// A point in the keyboard's coordinate space, in points. y grows downward.
public struct Point: Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// An axis-aligned rectangle in the keyboard's coordinate space.
public struct Rect: Equatable, Sendable {
    public var x, y, width, height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var minX: Double { x }
    public var maxX: Double { x + width }
    public var minY: Double { y }
    public var maxY: Double { y + height }
    public var midX: Double { x + width / 2 }
    public var midY: Double { y + height / 2 }

    /// Whether `p` is inside the rectangle. Points on an edge count as inside.
    public func contains(_ p: Point) -> Bool {
        (minX...maxX).contains(p.x) && (minY...maxY).contains(p.y)
    }

    /// The straight-line distance from `p` to the nearest point of the rectangle: 0 inside or on an edge.
    public func distance(to p: Point) -> Double {
        let dx = max(minX - p.x, 0, p.x - maxX)
        let dy = max(minY - p.y, 0, p.y - maxY)
        return (dx * dx + dy * dy).squareRoot()
    }
}

/// A key placed on the keyboard.
public struct KeyFrame: Equatable, Sendable, Identifiable {
    /// The key's index in the array `KeyboardGeometry.frames` returned.
    public var id: Int
    public var key: KeySpec
    public var rect: Rect
    /// The row, counted from 0 at the top. The last row is the bottom row.
    public var row: Int
}
