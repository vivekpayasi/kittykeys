import Foundation
import Testing
import KeyboardCore

// Worked numbers at width 390 with standard metrics:
// unit = (390 - 6 - 54) / 10 = 33.
// Rows, top to bottom (y): number 44...80, q-p 90...132, a-l 142...184, z-m 194...236, bottom 246...288.
// a-l row: 9 keys, 345 wide, centred from x 22.5: f is 139.5...172.5, g is 178.5...211.5, l ends at 367.5.
// Bottom row: 123 3...55.5, 😊 61.5...94.5, "," 100.5...133.5, space 139.5...270, "." 276...309, return 315...387.

private func qwertyFrames() throws -> [KeyFrame] {
    let page = try #require(try LayoutSet.bundled().page("latin-qwerty"))
    return KeyboardGeometry.frames(page: page, bottom: page.bottomRow(.standard), width: 390, metrics: .standard)
}

private func label(at p: Point, in frames: [KeyFrame]) -> String? {
    KeyboardGeometry.hitTest(p, in: frames, metrics: .standard)?.key.label
}

// width 390 → unit = (390 - 6 - 54) / 10 = 33
@Test func rowsLayOutEdgeToEdge() throws {
    let page = try #require(try LayoutSet.bundled().page("latin-qwerty"))
    let f = KeyboardGeometry.frames(page: page, bottom: page.bottomRow(.standard), width: 390, metrics: .standard)
    let q = try #require(f.first { $0.key.label == "q" }), p = try #require(f.first { $0.key.label == "p" })
    #expect(abs(q.rect.minX - 3) < 0.01 && abs(p.rect.maxX - 387) < 0.01 && abs(q.rect.width - 33) < 0.01)
    #expect(f.first { $0.key.label == "1" }!.rect.height == 36 && q.rect.height == 42)
    #expect(abs(f.first { $0.key.label == "a" }!.rect.minX - (390 - (9*33 + 8*6)) / 2) < 0.01)
    let space = try #require(f.first { $0.key.action == .space })
    let ret = try #require(f.first { $0.key.action == .returnKey })
    #expect(abs(ret.rect.maxX - 387) < 0.01 && space.rect.width > 100)
    #expect(KeyboardMetrics.standard.totalHeight(rowCount: 5) == 292)
}

@Test func framesAreRowMajorAndStackedBelowSuggestionRow() throws {
    let f = try qwertyFrames()
    #expect(f.map(\.id) == Array(f.indices))
    #expect(f.map(\.row) == Array(repeating: 0, count: 10) + Array(repeating: 1, count: 10)
        + Array(repeating: 2, count: 9) + Array(repeating: 3, count: 9) + Array(repeating: 4, count: 6))
    let rowTops = (0...4).map { row in f.first { $0.row == row }!.rect.minY }
    #expect(rowTops == [44, 90, 142, 194, 246])
    #expect(f.last!.rect.maxY + KeyboardMetrics.standard.bottomPadding == KeyboardMetrics.standard.totalHeight(rowCount: 5))
}

@Test func fillKeysShareLeftoverSpace() throws {
    let page = try #require(try LayoutSet.bundled().page("latin-qwerty"))
    let bottom = try JSONDecoder().decode([KeySpec].self, from: Data(
        #"[{"label":"x","width":0},{"label":"y","width":2},{"label":"z","width":0}]"#.utf8))
    let row = KeyboardGeometry.frames(page: page, bottom: bottom, width: 390, metrics: .standard).filter { $0.row == 4 }
    // 384 available - 72 for y - 2 gaps of 6 = 300, split in two.
    #expect(row.map(\.rect.width) == [150, 72, 150])
    #expect(row.first!.rect.minX == 3 && row.last!.rect.maxX == 387)
}

@Test func gapsGoToNearestKey() throws {
    let f = try qwertyFrames()
    // The f|g gap is x 172.5...178.5, midpoint 175.5; the a-l row's middle is y 163.
    #expect(label(at: Point(x: 176.5, y: 163), in: f) == "g")
    #expect(label(at: Point(x: 174.5, y: 163), in: f) == "f")
    // Left of a and right of l.
    #expect(label(at: Point(x: 0, y: 163), in: f) == "a")
    #expect(label(at: Point(x: 390, y: 163), in: f) == "l")
    // The gap between the q-p and a-l rows is y 132...142, midpoint 137; x 195 is g's middle.
    #expect(label(at: Point(x: 195, y: 138), in: f) == "g")
    // The bottom padding (y 288...292) and everything below it go to the bottom row.
    #expect(label(at: Point(x: 200, y: 291), in: f) == "space")
    #expect(label(at: Point(x: 390, y: 291), in: f) == "return")
    #expect(label(at: Point(x: 200, y: 400), in: f) == "space")
}

@Test func hitTestPicksTheRowFirst() throws {
    let f = try qwertyFrames()
    // The a-l row's band runs from just past y 137 to y 189 (halfway through the gap above z-m).
    // Its left gutter (x < 22.5) is nearer to q or shift as rectangles, but the band keeps it on a.
    #expect(label(at: Point(x: 5, y: 145), in: f) == "a")
    #expect(label(at: Point(x: 5, y: 180), in: f) == "a")
    #expect(label(at: Point(x: 5, y: 194), in: f) == "⇧")
    #expect(label(at: Point(x: 385, y: 150), in: f) == "l")
    // The midpoint of the gap belongs to the row above; anything past it to the row below.
    #expect(label(at: Point(x: 20, y: 137), in: f) == "q")
    #expect(label(at: Point(x: 20, y: 137.1), in: f) == "a")
}

@Test func tooNarrowForKeysGivesNoFrames() throws {
    let page = try #require(try LayoutSet.bundled().page("latin-qwerty"))
    // Below width 60 the unit is negative: an input view is often 0 wide on its first layout pass.
    #expect(KeyboardGeometry.frames(page: page, bottom: page.bottomRow(.standard), width: 0, metrics: .standard).isEmpty)
    #expect(KeyboardGeometry.frames(page: page, bottom: page.bottomRow(.standard), width: 50, metrics: .standard).isEmpty)
    #expect(KeyboardGeometry.hitTest(Point(x: 200, y: 100), in: [], metrics: .standard) == nil)
}

@Test func suggestionRowIsNotAKey() throws {
    let f = try qwertyFrames()
    #expect(KeyboardGeometry.hitTest(Point(x: 200, y: 20), in: f, metrics: .standard) == nil)
    #expect(label(at: Point(x: 200, y: 43.9), in: f) == nil)
    // The number row starts at y 44; 6 is x 198...231.
    #expect(label(at: Point(x: 200, y: 44), in: f) == "6")
}

@Test func rectDistanceIsZeroInsideAndStraightLineOutside() {
    let r = Rect(x: 10, y: 20, width: 30, height: 40)
    #expect(r.minX == 10 && r.maxX == 40 && r.minY == 20 && r.maxY == 60 && r.midX == 25 && r.midY == 40)
    #expect(r.contains(Point(x: 25, y: 40)) && r.distance(to: Point(x: 25, y: 40)) == 0)
    #expect(r.contains(Point(x: 40, y: 60)) && r.distance(to: Point(x: 40, y: 60)) == 0)
    #expect(!r.contains(Point(x: 0, y: 40)) && r.distance(to: Point(x: 0, y: 40)) == 10)
    #expect(r.distance(to: Point(x: 43, y: 64)) == 5)
}

@Test func containsHandlesNegativeSize() {
    #expect(!Rect(x: 10, y: 10, width: -5, height: 5).contains(Point(x: 8, y: 12)))
}
