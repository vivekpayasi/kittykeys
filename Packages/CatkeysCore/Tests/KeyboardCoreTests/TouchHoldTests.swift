import Testing
import KeyboardCore

// Worked numbers at width 390 with standard metrics (see TouchTapTests and GeometryTests):
// ⌫ is 334.5...387 on the z-m row (y 194...236), centre (360.75, 215).
// space is 139.5...270 on the bottom row (y 246...288), centre (204.75, 267).
// Backspace repeats: characters at 0.4, 0.47, 0.54 … 1.45 (16 of them), then words at 1.5, 1.7, 1.9 …
// Cursor mode: 9 pt per character (×3 above 300 pt/s), 30 pt per line, measured from an anchor that
// moves only by the distance each step used.

struct TouchHoldTests {
    let frames: [KeyFrame]
    let touches = TouchProcessor()

    init() throws {
        frames = try TouchTapTests.pageFrames("latin-qwerty")
        touches.frames = frames
        touches.keyboardWidth = 390
    }

    func key(_ label: String) throws -> KeyFrame {
        try #require(frames.first { $0.key.label == label })
    }

    func center(_ label: String) throws -> Point {
        let rect = try key(label).rect
        return Point(x: rect.midX, y: rect.midY)
    }

    /// Holds space at its centre from t = 0 until cursor mode begins at 0.33.
    func enterCursorMode() throws {
        let space = try key("space")
        #expect(touches.touchDown(1, at: try center("space"), time: 0) == [.keyDown(space)])
        #expect(touches.advance(to: 0.33) == [.cursorModeBegan])
    }

    // MARK: Backspace

    @Test func backspaceRepeatsThenDeletesWords() throws {
        let b = try key("⌫"), pb = try center("⌫")
        #expect(b.key.action == .backspace && pb == Point(x: 360.75, y: 215))
        #expect(touches.touchDown(1, at: pb, time: 0) == [.keyDown(b), .deleteBackward(word: false)])
        #expect(touches.advance(to: 0.39) == [])
        #expect(touches.advance(to: 0.4) == [.deleteBackward(word: false)])
        #expect(touches.advance(to: 0.47) == [.deleteBackward(word: false)])
        // 0.54 … 1.45 are fourteen more character repeats; at 1.5 s it switches to words.
        #expect(touches.advance(to: 1.5)
            == Array(repeating: .deleteBackward(word: false), count: 14) + [.deleteBackward(word: true)])
        #expect(touches.advance(to: 1.69) == [])
        #expect(touches.advance(to: 1.7) == [.deleteBackward(word: true)])
        #expect(touches.nextDeadline == 1.9)
        #expect(touches.touchUp(1, at: pb, time: 1.8) == [.keyUp(b)])
        #expect(touches.nextDeadline == nil)
        #expect(touches.advance(to: 5) == [])
    }

    @Test func backspaceSwipeDeletesRestOfWord() throws {
        let b = try key("⌫"), pb = try center("⌫")
        #expect(touches.touchDown(1, at: pb, time: 0) == [.keyDown(b), .deleteBackward(word: false)])
        // 15 pt left, or any distance up or down, is not a swipe.
        #expect(touches.touchMoved(1, to: Point(x: 345.75, y: 190), time: 0.05) == [])
        // 25 pt left of where it landed: the rest of the word goes and the repeats stop.
        #expect(touches.touchMoved(1, to: Point(x: 335.75, y: 215), time: 0.1) == [.deleteRestOfWord])
        #expect(touches.nextDeadline == nil)
        #expect(touches.touchMoved(1, to: Point(x: 300.75, y: 215), time: 0.2) == [])
        #expect(touches.advance(to: 2.0) == [])
        #expect(touches.touchUp(1, at: Point(x: 300.75, y: 215), time: 2.1) == [.keyUp(b)])
    }

    @Test func backspaceSwipeOfExactlyTwentyPoints() throws {
        let b = try key("⌫"), pb = try center("⌫")
        #expect(touches.touchDown(1, at: pb, time: 0) == [.keyDown(b), .deleteBackward(word: false)])
        // 19.75 pt left is short of the swipe; exactly 20 pt is one.
        #expect(touches.touchMoved(1, to: Point(x: 341, y: 215), time: 0.05) == [])
        #expect(touches.touchMoved(1, to: Point(x: 340.75, y: 215), time: 0.1) == [.deleteRestOfWord])
        #expect(touches.nextDeadline == nil)
        #expect(touches.touchUp(1, at: Point(x: 340.75, y: 215), time: 0.2) == [.keyUp(b)])
    }

    @Test func backspaceSwipeWhileRepeatingCharacters() throws {
        let b = try key("⌫"), pb = try center("⌫")
        #expect(touches.touchDown(1, at: pb, time: 0) == [.keyDown(b), .deleteBackward(word: false)])
        #expect(touches.advance(to: 0.6) == Array(repeating: .deleteBackward(word: false), count: 3))   // 0.4, 0.47, 0.54
        #expect(touches.touchMoved(1, to: Point(x: 335.75, y: 215), time: 0.6) == [.deleteRestOfWord])
        #expect(touches.nextDeadline == nil)
        #expect(touches.touchMoved(1, to: Point(x: 300.75, y: 215), time: 0.7) == [])
        #expect(touches.advance(to: 3) == [])
        #expect(touches.touchUp(1, at: Point(x: 300.75, y: 215), time: 3.1) == [.keyUp(b)])
    }

    @Test func backspaceSwipeWhileRepeatingWords() throws {
        let b = try key("⌫"), pb = try center("⌫")
        #expect(touches.touchDown(1, at: pb, time: 0) == [.keyDown(b), .deleteBackward(word: false)])
        // Sixteen character repeats (0.4 … 1.45), then the first word at 1.5.
        #expect(touches.advance(to: 1.6)
            == Array(repeating: .deleteBackward(word: false), count: 16) + [.deleteBackward(word: true)])
        #expect(touches.touchMoved(1, to: Point(x: 335.75, y: 215), time: 1.6) == [.deleteRestOfWord])
        #expect(touches.nextDeadline == nil)
        #expect(touches.touchMoved(1, to: Point(x: 300.75, y: 215), time: 1.7) == [])
        #expect(touches.advance(to: 3) == [])
        #expect(touches.touchUp(1, at: Point(x: 300.75, y: 215), time: 3.1) == [.keyUp(b)])
    }

    @Test func backspaceTypesHeldKeyFirstAndKeepsRepeating() throws {
        let a = try key("a"), b = try key("⌫"), five = try key("5")
        let pa = try center("a"), pb = try center("⌫"), p5 = try center("5")
        #expect(touches.touchDown(1, at: pa, time: 0) == [.keyDown(a)])
        // Backspace landing is a new touch-down: the held a is typed before anything is deleted.
        #expect(touches.touchDown(2, at: pb, time: 0.05) == [.activate(a, landing: pa), .keyDown(b), .deleteBackward(word: false)])
        // A key landing while backspace is held doesn't stop or type backspace.
        #expect(touches.touchDown(3, at: p5, time: 0.1) == [.keyDown(five)])
        #expect(touches.nextDeadline == 0.05 + 0.4)
        #expect(touches.advance(to: 0.45) == [.deleteBackward(word: false)])
        #expect(touches.touchUp(3, at: p5, time: 0.5) == [.activate(five, landing: p5), .keyUp(five)])
        #expect(touches.advance(to: 0.52) == [.deleteBackward(word: false)])
        #expect(touches.touchUp(2, at: pb, time: 0.55) == [.keyUp(b)])
        #expect(touches.touchUp(1, at: pa, time: 0.6) == [.keyUp(a)])
        #expect(touches.nextDeadline == nil)
    }

    @Test func cancelStopsBackspaceRepeat() throws {
        let b = try key("⌫"), pb = try center("⌫")
        #expect(touches.touchDown(1, at: pb, time: 0) == [.keyDown(b), .deleteBackward(word: false)])
        #expect(touches.advance(to: 0.4) == [.deleteBackward(word: false)])
        #expect(touches.touchCancelled(1) == [.keyUp(b)])
        #expect(touches.nextDeadline == nil)
        #expect(touches.advance(to: 5) == [])
        #expect(touches.touchUp(1, at: pb, time: 5.1) == [])
    }

    @Test func timersOfDifferentTouchesFireInDeadlineOrder() throws {
        let b = try key("⌫"), d = try key("d"), pb = try center("⌫"), pd = try center("d")
        // Backspace is due at 0.4 and 0.47; d, landing later, shows its options at 0.12 + 0.3 = 0.42, between them.
        #expect(touches.touchDown(1, at: pb, time: 0) == [.keyDown(b), .deleteBackward(word: false)])
        #expect(touches.touchDown(2, at: pd, time: 0.12) == [.keyDown(d)])
        #expect(touches.nextDeadline == 0.4)
        #expect(touches.advance(to: 0.5) == [
            .deleteBackward(word: false),
            .alternatesShown(d, options: ["₹", "$", "€"], selected: 0, originX: 100.5),
            .deleteBackward(word: false),
        ])
        #expect(touches.touchUp(2, at: pd, time: 0.52) == [.activateAlternate(d, text: "₹"), .keyUp(d)])
        #expect(touches.touchUp(1, at: pb, time: 0.53) == [.keyUp(b)])
        #expect(touches.nextDeadline == nil)
    }

    // MARK: Space

    @Test func spaceTapTypesSpace() throws {
        let space = try key("space"), ps = try center("space")
        #expect(space.key.action == .space && ps == Point(x: 204.75, y: 267))
        #expect(touches.touchDown(1, at: ps, time: 0) == [.keyDown(space)])
        #expect(touches.nextDeadline == 0.33)
        #expect(touches.touchUp(1, at: ps, time: 0.2) == [.activate(space, landing: ps), .keyUp(space)])
        #expect(touches.nextDeadline == nil)
        #expect(touches.advance(to: 1) == [])
    }

    @Test func spaceHoldTypesASpaceWithoutCursorMode() throws {
        // Emoji search turns cursor mode off: held space has no timer, and its lift types it.
        let space = try key("space"), ps = try center("space")
        touches.allowsCursorMode = false
        #expect(touches.touchDown(1, at: ps, time: 0) == [.keyDown(space)])
        #expect(touches.nextDeadline == nil && touches.advance(to: 1) == [])
        #expect(touches.touchUp(1, at: ps, time: 1) == [.activate(space, landing: ps), .keyUp(space)])
        // Turning it off also cancels a hold under way.
        touches.allowsCursorMode = true
        #expect(touches.touchDown(1, at: ps, time: 2) == [.keyDown(space)])
        #expect(touches.nextDeadline == 2.33)
        touches.allowsCursorMode = false
        #expect(touches.nextDeadline == nil && touches.advance(to: 3) == [])
        #expect(touches.touchUp(1, at: ps, time: 3) == [.activate(space, landing: ps), .keyUp(space)])
        // On again, the next hold starts cursor mode.
        touches.allowsCursorMode = true
        #expect(touches.touchDown(1, at: ps, time: 4) == [.keyDown(space)])
        #expect(touches.advance(to: 4.33) == [.cursorModeBegan])
    }

    @Test func spaceHoldEntersCursorMode() throws {
        let space = try key("space")
        #expect(touches.touchDown(1, at: try center("space"), time: 0) == [.keyDown(space)])
        #expect(touches.advance(to: 0.32) == [])
        #expect(touches.advance(to: 0.33) == [.cursorModeBegan])
        #expect(touches.nextDeadline == nil)
        // 9 pt right in 0.1 s (90 pt/s): one character.
        #expect(touches.touchMoved(1, to: Point(x: 213.75, y: 267), time: 0.43) == [.cursorMoved(characters: 1)])
        // 30 pt right in 0.05 s (600 pt/s, fast): three whole steps of 9, each moving three characters.
        #expect(touches.touchMoved(1, to: Point(x: 243.75, y: 267), time: 0.48) == [.cursorMoved(characters: 9)])
        // 30 pt up: one line up. The 3 pt left over from the last step is no whole character.
        #expect(touches.touchMoved(1, to: Point(x: 243.75, y: 237), time: 0.6) == [.cursorMovedLines(-1)])
        // Lifting ends cursor mode and types no space.
        #expect(touches.touchUp(1, at: Point(x: 243.75, y: 237), time: 0.7) == [.cursorModeEnded, .keyUp(space)])
        #expect(touches.nextDeadline == nil)
    }

    @Test func cursorStepsCarryTheirRemainder() throws {
        let space = try key("space")
        #expect(touches.touchDown(1, at: try center("space"), time: 0) == [.keyDown(space)])
        // The finger drifts 6 pt right during the hold; cursor mode measures from where it is when it begins.
        #expect(touches.touchMoved(1, to: Point(x: 210.75, y: 267), time: 0.2) == [])
        #expect(touches.advance(to: 0.33) == [.cursorModeBegan])
        // 9 pt left of x 210.75 (3 pt left of the landing point): one character back.
        #expect(touches.touchMoved(1, to: Point(x: 201.75, y: 267), time: 0.5) == [.cursorMoved(characters: -1)])
        // 4 pt left is no whole step, but it carries: 6 pt more makes 10, one step, and 1 pt is left over.
        #expect(touches.touchMoved(1, to: Point(x: 197.75, y: 267), time: 0.7) == [])
        #expect(touches.touchMoved(1, to: Point(x: 191.75, y: 267), time: 0.9) == [.cursorMoved(characters: -1)])
        // One move both ways: 13 pt left rounds toward zero to one character, 30 pt down is a line down.
        // The horizontal step comes first.
        #expect(touches.touchMoved(1, to: Point(x: 179.75, y: 297), time: 1.1)
            == [.cursorMoved(characters: -1), .cursorMovedLines(1)])
        // A move reported at the same time as the last one counts as fast.
        #expect(touches.touchMoved(1, to: Point(x: 174.75, y: 297), time: 1.1) == [.cursorMoved(characters: -3)])
        #expect(touches.touchUp(1, at: Point(x: 174.75, y: 297), time: 1.2) == [.cursorModeEnded, .keyUp(space)])
    }

    @Test func otherTouchesIgnoredInCursorMode() throws {
        let a = try key("a"), pa = try center("a"), pb = try center("⌫")
        try enterCursorMode()
        // The whole keyboard is the trackpad: other fingers type, delete and highlight nothing.
        #expect(touches.touchDown(2, at: pa, time: 0.4) == [])
        #expect(touches.touchDown(3, at: pb, time: 0.45) == [])
        #expect(touches.nextDeadline == nil)
        #expect(touches.advance(to: 2) == [])
        #expect(touches.touchMoved(2, to: try center("s"), time: 2.1) == [])
        #expect(touches.touchMoved(3, to: Point(x: 300.75, y: 215), time: 2.1) == [])
        #expect(touches.touchUp(2, at: pa, time: 2.2) == [])
        #expect(touches.touchCancelled(3) == [])
        // Space still moves the cursor, and was never typed.
        #expect(touches.touchMoved(1, to: Point(x: 213.75, y: 267), time: 2.3) == [.cursorMoved(characters: 1)])
        #expect(touches.touchUp(1, at: Point(x: 213.75, y: 267), time: 2.4) == [.cursorModeEnded, .keyUp(try key("space"))])
        // Once it ends, keys work again.
        #expect(touches.touchDown(2, at: pa, time: 2.5) == [.keyDown(a)])
    }

    @Test func cursorModeStopsHeldBackspace() throws {
        let b = try key("⌫"), space = try key("space"), pb = try center("⌫"), ps = try center("space")
        #expect(touches.touchDown(1, at: pb, time: 0) == [.keyDown(b), .deleteBackward(word: false)])
        // Space lands while backspace repeats; backspace never rolls over, so space starts its hold (due 0.43).
        #expect(touches.touchDown(2, at: ps, time: 0.1) == [.keyDown(space)])
        // Backspace repeats once at 0.4; at 0.43 cursor mode begins and backspace stops.
        #expect(touches.advance(to: 0.43) == [.deleteBackward(word: false), .cursorModeBegan])
        #expect(touches.nextDeadline == nil)
        #expect(touches.advance(to: 3) == [])
        // Backspace's finger can't swipe a word away either, and its lift only clears its highlight.
        #expect(touches.touchMoved(1, to: Point(x: 300.75, y: 215), time: 3.1) == [])
        #expect(touches.touchMoved(2, to: Point(x: 213.75, y: 267), time: 3.2) == [.cursorMoved(characters: 1)])
        #expect(touches.touchUp(1, at: Point(x: 300.75, y: 215), time: 3.3) == [.keyUp(b)])
        #expect(touches.touchUp(2, at: Point(x: 213.75, y: 267), time: 3.4) == [.cursorModeEnded, .keyUp(space)])
    }

    @Test func spaceRolloverBeforeHold() throws {
        let space = try key("space"), a = try key("a"), ps = try center("space"), pa = try center("a")
        #expect(touches.touchDown(1, at: ps, time: 0) == [.keyDown(space)])
        // a lands before the 0.33 s hold: space is typed and its cursor hold is cancelled.
        #expect(touches.touchDown(2, at: pa, time: 0.1) == [.activate(space, landing: ps), .keyDown(a)])
        // Lift a before its own long-press (due at 0.4) so only space's cancelled hold is left to check.
        #expect(touches.touchUp(2, at: pa, time: 0.2) == [.activate(a, landing: pa), .keyUp(a)])
        #expect(touches.nextDeadline == nil)
        #expect(touches.advance(to: 0.5) == [])
        #expect(touches.touchUp(1, at: ps, time: 0.6) == [.keyUp(space)])
    }

    @Test func spaceGetsNoCursorModeWhileOptionsShow() throws {
        let d = try key("d"), space = try key("space"), pd = try center("d"), ps = try center("space")
        #expect(touches.touchDown(1, at: pd, time: 0) == [.keyDown(d)])
        #expect(touches.advance(to: 0.3) == [.alternatesShown(d, options: ["₹", "$", "€"], selected: 0, originX: 100.5)])
        // Like a key's long-press, space's hold doesn't start while another finger chooses an option.
        #expect(touches.touchDown(2, at: ps, time: 0.4) == [.keyDown(space)])
        #expect(touches.nextDeadline == nil)
        #expect(touches.advance(to: 1) == [])
        #expect(touches.touchUp(2, at: ps, time: 1.1) == [.activate(space, landing: ps), .keyUp(space)])
        #expect(touches.touchUp(1, at: pd, time: 1.2) == [.activateAlternate(d, text: "₹"), .keyUp(d)])
    }

    @Test func cancelDuringCursorModeEndsIt() throws {
        let space = try key("space"), a = try key("a"), pa = try center("a")
        try enterCursorMode()
        #expect(touches.touchCancelled(1) == [.cursorModeEnded, .keyUp(space)])
        #expect(touches.nextDeadline == nil)
        #expect(touches.advance(to: 5) == [])
        #expect(touches.touchUp(1, at: try center("space"), time: 5.1) == [])
        // Cursor mode is over: the next finger types again.
        #expect(touches.touchDown(2, at: pa, time: 6) == [.keyDown(a)])
    }

    @Test func reusedIDEndsCursorModeBeforeLanding() throws {
        let space = try key("space"), a = try key("a"), pa = try center("a")
        try enterCursorMode()
        // Space's lift was lost and its id lands again: cursor mode ends as a lift would, then the new finger counts.
        #expect(touches.touchDown(1, at: pa, time: 1) == [.cursorModeEnded, .keyUp(space), .keyDown(a)])
        #expect(touches.touchUp(1, at: pa, time: 1.1) == [.activate(a, landing: pa), .keyUp(a)])
    }

    // MARK: Cancelling every touch (ruling R33)

    @Test func cancelAllEndsCursorMode() throws {
        let space = try key("space"), a = try key("a"), pa = try center("a")
        try enterCursorMode()
        #expect(touches.cancelAll() == [.cursorModeEnded, .keyUp(space)])
        #expect(touches.nextDeadline == nil)
        // Space's lift, if it comes after all, does nothing; and keys work again.
        #expect(touches.touchUp(1, at: try center("space"), time: 1) == [])
        #expect(touches.touchDown(2, at: pa, time: 1.1) == [.keyDown(a)])
        #expect(touches.touchUp(2, at: pa, time: 1.2) == [.activate(a, landing: pa), .keyUp(a)])
    }

    @Test func cancelAllStopsHeldBackspace() throws {
        let b = try key("⌫"), pb = try center("⌫")
        #expect(touches.touchDown(1, at: pb, time: 0) == [.keyDown(b), .deleteBackward(word: false)])
        #expect(touches.advance(to: 0.4) == [.deleteBackward(word: false)])
        #expect(touches.cancelAll() == [.keyUp(b)])
        #expect(touches.nextDeadline == nil)
        // A minute later, as when the keyboard comes back on screen: no delete is replayed.
        #expect(touches.advance(to: 60) == [])
        #expect(touches.touchUp(1, at: pb, time: 60.1) == [])
    }

    @Test func cancelAllEndsEveryTouchInOrderAndTypesNothing() throws {
        let a = try key("a"), s = try key("s"), d = try key("d"), b = try key("⌫")
        let pa = try center("a"), ps = try center("s"), pd = try center("d"), pb = try center("⌫")
        #expect(touches.touchDown(1, at: pa, time: 0) == [.keyDown(a)])
        // s types the held a (rollover), so a is spent; d waits for its long-press; backspace repeats.
        #expect(touches.touchDown(2, at: ps, time: 0.05) == [.activate(a, landing: pa), .keyDown(s)])
        #expect(touches.touchDown(3, at: pb, time: 0.1) == [.activate(s, landing: ps), .keyDown(b), .deleteBackward(word: false)])
        #expect(touches.touchDown(4, at: pd, time: 0.15) == [.keyDown(d)])
        #expect(touches.advance(to: 0.45) == [.alternatesShown(d, options: ["₹", "$", "€"], selected: 0, originX: 100.5)])
        #expect(touches.isShowingAlternates)
        #expect(touches.cancelAll() == [.keyUp(a), .keyUp(s), .keyUp(b), .keyUp(d)])
        #expect(touches.nextDeadline == nil && !touches.isShowingAlternates)
        #expect(touches.advance(to: 10) == [])
        #expect(touches.touchUp(4, at: pd, time: 10.1) == [])
        // With nothing down, it has nothing to say.
        #expect(touches.cancelAll() == [])
    }
}
