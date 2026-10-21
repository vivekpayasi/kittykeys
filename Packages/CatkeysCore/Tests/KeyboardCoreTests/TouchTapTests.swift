import Testing
import KeyboardCore

// Worked numbers at width 390 with standard metrics (see GeometryTests):
// Rows (y): number 44...80, q-p 90...132, a-l 142...184, z-m 194...236, bottom 246...288.
// Keys are 33 wide, 39 apart. Number and q-p rows start at x 3: 5 is 159...192.
// a-l row starts at x 22.5: a 22.5...55.5, s 61.5...94.5, d 100.5...133.5, f 139.5...172.5, g 178.5...211.5.
// z-m row: ⇧ 3...55.5. Bottom row: 123 3...55.5, 😊 61.5...94.5, "," 100.5...133.5, space 139.5...270,
// "." 276...309, return 315...387.
// Long-press cells are 36 wide. d's three options fit rightward from its left edge, x 100.5.
// "."'s six options are 216 wide and would pass x 390 from x 276, so they run leftward from its right edge:
// they start at 309 - 216 = 93, and "." (the default) is the rightmost cell, x 273...309.

struct TouchTapTests {
    let frames: [KeyFrame]
    let touches = TouchProcessor()

    init() throws {
        frames = try Self.pageFrames("latin-qwerty")
        touches.frames = frames
        touches.keyboardWidth = 390
    }

    static func pageFrames(_ id: String) throws -> [KeyFrame] {
        let page = try #require(try LayoutSet.bundled().page(id))
        return KeyboardGeometry.frames(page: page, bottom: page.bottomRow(.standard), width: 390, metrics: .standard)
    }

    func key(_ label: String) throws -> KeyFrame {
        try #require(frames.first { $0.key.label == label })
    }

    func center(_ label: String) throws -> Point {
        let rect = try key(label).rect
        return Point(x: rect.midX, y: rect.midY)
    }

    @Test func tapCommitsOnLiftAtLandingPoint() throws {
        let a = try key("a"), pa = try center("a"), ps = try center("s")
        #expect(pa == Point(x: 39, y: 163) && ps == Point(x: 78, y: 163))
        #expect(touches.touchDown(1, at: pa, time: 0) == [.keyDown(a)])
        // Sliding onto s changes nothing: the key is the one the finger landed on.
        #expect(touches.touchMoved(1, to: ps, time: 0.05) == [])
        #expect(touches.touchUp(1, at: ps, time: 0.1) == [.activate(a, landing: pa), .keyUp(a)])
        #expect(touches.nextDeadline == nil)
    }

    @Test func rolloverCommitsEarlierKeyFirst() throws {
        let a = try key("a"), s = try key("s"), pa = try center("a"), ps = try center("s")
        #expect(touches.touchDown(1, at: pa, time: 0) == [.keyDown(a)])
        // s lands while a is still down: a is typed before s even highlights.
        #expect(touches.touchDown(2, at: ps, time: 0.05) == [.activate(a, landing: pa), .keyDown(s)])
        // a is already typed, so its lift only clears its highlight.
        #expect(touches.touchUp(1, at: pa, time: 0.08) == [.keyUp(a)])
        #expect(touches.touchUp(2, at: ps, time: 0.12) == [.activate(s, landing: ps), .keyUp(s)])
        #expect(touches.nextDeadline == nil)
    }

    @Test func longPressShowsAndPicksAlternate() throws {
        let d = try key("d"), pd = try center("d")
        #expect(d.rect.minX == 100.5 && pd == Point(x: 117, y: 163))
        #expect(touches.touchDown(1, at: pd, time: 0) == [.keyDown(d)])
        #expect(touches.nextDeadline == 0.3)
        #expect(touches.advance(to: 0.29) == [])
        #expect(touches.advance(to: 0.3) == [.alternatesShown(d, options: ["₹", "$", "€"], selected: 0, originX: d.rect.minX)])
        #expect(touches.nextDeadline == nil)
        // 40 pt right is x 157: (157 - 100.5) / 36 = 1.57, the second cell.
        #expect(touches.touchMoved(1, to: Point(x: 157, y: 163), time: 0.4) == [.alternateSelected(d, selected: 1)])
        // x 170 is still the second cell: (170 - 100.5) / 36 = 1.93.
        #expect(touches.touchMoved(1, to: Point(x: 170, y: 150), time: 0.45) == [])
        #expect(touches.touchUp(1, at: Point(x: 170, y: 150), time: 0.5) == [.activateAlternate(d, text: "$"), .keyUp(d)])
    }

    @Test func alternatesStayOnTheKeyboard() throws {
        let period = try key("."), pp = try center(".")
        #expect(period.rect.minX == 276 && period.rect.maxX == 309 && pp == Point(x: 292.5, y: 267))
        #expect(touches.touchDown(1, at: pp, time: 0) == [.keyDown(period)])
        // The options run leftward in display order, so the default "." is selected under the finger.
        #expect(touches.advance(to: 0.3)
            == [.alternatesShown(period, options: ["/", ":", "…", "!", "?", "."], selected: 5, originX: 93)])
        // A 5 pt jitter either way stays in the "." cell: (297.5 - 93) / 36 = 5.68, (287.5 - 93) / 36 = 5.40.
        #expect(touches.touchMoved(1, to: Point(x: 297.5, y: 267), time: 0.35) == [])
        #expect(touches.touchMoved(1, to: Point(x: 287.5, y: 267), time: 0.4) == [])
        // 36 pt left of the landing point is x 256.5: (256.5 - 93) / 36 = 4.54, the "?" cell.
        #expect(touches.touchMoved(1, to: Point(x: 256.5, y: 267), time: 0.5) == [.alternateSelected(period, selected: 4)])
        // Past either end of the popup, the end option is selected.
        #expect(touches.touchMoved(1, to: Point(x: 0, y: 267), time: 0.6) == [.alternateSelected(period, selected: 0)])
        #expect(touches.touchMoved(1, to: Point(x: 390, y: 267), time: 0.7) == [.alternateSelected(period, selected: 5)])
        #expect(touches.touchMoved(1, to: Point(x: 256.5, y: 267), time: 0.8) == [.alternateSelected(period, selected: 4)])
        #expect(touches.touchUp(1, at: Point(x: 256.5, y: 267), time: 0.9) == [.activateAlternate(period, text: "?"), .keyUp(period)])
    }

    @Test func unusableAlternateWidthKeepsTheDefault() throws {
        let d = try key("d"), pd = try center("d")
        // A finger at a non-finite x selects the default option rather than trapping.
        #expect(touches.touchDown(1, at: pd, time: 0) == [.keyDown(d)])
        #expect(touches.advance(to: 0.3) == [.alternatesShown(d, options: ["₹", "$", "€"], selected: 0, originX: 100.5)])
        #expect(touches.touchMoved(1, to: Point(x: 157, y: 163), time: 0.4) == [.alternateSelected(d, selected: 1)])
        #expect(touches.touchMoved(1, to: Point(x: .nan, y: 163), time: 0.45) == [.alternateSelected(d, selected: 0)])
        #expect(touches.touchUp(1, at: pd, time: 0.5) == [.activateAlternate(d, text: "₹"), .keyUp(d)])
        // Cells 0 wide: no move leaves the default option.
        touches.timing.alternateWidth = 0
        #expect(touches.touchDown(2, at: pd, time: 1) == [.keyDown(d)])
        #expect(touches.advance(to: 1.5) == [.alternatesShown(d, options: ["₹", "$", "€"], selected: 0, originX: 100.5)])
        #expect(touches.touchMoved(2, to: Point(x: 157, y: 163), time: 1.6) == [])
        #expect(touches.touchMoved(2, to: Point(x: 100.5, y: 163), time: 1.65) == [])
        #expect(touches.touchUp(2, at: Point(x: 157, y: 163), time: 1.7) == [.activateAlternate(d, text: "₹"), .keyUp(d)])
    }

    @Test func unusableAlternateWidthLaysOutFromTheKey() throws {
        let period = try key("."), pp = try center(".")
        // A cell width that is not a positive number can't place the popup: it starts at the key's left edge
        // in the key's own order, default first and selected, rather than at a NaN or clamped origin.
        for (id, width) in [Double.nan, .infinity, -36].enumerated() {
            touches.timing.alternateWidth = width
            #expect(touches.touchDown(id, at: pp, time: Double(id)) == [.keyDown(period)])
            #expect(touches.advance(to: Double(id) + 0.3)
                == [.alternatesShown(period, options: [".", "?", "!", "…", ":", "/"], selected: 0, originX: 276)])
            #expect(touches.touchMoved(id, to: Point(x: 200, y: 267), time: Double(id) + 0.4) == [])
            #expect(touches.touchUp(id, at: pp, time: Double(id) + 0.5) == [.activateAlternate(period, text: "."), .keyUp(period)])
        }
    }

    @Test func onlyOnePopupAtATime() throws {
        let d = try key("d"), g = try key("g"), pd = try center("d"), pg = try center("g")
        #expect(touches.touchDown(1, at: pd, time: 0) == [.keyDown(d)])
        #expect(touches.advance(to: 0.3) == [.alternatesShown(d, options: ["₹", "$", "€"], selected: 0, originX: 100.5)])
        // g lands while d's options show: it gets no long-press, so it types on lift however long it's held.
        #expect(touches.touchDown(2, at: pg, time: 0.4) == [.keyDown(g)])
        #expect(touches.nextDeadline == nil)
        #expect(touches.advance(to: 1.0) == [])
        #expect(touches.touchUp(2, at: pg, time: 1.1) == [.activate(g, landing: pg), .keyUp(g)])
        #expect(touches.touchUp(1, at: pd, time: 1.2) == [.activateAlternate(d, text: "₹"), .keyUp(d)])
    }

    @Test func holdWithoutOptionsTypesKey() throws {
        let five = try key("5"), p5 = try center("5")
        #expect(five.key.longPress.isEmpty && p5 == Point(x: 175.5, y: 62))
        #expect(touches.touchDown(1, at: p5, time: 0) == [.keyDown(five)])
        #expect(touches.nextDeadline == nil)
        #expect(touches.advance(to: 1.0) == [])
        #expect(touches.touchUp(1, at: p5, time: 1.0) == [.activate(five, landing: p5), .keyUp(five)])
    }

    @Test func rolloverCancelsLongPress() throws {
        let d = try key("d"), f = try key("f"), pd = try center("d"), pf = try center("f")
        #expect(touches.touchDown(1, at: pd, time: 0) == [.keyDown(d)])
        #expect(touches.touchDown(2, at: pf, time: 0.1) == [.activate(d, landing: pd), .keyDown(f)])
        #expect(touches.touchUp(2, at: pf, time: 0.2) == [.activate(f, landing: pf), .keyUp(f)])
        // d is still held past its 0.3 s delay, but it was already typed, so its options never show.
        #expect(touches.nextDeadline == nil)
        #expect(touches.advance(to: 0.5) == [])
        #expect(touches.touchUp(1, at: pd, time: 0.6) == [.keyUp(d)])
    }

    @Test func shownOptionsSurviveANewFinger() throws {
        let d = try key("d"), f = try key("f"), pd = try center("d"), pf = try center("f")
        #expect(touches.touchDown(1, at: pd, time: 0) == [.keyDown(d)])
        #expect(touches.advance(to: 0.3) == [.alternatesShown(d, options: ["₹", "$", "€"], selected: 0, originX: 100.5)])
        // Once d's options show, a finger landing elsewhere doesn't type d.
        #expect(touches.touchDown(2, at: pf, time: 0.4) == [.keyDown(f)])
        #expect(touches.touchUp(2, at: pf, time: 0.45) == [.activate(f, landing: pf), .keyUp(f)])
        #expect(touches.touchUp(1, at: pd, time: 0.5) == [.activateAlternate(d, text: "₹"), .keyUp(d)])
    }

    @Test func shiftAndPageKeysActOnDown() throws {
        let shift = try key("⇧"), pShift = try center("⇧")
        #expect(touches.touchDown(1, at: pShift, time: 0) == [.keyDown(shift), .activate(shift, landing: pShift)])
        #expect(touches.touchUp(1, at: pShift, time: 0.1) == [.keyUp(shift)])
        let symbols = try key("123"), pSymbols = try center("123")
        #expect(touches.touchDown(2, at: pSymbols, time: 0.2) == [.keyDown(symbols), .activate(symbols, landing: pSymbols)])
        #expect(touches.nextDeadline == nil)
        #expect(touches.touchUp(2, at: pSymbols, time: 0.3) == [.keyUp(symbols)])
    }

    @Test func heldLetterTypesBeforeShiftActs() throws {
        let a = try key("a"), shift = try key("⇧"), pa = try center("a"), pShift = try center("⇧")
        #expect(touches.touchDown(1, at: pa, time: 0) == [.keyDown(a)])
        // a, then shift: a is typed before shift takes effect, so it stays lowercase.
        #expect(touches.touchDown(2, at: pShift, time: 0.05)
            == [.activate(a, landing: pa), .keyDown(shift), .activate(shift, landing: pShift)])
        #expect(touches.touchUp(1, at: pa, time: 0.1) == [.keyUp(a)])
        #expect(touches.touchUp(2, at: pShift, time: 0.15) == [.keyUp(shift)])
    }

    @Test func heldReturnTypesBeforeTheNextKey() throws {
        let ret = try key("return"), a = try key("a"), pRet = try center("return"), pa = try center("a")
        #expect(touches.touchDown(1, at: pRet, time: 0) == [.keyDown(ret)])
        // a lands while return is still down: the new line is typed first, even though a lifts first.
        #expect(touches.touchDown(2, at: pa, time: 0.05) == [.activate(ret, landing: pRet), .keyDown(a)])
        #expect(touches.touchUp(2, at: pa, time: 0.1) == [.activate(a, landing: pa), .keyUp(a)])
        #expect(touches.touchUp(1, at: pRet, time: 0.15) == [.keyUp(ret)])
    }

    @Test func returnAndEmojiActOnLift() throws {
        let ret = try key("return"), pRet = try center("return")
        #expect(touches.touchDown(1, at: pRet, time: 0) == [.keyDown(ret)])
        #expect(touches.touchUp(1, at: pRet, time: 0.1) == [.activate(ret, landing: pRet), .keyUp(ret)])
        let emoji = try key("😊"), pEmoji = try center("😊")
        #expect(touches.touchDown(2, at: pEmoji, time: 0.2) == [.keyDown(emoji)])
        #expect(touches.touchUp(2, at: pEmoji, time: 0.3) == [.activate(emoji, landing: pEmoji), .keyUp(emoji)])
    }

    @Test func longPressDelayIsConfigurable() throws {
        touches.timing.longPress = 0.5
        let d = try key("d"), pd = try center("d")
        #expect(touches.touchDown(1, at: pd, time: 0) == [.keyDown(d)])
        #expect(touches.nextDeadline == 0.5)
        #expect(touches.advance(to: 0.3) == [])
        #expect(touches.advance(to: 0.5) == [.alternatesShown(d, options: ["₹", "$", "€"], selected: 0, originX: 100.5)])
    }

    @Test func cancelClearsEverything() throws {
        let d = try key("d"), f = try key("f"), pd = try center("d"), pf = try center("f")
        // A held key: cancel clears its highlight, types nothing and stops its long-press timer.
        #expect(touches.touchDown(1, at: pd, time: 0) == [.keyDown(d)])
        #expect(touches.touchCancelled(1) == [.keyUp(d)])
        #expect(touches.nextDeadline == nil)
        #expect(touches.advance(to: 1) == [])
        #expect(touches.touchUp(1, at: pd, time: 1.1) == [])
        // Options showing: cancel closes them without typing one.
        #expect(touches.touchDown(2, at: pd, time: 2) == [.keyDown(d)])
        #expect(touches.advance(to: 2.5) == [.alternatesShown(d, options: ["₹", "$", "€"], selected: 0, originX: 100.5)])
        #expect(touches.touchCancelled(2) == [.keyUp(d)])
        #expect(touches.touchUp(2, at: pd, time: 2.6) == [])
        // A key already typed by rollover: cancel only clears its highlight.
        #expect(touches.touchDown(3, at: pd, time: 3) == [.keyDown(d)])
        #expect(touches.touchDown(4, at: pf, time: 3.05) == [.activate(d, landing: pd), .keyDown(f)])
        #expect(touches.touchCancelled(3) == [.keyUp(d)])
        #expect(touches.touchCancelled(4) == [.keyUp(f)])
        #expect(touches.nextDeadline == nil)
        #expect(touches.advance(to: 10) == [])
    }

    @Test func suggestionRowTouchesIgnored() throws {
        let a = try key("a"), pa = try center("a")
        #expect(touches.touchDown(1, at: Point(x: 200, y: 20), time: 0) == [])
        // Sliding down onto g still does nothing.
        #expect(touches.touchMoved(1, to: Point(x: 200, y: 163), time: 0.05) == [])
        #expect(touches.touchUp(1, at: Point(x: 200, y: 163), time: 0.1) == [])
        #expect(touches.nextDeadline == nil)
        // One landing while a key is held doesn't type that key early.
        #expect(touches.touchDown(2, at: pa, time: 1) == [.keyDown(a)])
        #expect(touches.touchDown(3, at: Point(x: 200, y: 20), time: 1.05) == [])
        #expect(touches.touchCancelled(3) == [])
        #expect(touches.touchUp(2, at: pa, time: 1.1) == [.activate(a, landing: pa), .keyUp(a)])
        // Before the first layout gives it frames, every touch lands on no key.
        let unlaidOut = TouchProcessor()
        #expect(unlaidOut.touchDown(1, at: pa, time: 0) == [])
        #expect(unlaidOut.touchUp(1, at: pa, time: 0.1) == [])
    }

    @Test func elevenTouchesCommitInOrder() throws {
        // Digits (no long-press options), letters, punctuation and space, all on distinct keys.
        let labels = ["1", "q", "a", "z", "2", "w", "s", "x", ",", "space", "."]
        let keys = try labels.map { try key($0) }, points = try labels.map { try center($0) }
        var events: [TouchEvent] = []
        for id in keys.indices {
            // Each landing types the key before it, then highlights its own.
            let expected: [TouchEvent] = id == 0
                ? [.keyDown(keys[0])]
                : [.activate(keys[id - 1], landing: points[id - 1]), .keyDown(keys[id])]
            let down = touches.touchDown(id, at: points[id], time: Double(id) * 0.01)
            #expect(down == expected)
            events += down
        }
        // Lifting newest first: only the last key is still waiting to be typed.
        let lastUp = touches.touchUp(10, at: points[10], time: 0.2)
        #expect(lastUp == [.activate(keys[10], landing: points[10]), .keyUp(keys[10])])
        events += lastUp
        for id in (0..<10).reversed() {
            let up = touches.touchUp(id, at: points[id], time: 0.3 - Double(id) * 0.01)
            #expect(up == [.keyUp(keys[id])])
            events += up
        }
        let typed = events.compactMap { event -> String? in
            if case .activate(let frame, _) = event { frame.key.label } else { nil }
        }
        #expect(typed == labels)
        #expect(touches.nextDeadline == nil)
    }

    @Test func framesReplacedMidTouchUseOriginalKey() throws {
        let a = try key("a"), pa = try center("a")
        #expect(touches.touchDown(1, at: pa, time: 0) == [.keyDown(a)])
        // The page changes under the held finger; another key now sits where a was.
        touches.frames = try Self.pageFrames("symbols-1")
        #expect(touches.touchUp(1, at: pa, time: 0.1) == [.activate(a, landing: pa), .keyUp(a)])
        // Any layout pass, even one with no frames at all, cancels a held key's coming long-press:
        // its popup would match no keys on screen, so the key types itself on lift.
        let d = try key("d"), pd = try center("d")
        touches.frames = frames
        #expect(touches.touchDown(2, at: pd, time: 1) == [.keyDown(d)])
        touches.frames = []
        #expect(touches.nextDeadline == nil)
        #expect(touches.advance(to: 1.5) == [])
        #expect(touches.touchUp(2, at: pd, time: 1.6) == [.activate(d, landing: pd), .keyUp(d)])
        // Holding space for cursor mode is not a long-press: it survives a layout pass.
        let space = try key("space"), pspace = try center("space")
        touches.frames = frames
        #expect(touches.touchDown(3, at: pspace, time: 2) == [.keyDown(space)])
        touches.frames = frames
        #expect(touches.advance(to: 2.33) == [.cursorModeBegan])
    }

    @Test func framesReplacedWhileChoosingTypeTheKey() throws {
        let d = try key("d"), pd = try center("d")
        #expect(touches.touchDown(1, at: pd, time: 0) == [.keyDown(d)])
        #expect(touches.advance(to: 0.3) == [.alternatesShown(d, options: ["₹", "$", "€"], selected: 0, originX: 100.5)])
        // New frames take the popup away: the finger goes back to its own key, with no long-press to come.
        touches.frames = try Self.pageFrames("symbols-1")
        #expect(touches.nextDeadline == nil)
        #expect(touches.touchMoved(1, to: Point(x: 157, y: 163), time: 0.4) == [])
        #expect(touches.advance(to: 1) == [])
        #expect(touches.touchUp(1, at: Point(x: 157, y: 163), time: 1.1) == [.activate(d, landing: pd), .keyUp(d)])
    }

    @Test func reusedTouchIDEndsTheEarlierTouch() throws {
        let a = try key("a"), s = try key("s"), d = try key("d")
        let pa = try center("a"), ps = try center("s"), pd = try center("d")
        #expect(touches.touchDown(1, at: pa, time: 0) == [.keyDown(a)])
        // Id 1 lands again without having lifted. Its lift was lost, so a is typed as if it had lifted.
        #expect(touches.touchDown(1, at: ps, time: 0.1) == [.activate(a, landing: pa), .keyUp(a), .keyDown(s)])
        #expect(touches.nextDeadline == 0.1 + 0.3)
        #expect(touches.touchUp(1, at: ps, time: 0.2) == [.activate(s, landing: ps), .keyUp(s)])
        // A stale touch choosing a long-press option types its selected option.
        #expect(touches.touchDown(2, at: pd, time: 1) == [.keyDown(d)])
        #expect(touches.advance(to: 1.5) == [.alternatesShown(d, options: ["₹", "$", "€"], selected: 0, originX: 100.5)])
        #expect(touches.touchDown(2, at: ps, time: 1.6) == [.activateAlternate(d, text: "₹"), .keyUp(d), .keyDown(s)])
        #expect(touches.touchUp(2, at: ps, time: 1.7) == [.activate(s, landing: ps), .keyUp(s)])
        #expect(touches.nextDeadline == nil)
    }
}
