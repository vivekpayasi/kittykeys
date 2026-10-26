/// Turns raw touches into key events: taps, fast typing (rollover), long-press options,
/// backspace repeat and swipe, and space-bar cursor mode.
///
/// Time comes only from the `time` arguments and `advance(to:)`, never from a clock, so the same calls give the same events.
/// Each finger keeps the key it landed on, so replacing `frames` never changes what a finger already down types.
/// Replacing them ends long-presses, shown or still to come, since a popup would no longer match the keys on screen.
/// A touch that lands on no key, such as one in the suggestion row, is ignored: the processor doesn't keep it,
/// so its moves, lift and cancel return no events.
public final class TouchProcessor {
    public var timing: TouchTiming
    /// The keys, in the order `KeyboardGeometry.frames` returns them. Replace them when the page or width changes.
    /// Fingers on character keys then lose their long-press, shown or still to come, and type their own key on lift.
    public var frames: [KeyFrame] = [] {
        didSet { endLongPresses() }
    }
    /// The keyboard's width in points; long-press popups stay inside it. 0 until set.
    public var keyboardWidth = 0.0
    /// Whether holding space starts cursor mode. Off, as in emoji search, a held space is typed on its lift like a tap.
    /// Turning it off cancels the hold of a space already down; a space already moving the cursor goes on doing so.
    public var allowsCursorMode = true {
        didSet {
            guard !allowsCursorMode else { return }
            for id in downOrder where touches[id]?.phase == .pressed && touches[id]?.frame.key.action == .space {
                touches[id]?.deadline = nil
            }
        }
    }

    private let metrics: KeyboardMetrics
    private var touches: [TouchID: KeyTouch] = [:]
    /// The ids in `touches`, oldest touch-down first.
    private var downOrder: [TouchID] = []

    /// More fingers than a screen reports at once, so the touch path never grows the collections.
    private static let touchCapacity = 20
    /// Deadlines are sums of decimal intervals that binary floating point rounds (0.4 + 0.07 is a hair over 0.47),
    /// so a timer due within this many seconds after `advance(to:)`'s time counts as due.
    private static let timerTolerance = 1e-9

    public init(timing: TouchTiming = .init(), metrics: KeyboardMetrics = .standard) {
        self.timing = timing
        self.metrics = metrics
        touches.reserveCapacity(Self.touchCapacity)
        downOrder.reserveCapacity(Self.touchCapacity)
    }

    /// A finger landed at `p`. A character, space or return key another finger holds, not yet typed,
    /// is typed first (rollover). Then the key under `p` highlights; shift and page keys act at once,
    /// backspace deletes at once and repeats while held, and other keys wait for the lift.
    /// While a long-press popup is showing, the new key gets no long-press of its own, and space no cursor mode;
    /// nor does space while `allowsCursorMode` is off.
    /// While space is moving the cursor, the whole keyboard is its trackpad: the new finger is ignored.
    public func touchDown(_ id: TouchID, at p: Point, time: Double) -> [TouchEvent] {
        var events: [TouchEvent] = []
        events.reserveCapacity(4)
        // An id that is still down means its lift was lost: end it as a lift would, so no letter is dropped.
        if touches[id] != nil { events += touchUp(id, at: p, time: time) }
        guard !isMovingCursor, let frame = KeyboardGeometry.hitTest(p, in: frames, metrics: metrics) else { return events }
        typeHeldKeys(into: &events)
        events.append(.keyDown(frame))
        var touch = KeyTouch(frame: frame, landing: p, position: p, phase: .pressed)
        switch frame.key.action {
        case .shift, .switchPage:
            events.append(.activate(frame, landing: p))
            touch.phase = .spent
        case .backspace:
            events.append(.deleteBackward(word: false))
            let deleting = KeyTouch.Deleting(downTime: time)
            touch.phase = .deleting(deleting)
            touch.deadline = nextDelete(after: deleting).time
        case .character:
            if !frame.key.longPress.isEmpty && !isShowingAlternates { touch.deadline = time + timing.longPress }
        case .space:
            if allowsCursorMode && !isShowingAlternates { touch.deadline = time + timing.cursorHold }
        case .returnKey, .emoji, .globe:
            break
        }
        touches[id] = touch
        downOrder.append(id)
        return events
    }

    /// A finger moved. A finger choosing a long-press option selects the option under it; backspace swiped
    /// `backspaceSwipe` left of where it landed deletes the rest of the word and stops repeating;
    /// space in cursor mode moves the cursor.
    /// Other fingers keep the key they landed on.
    public func touchMoved(_ id: TouchID, to p: Point, time: Double) -> [TouchEvent] {
        guard var touch = touches[id] else { return [] }
        var events: [TouchEvent] = []
        switch touch.phase {
        case .choosingAlternate(var popup):
            let option = alternateIndex(atX: p.x, in: popup)
            if option != popup.selected {
                popup.selected = option
                touch.phase = .choosingAlternate(popup)
                events.append(.alternateSelected(touch.frame, selected: option))
            }
        case .deleting where touch.landing.x - p.x >= timing.backspaceSwipe:
            touch.phase = .spent
            touch.deadline = nil
            events.append(.deleteRestOfWord)
        case .movingCursor(var trackpad):
            moveCursor(&trackpad, from: touch.position, to: p, time: time, into: &events)
            touch.phase = .movingCursor(trackpad)
        case .pressed, .spent, .deleting:
            break
        }
        touch.position = p
        touches[id] = touch
        return events
    }

    /// A finger lifted. Its key, or its selected long-press option, is typed unless that already happened.
    /// Lifting space in cursor mode ends cursor mode and types nothing.
    public func touchUp(_ id: TouchID, at p: Point, time: Double) -> [TouchEvent] {
        guard let touch = removeTouch(id) else { return [] }
        switch touch.phase {
        case .pressed:
            return [.activate(touch.frame, landing: touch.landing), .keyUp(touch.frame)]
        case .spent, .deleting:
            return [.keyUp(touch.frame)]
        case .choosingAlternate(let popup):
            return [.activateAlternate(touch.frame, text: popup.options[popup.selected]), .keyUp(touch.frame)]
        case .movingCursor:
            return [.cursorModeEnded, .keyUp(touch.frame)]
        }
    }

    /// The system took a touch away, as for an incoming call. Its highlight, timers and cursor mode go, and nothing is typed.
    public func touchCancelled(_ id: TouchID) -> [TouchEvent] {
        guard let touch = removeTouch(id) else { return [] }
        if case .movingCursor = touch.phase { return [.cursorModeEnded, .keyUp(touch.frame)] }
        return [.keyUp(touch.frame)]
    }

    /// Every touch ends at once and nothing is typed, as when the keyboard leaves the screen or a lift never came.
    /// Returns `.cursorModeEnded` first if space was moving the cursor, then `.keyUp` for every touch in
    /// touch-down order, spent ones included. No touch or timer is left, so `nextDeadline` is nil afterwards.
    public func cancelAll() -> [TouchEvent] {
        var events: [TouchEvent] = []
        events.reserveCapacity(downOrder.count + 1)
        if isMovingCursor { events.append(.cursorModeEnded) }
        for id in downOrder {
            if let touch = touches[id] { events.append(.keyUp(touch.frame)) }
        }
        touches.removeAll(keepingCapacity: true)
        downOrder.removeAll(keepingCapacity: true)
        return events
    }

    /// Fires every timer due at or before `time`, earliest first, across all touches.
    /// A timer due up to 1e-9 s after `time` counts as due, since sums like 0.4 + 0.07 round a hair past 0.47.
    public func advance(to time: Double) -> [TouchEvent] {
        var events: [TouchEvent] = []
        while let due = earliestTimer(dueBy: time + Self.timerTolerance) {
            fireTimer(due.id, dueAt: due.deadline, into: &events)
        }
        return events
    }

    /// When the next timer is due, for scheduling `advance(to:)`. nil when no timer is pending.
    public var nextDeadline: Double? {
        earliestTimer(dueBy: .infinity)?.deadline
    }

    /// Whether some finger is choosing a long-press option, so its popup is on screen.
    public var isShowingAlternates: Bool {
        for id in downOrder {
            if case .choosingAlternate? = touches[id]?.phase { return true }
        }
        return false
    }

    /// Rollover: types each held character, space or return key still waiting for its lift, in touch-down order,
    /// and cancels its long-press or cursor hold.
    private func typeHeldKeys(into events: inout [TouchEvent]) {
        for id in downOrder {
            guard let touch = touches[id], touch.phase == .pressed, touch.frame.key.action.rollsOver else { continue }
            events.append(.activate(touch.frame, landing: touch.landing))
            touches[id]?.phase = .spent
            touches[id]?.deadline = nil
        }
    }

    /// Cursor mode takes over the keyboard: a held backspace deletes no more, by timer or swipe, and its lift only clears its highlight.
    private func stopBackspaceRepeats() {
        for id in downOrder {
            guard case .deleting? = touches[id]?.phase else { continue }
            touches[id]?.phase = .spent
            touches[id]?.deadline = nil
        }
    }

    /// New frames end every long-press: a finger choosing an option goes back to pressed, and a held character key's
    /// long-press timer is cancelled, so each types its own key on lift. Space keeps its hold for cursor mode.
    private func endLongPresses() {
        for id in downOrder {
            guard let touch = touches[id] else { continue }
            switch touch.phase {
            case .choosingAlternate:
                touches[id]?.phase = .pressed
                touches[id]?.deadline = nil
            case .pressed where touch.frame.key.action == .character:
                touches[id]?.deadline = nil
            case .pressed, .spent, .deleting, .movingCursor:
                break
            }
        }
    }

    /// Whether space is in cursor mode.
    private var isMovingCursor: Bool {
        for id in downOrder {
            if case .movingCursor? = touches[id]?.phase { return true }
        }
        return false
    }

    /// Fires touch `id`'s timer, due at `deadline`: a character key's long-press shows its options,
    /// space's hold starts cursor mode (stopping any held backspace), and backspace deletes again and schedules its next repeat.
    private func fireTimer(_ id: TouchID, dueAt deadline: Double, into events: inout [TouchEvent]) {
        guard var touch = touches[id] else { return }
        touch.deadline = nil
        switch (touch.phase, touch.frame.key.action) {
        case (.pressed, .character) where !touch.frame.key.longPress.isEmpty:
            let popup = alternatesPopup(for: touch.frame)
            touch.phase = .choosingAlternate(popup)
            events.append(.alternatesShown(touch.frame, options: popup.options, selected: popup.selected, originX: popup.originX))
        case (.pressed, .space):
            touch.phase = .movingCursor(KeyTouch.Trackpad(anchor: touch.position, lastMoveTime: deadline))
            events.append(.cursorModeBegan)
            stopBackspaceRepeats()
        case (.deleting(var deleting), _):
            let word = nextDelete(after: deleting).word
            events.append(.deleteBackward(word: word))
            if word { deleting.wordRepeats += 1 } else { deleting.characterRepeats += 1 }
            touch.phase = .deleting(deleting)
            let next = nextDelete(after: deleting).time
            // A repeat interval that isn't positive would fire forever within one `advance(to:)`: stop instead.
            touch.deadline = next > deadline ? next : nil
        default:
            break
        }
        touches[id] = touch
    }

    /// When held backspace next deletes, and whether it deletes a word. Characters go from `backspaceFirstRepeat`
    /// every `backspaceRepeat`, until `backspaceWordsAfter`; from then on a word goes every `backspaceWordRepeat`.
    /// Each time is counted from touch-down, so repeats don't drift.
    private func nextDelete(after deleting: KeyTouch.Deleting) -> (time: Double, word: Bool) {
        let wordsFrom = deleting.downTime + timing.backspaceWordsAfter
        if deleting.wordRepeats == 0 {
            let character = deleting.downTime + timing.backspaceFirstRepeat
                + Double(deleting.characterRepeats) * timing.backspaceRepeat
            if character < wordsFrom - Self.timerTolerance { return (character, false) }
        }
        return (wordsFrom + Double(deleting.wordRepeats) * timing.backspaceWordRepeat, true)
    }

    /// Turns the finger's travel from the trackpad's anchor into whole cursor steps, horizontal first.
    /// Each step moves the anchor by the distance it used, so what's left over carries into the next move.
    /// A move faster than `cursorFastSpeed`, measured from `last` (the previous move, or where cursor mode began),
    /// moves `cursorFastMultiplier` characters per step.
    private func moveCursor(
        _ trackpad: inout KeyTouch.Trackpad, from last: Point, to p: Point, time: Double, into events: inout [TouchEvent]
    ) {
        let steps = Self.wholeSteps(p.x - trackpad.anchor.x, of: timing.cursorStep)
        if steps != 0 {
            let elapsed = time - trackpad.lastMoveTime
            let fast = elapsed <= 0 || abs(p.x - last.x) / elapsed > timing.cursorFastSpeed
            events.append(.cursorMoved(characters: fast ? steps * timing.cursorFastMultiplier : steps))
            trackpad.anchor.x += Double(steps) * timing.cursorStep
        }
        let lines = Self.wholeSteps(p.y - trackpad.anchor.y, of: timing.cursorLineStep)
        if lines != 0 {
            events.append(.cursorMovedLines(lines))
            trackpad.anchor.y += Double(lines) * timing.cursorLineStep
        }
        trackpad.lastMoveTime = time
    }

    /// How many whole `step`s fit in `distance`, rounded toward zero; negative for a negative distance.
    /// 0 when either is unusable: `Int(_:)` traps on NaN, infinity and huge values, and a crash kills the keyboard.
    private static func wholeSteps(_ distance: Double, of step: Double) -> Int {
        let steps = (distance / step).rounded(.towardZero)
        // NaN fails the comparison; no real move comes near the bound.
        guard step > 0, steps.magnitude <= 100_000 else { return 0 }
        return Int(steps)
    }

    /// Whether `timing.alternateWidth` can place cells. A width of 0 or less, or not finite, gives NaN or nonsense positions.
    private var alternateWidthIsUsable: Bool {
        timing.alternateWidth > 0 && timing.alternateWidth.isFinite
    }

    /// Lays out `frame`'s long-press options with the default (first) option over the key, selected.
    /// They run rightward from the key's left edge when they fit on the keyboard, otherwise leftward from its right edge.
    /// With an unusable cell width they run rightward from the left edge.
    private func alternatesPopup(for frame: KeyFrame) -> KeyTouch.Popup {
        let options = frame.key.longPress
        let width = Double(options.count) * timing.alternateWidth
        if !alternateWidthIsUsable || frame.rect.minX + width <= keyboardWidth {
            return KeyTouch.Popup(options: options, originX: frame.rect.minX, defaultIndex: 0)
        }
        return KeyTouch.Popup(
            options: options.reversed(), originX: max(frame.rect.maxX - width, 0), defaultIndex: options.count - 1)
    }

    /// The touch whose timer is due first at or before `time`. On a tie, the earlier touch-down wins.
    private func earliestTimer(dueBy time: Double) -> (id: TouchID, deadline: Double)? {
        var earliest: (id: TouchID, deadline: Double)?
        for id in downOrder {
            guard let deadline = touches[id]?.deadline, deadline <= time, deadline < earliest?.deadline ?? .infinity else { continue }
            earliest = (id, deadline)
        }
        return earliest
    }

    private func removeTouch(_ id: TouchID) -> KeyTouch? {
        guard let touch = touches.removeValue(forKey: id) else { return nil }
        if let index = downOrder.firstIndex(of: id) { downOrder.remove(at: index) }
        return touch
    }

    /// The option under `x`. Past either end of the popup, the end option.
    private func alternateIndex(atX x: Double, in popup: KeyTouch.Popup) -> Int {
        let cell = (x - popup.originX) / timing.alternateWidth
        // `Int(_:)` traps on NaN and infinity, and an unusable cell width gives them or nonsense:
        // keep the default option instead. Any finite value is clamped into range before converting.
        guard alternateWidthIsUsable, cell.isFinite else { return popup.defaultIndex }
        return Int(min(max(cell, 0), Double(popup.options.count - 1)))
    }
}

/// A finger on a key.
private struct KeyTouch {
    enum Phase: Equatable {
        /// Waiting for its lift, its long-press or cursor hold, or another finger landing.
        case pressed
        /// Its action already happened: on touch-down, by rollover, or for backspace by a swipe or cursor mode starting.
        /// Lift or cancel only clears the highlight.
        case spent
        /// Its long-press options are showing.
        case choosingAlternate(Popup)
        /// Backspace held down, deleting on its timer.
        case deleting(Deleting)
        /// Space held past its cursor hold: the finger moves the cursor.
        case movingCursor(Trackpad)
    }

    /// A long-press popup: one `alternateWidth` cell per option, from `originX`.
    struct Popup: Equatable {
        /// The options in display order, left to right.
        var options: [String]
        var originX: Double
        /// Where the key's first option, its default, sits in `options`.
        var defaultIndex: Int
        var selected: Int

        init(options: [String], originX: Double, defaultIndex: Int) {
            self.options = options
            self.originX = originX
            self.defaultIndex = defaultIndex
            selected = defaultIndex
        }
    }

    /// Held backspace's repeats.
    struct Deleting: Equatable {
        /// When backspace landed; every repeat is timed from here.
        let downTime: Double
        /// Repeats fired so far, of characters and of words.
        var characterRepeats = 0, wordRepeats = 0
    }

    /// Space-bar cursor mode.
    struct Trackpad: Equatable {
        /// Where the finger's travel is measured from, one value per axis.
        var anchor: Point
        /// When the finger last moved, or when cursor mode began.
        var lastMoveTime: Double
    }

    /// The key the finger landed on. It stays the same when `frames` is replaced.
    let frame: KeyFrame
    let landing: Point
    /// Where the finger was last reported.
    var position: Point
    var phase: Phase
    /// When this touch's timer fires. nil when none is pending.
    var deadline: Double?
}

private extension KeyAction {
    /// Whether another finger landing types this key at once instead of it waiting for its own lift.
    var rollsOver: Bool {
        self == .character || self == .space || self == .returnKey
    }
}
