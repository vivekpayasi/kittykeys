import Testing
import KeyboardCore

// Worked numbers at width 390 with standard metrics are in TouchTapTests and TouchHoldTests.
// Key ids are indexes into the current page's frames: on latin-qwerty the number row is 0-9 and q is 10;
// on symbols-1 id 10 is "@".

/// A controller over a fake document, laid out at width 390, with a clock the tests move by hand.
/// Like the host, it reports the field's traits once at the start.
@MainActor final class Harness {
    let doc: FakeTextDocument
    let feedback = RecordingFeedback()
    let controller: KeyboardController
    /// The time the next touch happens at.
    var now = 0.0
    /// How many times the controller called `onChange`.
    var changes = 0

    init(_ text: String = "", cursor: Int? = nil, autoCap: AutoCapMode = .none, settings: KeyboardSettings = KeyboardSettings()) throws {
        doc = FakeTextDocument(text, cursor: cursor)
        controller = KeyboardController(document: doc, layouts: try LayoutSet.bundled(), settings: settings, feedback: feedback)
        controller.setWidth(390)
        controller.fieldDidChange(FieldTraits(autoCap: autoCap))
        controller.onChange = { [unowned self] in self.changes += 1 }
    }

    func key(_ label: String) throws -> KeyFrame {
        try #require(controller.frames.first { $0.key.label == label })
    }

    /// Finger `id` lands on the centre of `label` at `now`. Returns where it landed.
    @discardableResult func down(_ label: String, id: TouchID = 1) throws -> Point {
        let rect = try key(label).rect
        let p = Point(x: rect.midX, y: rect.midY)
        controller.touchDown(id, at: p, time: now)
        return p
    }

    func move(to p: Point, id: TouchID = 1) {
        controller.touchMoved(id, to: p, time: now)
    }

    func up(at p: Point, id: TouchID = 1) {
        controller.touchUp(id, at: p, time: now)
    }

    /// Moves the clock on and fires the timers due by then.
    func wait(_ seconds: Double) {
        now += seconds
        controller.advance(to: now)
    }

    /// Taps `label`: down at its centre, up 0.1 s later. The next touch comes 0.1 s after the lift.
    func tap(_ label: String, id: TouchID = 1) throws {
        let p = try down(label, id: id)
        now += 0.1
        up(at: p, id: id)
        now += 0.1
    }
}

@MainActor struct ControllerTests {
    // MARK: Typing, shift and capitals

    @Test func typesLetters() throws {
        let k = try Harness()
        k.controller.fieldDidChange(FieldTraits(autoCap: .none))
        try k.tap("h")
        try k.tap("i")
        #expect(k.doc.text == "hi")
    }

    @Test func autoCapitalisesSentences() throws {
        let k = try Harness(autoCap: .sentences)
        #expect(k.controller.state.shift == .once)
        try k.tap("h")
        try k.tap("i")
        #expect(k.doc.text == "Hi" && k.controller.state.shift == .off)
        try k.tap(".")
        try k.tap("space")
        #expect(k.doc.text == "Hi. " && k.controller.state.shift == .once)
        try k.tap("o")
        #expect(k.doc.text == "Hi. O")
    }

    @Test func automaticCapitalGoesWhenItsReasonGoes() throws {
        let k = try Harness("Hi.", autoCap: .sentences)
        #expect(k.controller.state.shift == .off)
        try k.tap("space")
        #expect(k.controller.state.shift == .once)
        // Deleting the space after the full stop takes the automatic capital away.
        try k.tap("⌫")
        #expect(k.doc.text == "Hi." && k.controller.state.shift == .off)
        // A change the controller didn't make counts once the host reports it.
        k.doc.insert(" ")
        k.controller.documentDidChange()
        #expect(k.controller.state.shift == .once)
    }

    @Test func shiftOnceAndCapsLock() throws {
        let k = try Harness()
        try k.tap("⇧")
        #expect(k.controller.state.shift == .once)
        try k.tap("a")
        try k.tap("b")
        #expect(k.doc.text == "Ab" && k.controller.state.shift == .off)
        // Shift acts on touch-down, so taps 0.2 s apart fall in the 0.3 s double-tap window.
        try k.tap("⇧")
        try k.tap("⇧")
        #expect(k.controller.state.shift == .locked)
        try k.tap("a")
        try k.tap("b")
        #expect(k.doc.text == "AbAB" && k.controller.state.shift == .locked)
        try k.tap("⇧")
        #expect(k.controller.state.shift == .off)
    }

    @Test func keyBetweenShiftTapsIsNoDoubleTap() throws {
        // Shift, o, shift all within 0.3 s: the o comes between, so the second tap is a first tap, not caps lock.
        let k = try Harness()
        let pShift = try k.down("⇧")
        k.now = 0.03
        k.up(at: pShift)
        k.now = 0.06
        let po = try k.down("o")
        k.now = 0.1
        k.up(at: po)
        k.now = 0.2
        try k.down("⇧")
        #expect(k.doc.text == "O" && k.controller.state.shift == .once)
    }

    @Test func slowSecondShiftTapTurnsShiftOff() throws {
        let k = try Harness()
        try k.tap("⇧")
        k.wait(0.2)
        // 0.4 s after the first tap: too slow for caps lock.
        try k.tap("⇧")
        #expect(k.controller.state.shift == .off)
    }

    @Test func doubleTapGivesCapsLockAtSentenceStart() throws {
        // Shift is on by itself at a sentence start. The first tap turns it off; the second, 0.2 s later, locks caps.
        let k = try Harness(autoCap: .sentences)
        #expect(k.controller.state.shift == .once)
        try k.tap("⇧")
        #expect(k.controller.state.shift == .off)
        try k.tap("⇧")
        #expect(k.controller.state.shift == .locked)
        try k.tap("a")
        try k.tap("b")
        #expect(k.doc.text == "AB" && k.controller.state.shift == .locked)
        // Automatic capitals leave caps lock alone.
        for label in [".", "space", "c"] { try k.tap(label) }
        #expect(k.doc.text == "AB. C" && k.controller.state.shift == .locked)
    }

    @Test func shiftLeavesLongerOutputsAsWritten() throws {
        let k = try Harness()
        k.controller.fieldDidChange(FieldTraits(kind: .url, autoCap: .none))
        try k.tap("⇧")
        try k.tap("⇧")
        #expect(k.controller.state.shift == .locked)
        try k.tap(".com")
        try k.tap("a")
        #expect(k.doc.text == ".comA" && k.controller.state.shift == .locked)
    }

    // MARK: Double-space full stop

    @Test func doubleSpaceFullStop() throws {
        let k = try Harness("hi")
        try k.tap("space")
        try k.tap("space")
        #expect(k.doc.text == "hi. ")
        // A third space is just a space.
        try k.tap("space")
        #expect(k.doc.text == "hi.  ")

        let off = try Harness("hi")
        off.controller.settings.doubleSpacePeriod = false
        try off.tap("space")
        try off.tap("space")
        #expect(off.doc.text == "hi  ")
    }

    @Test func doubleSpaceNeedsLetterBefore() throws {
        let k = try Harness("hi.")
        try k.tap("space")
        try k.tap("space")
        #expect(k.doc.text == "hi.  ")
    }

    @Test func doubleSpaceNeedsTwoSpacesInAQuickRow() throws {
        let slow = try Harness("hi")
        try slow.tap("space")
        slow.wait(0.4)
        // Typed 0.6 s after the first space.
        try slow.tap("space")
        #expect(slow.doc.text == "hi  ")

        // Shift between the spaces: the second space comes 0.4 s after the first, but the key before it was shift.
        let between = try Harness("hi")
        try between.tap("space")
        try between.tap("⇧")
        try between.tap("space")
        #expect(between.doc.text == "hi  ")
    }

    @Test func doubleSpaceNeedsTheCursorWhereTheSpaceLeftIt() throws {
        let k = try Harness("ok ")
        for label in ["h", "i", "space"] { try k.tap(label) }
        #expect(k.doc.text == "ok hi ")
        // Something else moves the cursor back to just after "ok ": a quick space there is just a space.
        k.doc.moveCursor(by: -3)
        k.controller.documentDidChange()
        try k.tap("space")
        #expect(k.doc.text == "ok  hi ")
    }

    // MARK: Long-press popup

    @Test func longPressTypesSymbolAndUsesShift() throws {
        let k = try Harness()
        try k.tap("⇧")
        let d = try k.key("d")
        let p = try k.down("d")
        k.wait(0.4)
        let popup = try #require(k.controller.state.alternates)
        #expect(popup.keyID == d.id && popup.options == ["₹", "$", "€"] && popup.selected == 0 && popup.originX == 100.5)
        k.up(at: p)
        #expect(k.doc.text == "₹" && k.controller.state.shift == .off && k.controller.state.alternates == nil)
    }

    @Test func popupShowsOptionsInDisplayOrder() throws {
        let k = try Harness()
        let period = try k.key(".")
        let p = try k.down(".")
        k.wait(0.3)
        // "."'s options run leftward from its right edge, so its default is the last cell (see TouchTapTests).
        let popup = try #require(k.controller.state.alternates)
        #expect(popup.keyID == period.id && popup.options == ["/", ":", "…", "!", "?", "."])
        #expect(popup.selected == 5 && popup.originX == 93)
        let onQuestionMark = Point(x: 256.5, y: p.y)
        k.move(to: onQuestionMark)
        #expect(k.controller.state.alternates?.selected == 4)
        // Another finger's key going up leaves the popup alone.
        try k.tap("s", id: 2)
        #expect(k.doc.text == "s" && k.controller.state.alternates?.selected == 4)
        k.up(at: onQuestionMark)
        #expect(k.doc.text == "s?" && k.controller.state.alternates == nil)
    }

    @Test func longPressDelayComesFromSettings() throws {
        var settings = KeyboardSettings()
        settings.longPressDelay = 0.4
        let k = try Harness(settings: settings)
        let p = try k.down("d")
        #expect(k.controller.nextDeadline == 0.4)
        k.up(at: p)
        k.controller.settings.longPressDelay = 0.5
        k.now = 1
        try k.down("d")
        #expect(k.controller.nextDeadline == 1.5)
        k.wait(0.4)
        #expect(k.controller.state.alternates == nil)
        k.wait(0.1)
        #expect(k.controller.state.alternates?.options == ["₹", "$", "€"])
    }

    @Test func popupStaysWhileItsFingerChooses() throws {
        // A second finger taps d while the first chooses from d's popup: the popup stays with the first finger.
        let k = try Harness()
        let d = try k.key("d")
        let p = try k.down("d", id: 1)
        k.wait(0.3)
        try k.tap("d", id: 2)
        #expect(k.doc.text == "d" && k.controller.state.alternates?.keyID == d.id)
        k.move(to: Point(x: 157, y: p.y), id: 1)
        #expect(k.controller.state.alternates?.selected == 1)
        k.now += 0.1
        k.up(at: Point(x: 157, y: p.y), id: 1)
        #expect(k.doc.text == "d$" && k.controller.state.alternates == nil && k.controller.state.pressedKeyIDs.isEmpty)
    }

    @Test func popupClosesWhenItsKeyLifts() throws {
        // A second finger holds d too. The popup's finger is cancelled: the popup goes, the highlight stays.
        let k = try Harness()
        let d = try k.key("d")
        let p = try k.down("d", id: 1)
        k.wait(0.3)
        try k.down("d", id: 2)
        #expect(k.controller.state.alternates?.keyID == d.id)
        k.controller.touchCancelled(1)
        #expect(k.controller.state.alternates == nil && k.controller.state.pressedKeyIDs == [d.id])
        k.now += 0.1
        k.up(at: p, id: 2)
        #expect(k.doc.text == "d" && k.controller.state.pressedKeyIDs.isEmpty)
    }

    @Test func widthChangeCancelsAComingLongPress() throws {
        let k = try Harness()
        let p = try k.down("d")
        k.wait(0.1)
        k.controller.setWidth(375)
        k.wait(0.9)
        #expect(k.controller.state.alternates == nil)
        k.up(at: p)
        #expect(k.doc.text == "d")
    }

    @Test func widthChangeDuringLongPressTypesTheKey() throws {
        let k = try Harness()
        let p = try k.down("d")
        k.wait(0.3)
        #expect(k.controller.state.alternates != nil)
        k.controller.setWidth(375)
        #expect(k.controller.state.alternates == nil)
        k.now += 0.1
        k.up(at: p)
        #expect(k.doc.text == "d")
    }

    // MARK: Pages and fields

    @Test func pagesSwitch() throws {
        let k = try Harness()
        try k.tap("123")
        #expect(k.controller.state.pageID == "symbols-1" && k.controller.frames.contains { $0.key.label == "1/2" })
        try k.tap("1/2")
        #expect(k.controller.state.pageID == "symbols-2")
        try k.tap("2/2")
        #expect(k.controller.state.pageID == "symbols-1")
        try k.tap("ABC")
        #expect(k.controller.state.pageID == "latin-qwerty" && k.controller.state.pressedKeyIDs.isEmpty)
        #expect(k.doc.text == "")
    }

    @Test func fieldVariantsAndReturnKey() throws {
        let k = try Harness()
        func labels() -> [String] { k.controller.frames.map(\.key.label) }
        k.controller.fieldDidChange(FieldTraits(kind: .email))
        #expect(labels().contains("@"))
        k.controller.fieldDidChange(FieldTraits(kind: .url))
        #expect(labels().contains("/") && labels().contains(".com"))
        k.controller.fieldDidChange(FieldTraits(kind: .number))
        #expect(k.controller.state.pageID == "symbols-1")
        k.controller.fieldDidChange(FieldTraits(returnKey: .send))
        #expect(k.controller.state.returnKey == .send)
        #expect(k.controller.state.pageID == "latin-qwerty" && labels().contains(",") && !labels().contains("@"))
        try k.tap("return")
        #expect(k.doc.text == "\n")
    }

    @Test func sameTraitsKeepThePage() throws {
        // iOS reports the traits after every text change: the same traits again must not leave the symbols page.
        let k = try Harness()
        try k.tap("123")
        k.controller.fieldDidChange(FieldTraits(autoCap: .none))
        #expect(k.controller.state.pageID == "symbols-1")
        k.controller.fieldDidChange(FieldTraits(autoCap: .none, returnKey: .go))
        #expect(k.controller.state.pageID == "latin-qwerty" && k.controller.state.returnKey == .go)

        // The same traits still re-check automatic capitals.
        let s = try Harness("Hi.", autoCap: .sentences)
        s.doc.insert(" ")
        s.controller.fieldDidChange(FieldTraits(autoCap: .sentences))
        #expect(s.controller.state.shift == .once)
    }

    @Test func keyboardWillAppearStartsAfresh() throws {
        let k = try Harness()
        let text = FieldTraits(autoCap: .none)
        try k.tap("123")
        try k.tap("1/2")
        #expect(k.controller.state.pageID == "symbols-2")
        // The same traits as before, yet the keyboard opens on letters.
        k.controller.keyboardWillAppear(text)
        #expect(k.controller.state.pageID == "latin-qwerty")
        // The traits count as reported: the same ones again leave the page alone.
        try k.tap("123")
        k.controller.fieldDidChange(text)
        #expect(k.controller.state.pageID == "symbols-1")

        // Caps lock goes, and the shift taps before it are forgotten: a tap 0.2 s after the last one is a first tap.
        let shift = try Harness()
        try shift.tap("⇧")
        try shift.tap("⇧")
        #expect(shift.controller.state.shift == .locked)
        shift.controller.keyboardWillAppear(text)
        #expect(shift.controller.state.shift == .off)
        try shift.tap("⇧")
        #expect(shift.controller.state.shift == .once)

        // A space typed before doesn't pair with one typed after.
        let space = try Harness("hi")
        try space.tap("space")
        space.controller.keyboardWillAppear(text)
        try space.tap("space")
        #expect(space.doc.text == "hi  ")
    }

    @Test func globeKeyAppearsWhenNeeded() throws {
        let k = try Harness()
        var globes = 0
        k.controller.onGlobe = { globes += 1 }
        func bottomRow() -> [KeyAction] {
            let frames = k.controller.frames
            return frames.filter { $0.row == frames.last?.row }.map(\.key.action)
        }
        #expect(!bottomRow().contains(.globe))
        k.controller.needsGlobeKey = true
        #expect(bottomRow() == [.switchPage(.named("symbols-1")), .globe, .emoji, .character, .space, .character, .returnKey])
        try k.tap("🌐")
        #expect(globes == 1 && k.doc.text == "")
        // The emoji key does nothing yet.
        try k.tap("😊")
        #expect(globes == 1 && k.doc.text == "")
        k.controller.needsGlobeKey = false
        #expect(!bottomRow().contains(.globe))
    }

    // MARK: Backspace

    @Test func wordDeleteRemovesEmojiAsOneUnit() throws {
        // The touch-down delete takes the whole emoji. The swipe then finds that word finished and deletes nothing more.
        let k = try Harness("hi 👍🏽")
        let p = try k.down("⌫")
        #expect(k.doc.text == "hi ")
        k.wait(0.05)
        let swiped = Point(x: p.x - 25, y: p.y)
        k.move(to: swiped)
        k.wait(0.05)
        k.up(at: swiped)
        #expect(k.doc.text == "hi ")
    }

    @Test func backspaceSwipeFinishesTheWord() throws {
        let k = try Harness("hi there")
        let p = try k.down("⌫")
        #expect(k.doc.text == "hi ther")
        k.wait(0.05)
        k.move(to: Point(x: p.x - 25, y: p.y))
        #expect(k.doc.text == "hi ")
    }

    @Test func heldBackspaceDeletesWholeWords() throws {
        // "hi 👍🏽 ok" and 17 more characters: the touch-down delete and the 16 repeats up to 1.45 s take one each.
        let k = try Harness("hi 👍🏽 ok see you tomorrow")
        let p = try k.down("⌫")
        k.wait(1.45)
        #expect(k.doc.text == "hi 👍🏽 ok")
        // At 1.5 s backspace deletes whole words: "ok" goes at once,
        k.wait(0.05)
        #expect(k.doc.text == "hi 👍🏽 ")
        // then the space and the emoji.
        k.wait(0.2)
        #expect(k.doc.text == "hi ")
        k.up(at: p)
    }

    // MARK: Cursor mode

    @Test func cursorModeMovesAndTicks() throws {
        let k = try Harness("abcdef", cursor: 3)
        let p = try k.down("space")
        k.wait(0.33)
        #expect(k.controller.state.cursorMode)
        // 18 pt in 0.67 s is slow: one character per 9 pt.
        k.now += 0.67
        k.move(to: Point(x: p.x + 18, y: p.y))
        #expect(k.doc.cursor == 5 && k.feedback.cursorTicks == 2 && k.controller.state.cursorMode)
        k.up(at: Point(x: p.x + 18, y: p.y))
        #expect(!k.controller.state.cursorMode && k.doc.text == "abcdef" && k.doc.cursor == 5)
    }

    @Test func cursorModeMovesLines() throws {
        // The cursor is at the end of "cd"; one line up at the same column is the end of "ab".
        let k = try Harness("ab\ncd")
        let p = try k.down("space")
        k.wait(0.33)
        k.now += 0.5
        k.move(to: Point(x: p.x, y: p.y - 30))
        #expect(k.doc.cursor == 2 && k.feedback.cursorTicks == 1)
    }

    @Test func cursorModeEndChecksCapitals() throws {
        // Moving the cursor back to just after "Hi. " puts it at the start of a sentence.
        let k = try Harness("Hi. ok", autoCap: .sentences)
        #expect(k.controller.state.shift == .off)
        let p = try k.down("space")
        k.wait(0.33)
        k.now += 0.67
        k.move(to: Point(x: p.x - 18, y: p.y))
        k.up(at: Point(x: p.x - 18, y: p.y))
        #expect(k.doc.cursor == 4 && k.controller.state.shift == .once)
    }

    // MARK: Highlights, preview and feedback

    @Test func previewOnlyForCharacterKeys() throws {
        let k = try Harness()
        let a = try k.key("a"), shift = try k.key("⇧")
        let pa = try k.down("a")
        #expect(k.controller.state.previewKeyID == a.id && k.controller.state.pressedKeyIDs == [a.id])
        k.up(at: pa)
        #expect(k.controller.state.previewKeyID == nil && k.controller.state.pressedKeyIDs.isEmpty)
        let ps = try k.down("⇧")
        #expect(k.controller.state.previewKeyID == nil && k.controller.state.pressedKeyIDs == [shift.id])
        k.up(at: ps)
        try k.down("a")
        #expect(k.controller.state.previewKeyID == a.id)
        // Turning key popups off hides the preview showing now and every later one.
        k.controller.settings.keyPopup = false
        #expect(k.controller.state.previewKeyID == nil)
        k.up(at: pa)
        try k.down("a")
        #expect(k.controller.state.previewKeyID == nil && k.controller.state.pressedKeyIDs == [a.id])
    }

    @Test func keyDownGivesFeedback() throws {
        let k = try Harness()
        try k.tap("a")
        #expect(k.feedback.keyDowns == 1 && k.feedback.cursorTicks == 0)
    }

    @Test func twoFingersOnOneKeyKeepItPressed() throws {
        let k = try Harness()
        let a = try k.key("a")
        let p = try k.down("a", id: 1)
        // The second finger types the first one's a (rollover); both hold the key.
        try k.down("a", id: 2)
        #expect(k.doc.text == "a" && k.controller.state.pressedKeyIDs == [a.id])
        k.up(at: p, id: 1)
        #expect(k.controller.state.pressedKeyIDs == [a.id] && k.controller.state.previewKeyID == a.id)
        k.up(at: p, id: 2)
        #expect(k.doc.text == "aa" && k.controller.state.pressedKeyIDs.isEmpty && k.controller.state.previewKeyID == nil)
    }

    @Test func pageSwitchLeavesNoStaleHighlight() throws {
        let k = try Harness()
        let q = try k.key("q")
        let pq = try k.down("q", id: 1)
        k.now += 0.05
        // 123 types the held q, then opens symbols-1. Its own highlight goes with the old page.
        let p123 = try k.down("123", id: 2)
        #expect(k.doc.text == "q" && k.controller.state.pageID == "symbols-1" && k.controller.state.pressedKeyIDs.isEmpty)
        let at = try k.key("@")
        #expect(at.id == q.id)
        k.now += 0.05
        let pAt = try k.down("@", id: 3)
        #expect(k.controller.state.pressedKeyIDs == [at.id] && k.controller.state.previewKeyID == at.id)
        // q and 123 lift with frames from the old page; "@" shares q's id but stays highlighted.
        k.now += 0.05
        k.up(at: pq, id: 1)
        k.up(at: p123, id: 2)
        #expect(k.controller.state.pressedKeyIDs == [at.id] && k.controller.state.previewKeyID == at.id)
        k.up(at: pAt, id: 3)
        #expect(k.doc.text == "q@" && k.controller.state.pressedKeyIDs.isEmpty && k.controller.state.previewKeyID == nil)
    }

    @Test func pageSwitchClosesThePopup() throws {
        let k = try Harness()
        let pd = try k.down("d", id: 1)
        k.wait(0.3)
        #expect(k.controller.state.alternates != nil)
        try k.down("123", id: 2)
        #expect(k.controller.state.pageID == "symbols-1" && k.controller.state.alternates == nil)
        // With its popup gone, the finger types its own key.
        k.now += 0.1
        k.up(at: pd, id: 1)
        #expect(k.doc.text == "d" && k.controller.state.alternates == nil)
    }

    @Test func cancelledTouchesLeaveNothingBehind() throws {
        // The system takes the touches away, as for an incoming call: nothing typed, no highlight, popup or cursor mode.
        let k = try Harness("ab")
        try k.down("d", id: 1)
        k.wait(0.3)
        #expect(k.controller.state.alternates != nil && k.controller.state.previewKeyID != nil)
        k.controller.touchCancelled(1)
        #expect(k.controller.state.alternates == nil && k.controller.state.previewKeyID == nil)
        #expect(k.controller.state.pressedKeyIDs.isEmpty && k.controller.nextDeadline == nil)
        try k.down("space", id: 2)
        k.wait(0.33)
        #expect(k.controller.state.cursorMode)
        k.controller.touchCancelled(2)
        #expect(!k.controller.state.cursorMode && k.controller.state.pressedKeyIDs.isEmpty && k.doc.text == "ab")
    }

    // MARK: Width, height and change notices

    @Test func framesFollowTheWidth() throws {
        let doc = FakeTextDocument("")
        let controller = KeyboardController(
            document: doc, layouts: try LayoutSet.bundled(), settings: KeyboardSettings(), feedback: RecordingFeedback())
        controller.fieldDidChange(FieldTraits(autoCap: .none))
        // No keys until the width is known, so touches do nothing.
        #expect(controller.frames.isEmpty && controller.height == 292)
        controller.touchDown(1, at: Point(x: 39, y: 163), time: 0)
        controller.touchUp(1, at: Point(x: 39, y: 163), time: 0.1)
        #expect(doc.text == "" && controller.state.pressedKeyIDs.isEmpty)

        controller.setWidth(390)
        // 10 + 10 + 9 + 9 keys and a bottom row of 6.
        #expect(controller.frames.count == 44 && controller.frames.last?.rect.maxX == 387)
        let a = try #require(controller.frames.first { $0.key.label == "a" })
        controller.touchDown(2, at: Point(x: a.rect.midX, y: a.rect.midY), time: 1)
        #expect(controller.state.pressedKeyIDs == [a.id])
        // A new width lays the keys out again and drops the highlight of the old layout; the held key still types.
        controller.setWidth(375)
        #expect(controller.frames.count == 44 && controller.frames.last?.rect.maxX == 372)
        #expect(controller.state.pressedKeyIDs.isEmpty && controller.state.previewKeyID == nil)
        controller.touchUp(2, at: Point(x: a.rect.midX, y: a.rect.midY), time: 1.1)
        #expect(doc.text == "a" && controller.state.pressedKeyIDs.isEmpty)
    }

    @Test func onChangeFiresOncePerChangingCall() throws {
        let k = try Harness()
        let p = try k.down("a")
        #expect(k.changes == 1)
        k.now += 0.05
        k.move(to: Point(x: p.x + 5, y: p.y))
        #expect(k.changes == 1)
        k.up(at: p)
        #expect(k.changes == 2)
        k.controller.documentDidChange()
        k.controller.setWidth(390)
        #expect(k.changes == 2)
        k.controller.setWidth(375)
        #expect(k.changes == 3)
        // Key down and the page switch in one call: one notice.
        k.now += 0.2
        try k.down("123")
        #expect(k.changes == 4)
        k.controller.needsGlobeKey = true
        #expect(k.changes == 5)
    }
}
