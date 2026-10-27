import Testing
import KeyboardCore

/// The skin-tone popup: base and 5 skins, laid out like the long-press popup (ruling R13), with the option the cell
/// shows (the anchor, ruling M3-R10) under the finger.
struct SkinTonePopupLayoutTests {
    static let count = 6, padding = 4.0, preferred = 40.0

    /// Common iPhone widths in points, portrait. Every anchor and finger position keeps the popup inside and starts
    /// with the anchor picked. An end anchor (the base or the darkest skin) is always under the finger; a middle one
    /// is wherever either order fits without shifting.
    @Test(arguments: [320.0, 375.0, 390.0, 393.0, 402.0, 430.0, 440.0])
    func anchorStaysUnderTheFingerInsideTheKeyboard(_ width: Double) {
        let n = Self.count
        let minX = Self.padding, maxX = width - Self.padding
        let cell = SkinTonePopupLayout.cellWidth(count: n, available: maxX - minX, preferred: Self.preferred)
        #expect(cell > 0 && cell <= Self.preferred)
        for anchor in 0..<n {
            func fits(at position: Int, finger: Double) -> Bool {
                finger - (Double(position) + 0.5) * cell >= minX && finger + (Double(n - position) - 0.5) * cell <= maxX
            }
            var finger = 0.0
            while finger <= width {
                let layout = SkinTonePopupLayout(
                    count: n, anchor: anchor, cellWidth: cell, fingerX: finger, minX: minX, maxX: maxX)
                let context = "width \(width) anchor \(anchor) finger \(finger)"
                #expect(layout.originX >= minX - 1e-9, "\(context)")
                #expect(layout.originX + Double(n) * cell <= maxX + 1e-9, "\(context)")
                #expect(SkinTonePick(layout: layout, fingerX: finger).selected == anchor, "\(context)")
                let isEnd = anchor == 0 || anchor == n - 1
                let fitsUnshifted = fits(at: anchor, finger: finger) || fits(at: n - 1 - anchor, finger: finger)
                if finger >= minX && finger <= maxX && (isEnd || fitsUnshifted) {
                    #expect(layout.option(atX: finger) == anchor, "\(context)")
                }
                finger += 0.5
            }
        }
    }

    @Test func preferredWidthWhenThereIsRoom() {
        #expect(SkinTonePopupLayout.cellWidth(count: 6, available: 1000, preferred: 40) == 40)
        #expect(SkinTonePopupLayout.cellWidth(count: 6, available: 382, preferred: 40) < 38.2)
        #expect(SkinTonePopupLayout.cellWidth(count: 1, available: 30, preferred: 40) <= 30)
        #expect(SkinTonePopupLayout.cellWidth(count: 6, available: 0, preferred: 40) == 0)
        #expect(SkinTonePopupLayout.cellWidth(count: 6, available: -5, preferred: 40) == 0)
        #expect(SkinTonePopupLayout.cellWidth(count: 6, available: .nan, preferred: 40) == 0)
    }

    @Test func runsRightwardFromTheFingerWhenItFits() {
        let layout = SkinTonePopupLayout(count: 6, anchor: 0, cellWidth: 36, fingerX: 30, minX: 4, maxX: 386)
        #expect(!layout.isMirrored)
        #expect(layout.originX == 12)
        #expect((0..<6).map(layout.option(atPosition:)) == [0, 1, 2, 3, 4, 5])
        #expect(layout.option(atX: 30) == 0)
        #expect(layout.option(atX: 30 + 36) == 1)
        #expect(layout.option(atX: 30 + 4 * 36) == 4)
        #expect(layout.option(atX: 1000) == 5)
        #expect(layout.option(atX: -1000) == 0)
    }

    @Test func mirrorsAtTheRightEdge() {
        let layout = SkinTonePopupLayout(count: 6, anchor: 0, cellWidth: 36, fingerX: 360, minX: 4, maxX: 386)
        #expect(layout.isMirrored)
        #expect(layout.originX == 360 + 18 - 6 * 36)
        #expect((0..<6).map(layout.option(atPosition:)) == [5, 4, 3, 2, 1, 0])
        #expect(layout.option(atX: 360) == 0)
        #expect(layout.option(atX: 360 - 36) == 1)
        #expect(layout.option(atX: 0) == 5)
        #expect(layout.option(atX: 400) == 0)
    }

    /// Mirrored, the anchor's cell is counted from the right: skin 1 sits fourth from the left, under the finger.
    @Test func mirroredAnchorSitsUnderTheFinger() {
        let layout = SkinTonePopupLayout(count: 6, anchor: 1, cellWidth: 36, fingerX: 300, minX: 4, maxX: 386)
        #expect(layout.isMirrored)
        #expect(layout.originX == 300 - 4.5 * 36)
        #expect(layout.option(atX: 300) == 1)
        #expect(layout.option(atX: 300 - 36) == 2)
        #expect(layout.option(atX: 300 + 36) == 0)
    }

    @Test func clampsAtTheLeftEdge() {
        let layout = SkinTonePopupLayout(count: 6, anchor: 0, cellWidth: 36, fingerX: 6, minX: 4, maxX: 386)
        #expect(!layout.isMirrored)
        #expect(layout.originX == 4)
        #expect(layout.option(atX: 6) == 0)
    }

    @Test func clampsAtTheRightEdge() {
        let layout = SkinTonePopupLayout(count: 6, anchor: 0, cellWidth: 36, fingerX: 385, minX: 4, maxX: 386)
        #expect(layout.isMirrored)
        #expect(layout.originX == 386 - 6 * 36)
        #expect(layout.option(atX: 385) == 0)
    }

    /// The third skin (option 3) remembered, held in the left-most column: no order fits, so the row shifts inside,
    /// mirrored because that needs less shifting. The finger ends up over the darkest skin, but the remembered tone
    /// stays picked until the finger leaves its starting cell; after that the pick follows the finger.
    @Test func toneThreeAtTheLeftEdge() {
        let layout = SkinTonePopupLayout(count: 6, anchor: 3, cellWidth: 37, fingerX: 27.5, minX: 4, maxX: 386)
        #expect(layout.isMirrored)
        #expect(layout.originX == 4)
        #expect(layout.option(atX: 4 + 2 * 37 + 1) == 3)
        #expect(layout.option(atX: 27.5) == 5)
        var pick = SkinTonePick(layout: layout, fingerX: 27.5)
        #expect(pick.selected == 3)
        pick.move(toX: 30)
        #expect(pick.selected == 3)
        pick.move(toX: 4 + 37 + 5)
        #expect(pick.selected == 4)
        pick.move(toX: 27.5)
        #expect(pick.selected == 5)
    }

    /// The same at the right-most column: the row runs rightward, shifted inside, with the finger over the darkest skin.
    @Test func toneThreeAtTheRightEdge() {
        let layout = SkinTonePopupLayout(count: 6, anchor: 3, cellWidth: 37, fingerX: 374.5, minX: 4, maxX: 386)
        #expect(!layout.isMirrored)
        #expect(layout.originX == 386 - 6 * 37)
        #expect(layout.option(atX: 374.5) == 5)
        var pick = SkinTonePick(layout: layout, fingerX: 374.5)
        #expect(pick.selected == 3)
        pick.move(toX: 372)
        #expect(pick.selected == 3)
        pick.move(toX: 164 + 4 * 37 + 5)
        #expect(pick.selected == 4)
        pick.move(toX: 164 + 3 * 37 + 5)
        #expect(pick.selected == 3)
    }

    /// Away from the edges the remembered tone is under the finger, and sliding one cell picks its neighbour.
    @Test func toneThreeInTheMiddle() {
        let layout = SkinTonePopupLayout(count: 6, anchor: 3, cellWidth: 37, fingerX: 201, minX: 4, maxX: 386)
        #expect(!layout.isMirrored)
        #expect(layout.originX == 201 - 3.5 * 37)
        #expect(layout.option(atX: 201) == 3)
        var pick = SkinTonePick(layout: layout, fingerX: 201)
        pick.move(toX: 201 + 37)
        #expect(pick.selected == 4)
        pick.move(toX: 201)
        #expect(pick.selected == 3)
    }

    /// Bad numbers never trap: a crash kills the keyboard. The anchor stays picked.
    @Test(arguments: [0.0, -10.0, .nan, .infinity])
    func unusableCellWidthPicksTheAnchor(_ width: Double) {
        for anchor in [0, 3] {
            let layout = SkinTonePopupLayout(count: 6, anchor: anchor, cellWidth: width, fingerX: 100, minX: 4, maxX: 386)
            #expect(layout.option(atX: 100) == anchor)
            #expect(layout.option(atX: 300) == anchor)
            #expect(layout.option(atX: .nan) == anchor)
            var pick = SkinTonePick(layout: layout, fingerX: 100)
            pick.move(toX: 300)
            #expect(pick.selected == anchor)
        }
    }

    @Test func unusableFingerCountOrAnchor() {
        let layout = SkinTonePopupLayout(count: 6, anchor: 0, cellWidth: 36, fingerX: .nan, minX: 4, maxX: 386)
        #expect(layout.originX.isFinite)
        #expect(layout.option(atX: .nan) == 0)
        #expect(layout.option(atX: .infinity) == 0)
        let empty = SkinTonePopupLayout(count: 0, anchor: 0, cellWidth: 36, fingerX: 100, minX: 4, maxX: 386)
        #expect(empty.option(atX: 100) == 0)
        let cramped = SkinTonePopupLayout(count: 6, anchor: 0, cellWidth: 36, fingerX: 50, minX: 4, maxX: 100)
        #expect(cramped.originX == 4)
        // An anchor out of range is taken as the nearest end.
        #expect(SkinTonePopupLayout(count: 6, anchor: 9, cellWidth: 36, fingerX: 200, minX: 4, maxX: 386).anchor == 5)
        #expect(SkinTonePopupLayout(count: 6, anchor: -1, cellWidth: 36, fingerX: 200, minX: 4, maxX: 386).anchor == 0)
    }
}
