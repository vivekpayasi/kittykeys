import Testing
import KeyboardCore

/// The skin-tone popup: base and 5 skins, laid out like the long-press popup (ruling R13), with the base under the finger.
struct SkinTonePopupLayoutTests {
    static let count = 6, padding = 4.0, preferred = 40.0

    /// Common iPhone widths in points, portrait.
    @Test(arguments: [320.0, 375.0, 390.0, 393.0, 402.0, 430.0, 440.0])
    func baseStaysUnderTheFingerInsideTheKeyboard(_ width: Double) {
        let minX = Self.padding, maxX = width - Self.padding
        let cell = SkinTonePopupLayout.cellWidth(count: Self.count, available: maxX - minX, preferred: Self.preferred)
        #expect(cell > 0 && cell <= Self.preferred)
        var finger = 0.0
        while finger <= width {
            let layout = SkinTonePopupLayout(count: Self.count, cellWidth: cell, fingerX: finger, minX: minX, maxX: maxX)
            #expect(layout.originX >= minX - 1e-9, "finger \(finger)")
            #expect(layout.originX + Double(Self.count) * cell <= maxX + 1e-9, "finger \(finger)")
            if finger >= minX && finger <= maxX {
                #expect(layout.option(atX: finger) == 0, "width \(width) finger \(finger)")
            }
            finger += 0.5
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
        let layout = SkinTonePopupLayout(count: 6, cellWidth: 36, fingerX: 30, minX: 4, maxX: 386)
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
        let layout = SkinTonePopupLayout(count: 6, cellWidth: 36, fingerX: 360, minX: 4, maxX: 386)
        #expect(layout.isMirrored)
        #expect(layout.originX == 360 + 18 - 6 * 36)
        #expect((0..<6).map(layout.option(atPosition:)) == [5, 4, 3, 2, 1, 0])
        #expect(layout.option(atX: 360) == 0)
        #expect(layout.option(atX: 360 - 36) == 1)
        #expect(layout.option(atX: 0) == 5)
        #expect(layout.option(atX: 400) == 0)
    }

    @Test func clampsAtTheLeftEdge() {
        let layout = SkinTonePopupLayout(count: 6, cellWidth: 36, fingerX: 6, minX: 4, maxX: 386)
        #expect(!layout.isMirrored)
        #expect(layout.originX == 4)
        #expect(layout.option(atX: 6) == 0)
    }

    @Test func clampsAtTheRightEdge() {
        let layout = SkinTonePopupLayout(count: 6, cellWidth: 36, fingerX: 385, minX: 4, maxX: 386)
        #expect(layout.isMirrored)
        #expect(layout.originX == 386 - 6 * 36)
        #expect(layout.option(atX: 385) == 0)
    }

    /// Bad numbers never trap: a crash kills the keyboard. The base is picked.
    @Test(arguments: [0.0, -10.0, .nan, .infinity])
    func unusableCellWidthPicksTheBase(_ width: Double) {
        let layout = SkinTonePopupLayout(count: 6, cellWidth: width, fingerX: 100, minX: 4, maxX: 386)
        #expect(layout.option(atX: 100) == 0)
        #expect(layout.option(atX: 300) == 0)
        #expect(layout.option(atX: .nan) == 0)
    }

    @Test func unusableFingerOrCount() {
        let layout = SkinTonePopupLayout(count: 6, cellWidth: 36, fingerX: .nan, minX: 4, maxX: 386)
        #expect(layout.originX.isFinite)
        #expect(layout.option(atX: .nan) == 0)
        #expect(layout.option(atX: .infinity) == 0)
        let empty = SkinTonePopupLayout(count: 0, cellWidth: 36, fingerX: 100, minX: 4, maxX: 386)
        #expect(empty.option(atX: 100) == 0)
        let cramped = SkinTonePopupLayout(count: 6, cellWidth: 36, fingerX: 50, minX: 4, maxX: 100)
        #expect(cramped.originX == 4)
    }
}
