/// Turns raw touches into key events: taps, fast typing (rollover) and long-press options.
///
/// Time comes only from the `time` arguments and `advance(to:)`, never from a clock, so the same calls give the same events.
/// Each finger keeps the key it landed on, so replacing `frames` never changes what a finger already down types.
/// A touch that lands on no key, such as one in the suggestion row, is ignored: the processor doesn't keep it,
/// so its moves, lift and cancel return no events.
public final class TouchProcessor {
    public var timing: TouchTiming
    /// The keys, in the order `KeyboardGeometry.frames` returns them. Replace them when the page or width changes.
    public var frames: [KeyFrame] = []
    /// The keyboard's width in points; long-press popups stay inside it. 0 until set.
    public var keyboardWidth = 0.0

    private let metrics: KeyboardMetrics
    private var touches: [TouchID: KeyTouch] = [:]
    /// The ids in `touches`, oldest touch-down first.
    private var downOrder: [TouchID] = []

    /// More fingers than a screen reports at once, so the touch path never grows the collections.
    private static let touchCapacity = 20

    public init(timing: TouchTiming = .init(), metrics: KeyboardMetrics = .standard) {
        self.timing = timing
        self.metrics = metrics
        touches.reserveCapacity(Self.touchCapacity)
        downOrder.reserveCapacity(Self.touchCapacity)
    }

    /// A finger landed at `p`. A character, space or return key another finger holds, not yet typed,
    /// is typed first (rollover). Then the key under `p` highlights; shift and page keys act at once,
    /// other keys wait for the lift. While a long-press popup is showing, the new key gets no long-press of its own.
    public func touchDown(_ id: TouchID, at p: Point, time: Double) -> [TouchEvent] {
        var events: [TouchEvent] = []
        events.reserveCapacity(4)
        // An id that is still down means its lift was lost: end it as a lift would, so no letter is dropped.
        if touches[id] != nil { events += touchUp(id, at: p, time: time) }
        guard let frame = KeyboardGeometry.hitTest(p, in: frames, metrics: metrics) else { return events }
        typeHeldKeys(into: &events)
        events.append(.keyDown(frame))
        var touch = KeyTouch(frame: frame, landing: p, phase: .pressed)
        switch frame.key.action {
        case .shift, .switchPage:
            events.append(.activate(frame, landing: p))
            touch.phase = .spent
        case .backspace:
            touch.phase = .spent  // Highlight only: deleting is not handled yet.
        case .character:
            if !frame.key.longPress.isEmpty && !isShowingAlternates { touch.deadline = time + timing.longPress }
        case .space, .returnKey, .emoji, .globe:
            break
        }
        touches[id] = touch
        downOrder.append(id)
        return events
    }

    /// A finger moved. Only a finger choosing a long-press option reacts: the option under it becomes the selected one.
    /// Other fingers keep the key they landed on.
    public func touchMoved(_ id: TouchID, to p: Point, time: Double) -> [TouchEvent] {
        guard let touch = touches[id], case .choosingAlternate(var popup) = touch.phase else { return [] }
        let option = alternateIndex(atX: p.x, in: popup)
        guard option != popup.selected else { return [] }
        popup.selected = option
        touches[id]?.phase = .choosingAlternate(popup)
        return [.alternateSelected(touch.frame, selected: option)]
    }

    /// A finger lifted. Its key, or its selected long-press option, is typed unless that already happened.
    public func touchUp(_ id: TouchID, at p: Point, time: Double) -> [TouchEvent] {
        guard let touch = removeTouch(id) else { return [] }
        switch touch.phase {
        case .pressed:
            return [.activate(touch.frame, landing: touch.landing), .keyUp(touch.frame)]
        case .spent:
            return [.keyUp(touch.frame)]
        case .choosingAlternate(let popup):
            return [.activateAlternate(touch.frame, text: popup.options[popup.selected]), .keyUp(touch.frame)]
        }
    }

    /// The system took a touch away, as for an incoming call. Its highlight and timers go, and nothing is typed.
    public func touchCancelled(_ id: TouchID) -> [TouchEvent] {
        guard let touch = removeTouch(id) else { return [] }
        return [.keyUp(touch.frame)]
    }

    /// Fires every timer due at or before `time`, earliest first.
    public func advance(to time: Double) -> [TouchEvent] {
        var events: [TouchEvent] = []
        while let due = earliestTimer(dueBy: time) {
            fireTimer(due.id, into: &events)
        }
        return events
    }

    /// When the next timer is due, for scheduling `advance(to:)`. nil when no timer is pending.
    public var nextDeadline: Double? {
        earliestTimer(dueBy: .infinity)?.deadline
    }

    /// Rollover: types each held character, space or return key still waiting for its lift, in touch-down order,
    /// and cancels its long-press.
    private func typeHeldKeys(into events: inout [TouchEvent]) {
        for id in downOrder {
            guard let touch = touches[id], touch.phase == .pressed, touch.frame.key.action.rollsOver else { continue }
            events.append(.activate(touch.frame, landing: touch.landing))
            touches[id]?.phase = .spent
            touches[id]?.deadline = nil
        }
    }

    /// Whether some finger is choosing a long-press option.
    private var isShowingAlternates: Bool {
        for id in downOrder {
            if case .choosingAlternate? = touches[id]?.phase { return true }
        }
        return false
    }

    /// Fires touch `id`'s timer. The only timer so far is a character key's long-press, which shows its options.
    private func fireTimer(_ id: TouchID, into events: inout [TouchEvent]) {
        guard var touch = touches[id] else { return }
        touch.deadline = nil
        if touch.phase == .pressed, touch.frame.key.action == .character, !touch.frame.key.longPress.isEmpty {
            let popup = alternatesPopup(for: touch.frame)
            touch.phase = .choosingAlternate(popup)
            events.append(.alternatesShown(touch.frame, options: popup.options, selected: popup.selected, originX: popup.originX))
        }
        touches[id] = touch
    }

    /// Lays out `frame`'s long-press options with the default (first) option over the key, selected.
    /// They run rightward from the key's left edge when they fit on the keyboard, otherwise leftward from its right edge.
    private func alternatesPopup(for frame: KeyFrame) -> KeyTouch.Popup {
        let options = frame.key.longPress
        let width = Double(options.count) * timing.alternateWidth
        if frame.rect.minX + width <= keyboardWidth {
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
        // `Int(_:)` traps on NaN and infinity, and a cell width of 0 or less gives them or nonsense:
        // keep the default option instead. Any finite value is clamped into range before converting.
        guard timing.alternateWidth > 0, cell.isFinite else { return popup.defaultIndex }
        return Int(min(max(cell, 0), Double(popup.options.count - 1)))
    }
}

/// A finger on a key.
private struct KeyTouch {
    enum Phase: Equatable {
        /// Waiting for its lift, its long-press, or another finger landing.
        case pressed
        /// Its action already happened, on touch-down or by rollover. Lift or cancel only clears the highlight.
        case spent
        /// Its long-press options are showing.
        case choosingAlternate(Popup)
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

    /// The key the finger landed on. It stays the same when `frames` is replaced.
    let frame: KeyFrame
    let landing: Point
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
