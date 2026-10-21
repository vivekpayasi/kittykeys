// UIKit only, so that `swift test` still builds the package on macOS.
#if canImport(UIKit)
import KeyboardCore
import UIKit

/// The return key's label for the field's return key type.
/// English for milestone 1; it moves to the layout data when a second language arrives.
public enum ReturnKeyLabel {
    public static func text(for kind: ReturnKeyKind) -> String {
        switch kind {
        case .standard: "return"
        case .go: "Go"
        case .search: "Search"
        case .join: "Join"
        case .next: "Next"
        case .route: "Route"
        case .send: "Send"
        case .done: "Done"
        case .emergencyCall: "Emergency"
        case .continue: "Continue"
        }
    }
}

/// The keyboard: draws every key from a `KeyboardController`'s frames and state, and hands it every raw touch.
///
/// - Keys are layers, built once per change of the controller's frames. Other changes touch only the layers
///   they affect, with implicit animations off. There are no buttons, gesture recognizers or Auto Layout
///   inside the key grid.
/// - The view lays the keys out for its own width, redraws from `controller.onChange` (which `init` sets; a host
///   that wants change notices too wraps it rather than replacing it), and runs the controller's timers with a
///   display link while one is pending.
/// - A touch whose lift never arrives is ended for it (ruling R33): when the view leaves or rejoins a window,
///   and when a new touch begins while UIKit no longer reports it.
/// - The suggestion row is an empty band at the top in milestone 1.
@MainActor public final class KeyboardView: UIView {
    /// The width of a long-press option's cell, the touch processor's own.
    private static let alternateWidth = CGFloat(TouchTiming().alternateWidth)
    /// The label shift shows while caps lock is on. The layout file's label shows otherwise.
    private static let capsLockLabel = "⇪"
    /// Label sizes: number row, single-character labels, longer labels such as "123" or "return".
    private static let numberFontSize: CGFloat = 19, characterFontSize: CGFloat = 21, wordFontSize: CGFloat = 15
    /// More fingers than a screen reports at once, so tracking touches never grows its set.
    private static let touchCapacity = 20

    /// Set by the host from the trait collection or the field's `keyboardAppearance`. Changing it redraws every key.
    public var theme: KeyboardTheme = .light {
        didSet {
            guard theme != oldValue else { return }
            backgroundColor = theme.background
            rebuild()
        }
    }

    /// Called at each touch-down with the touch's timestamp, before the controller sees the touch.
    /// The keyboard extension measures touch delivery with it.
    public var onTouchDown: ((_ timestamp: TimeInterval) -> Void)?
    /// Called once, after the first render that drew keys. The keyboard extension ends its startup measurement with it.
    public var onFirstKeysDrawn: (() -> Void)?

    private let controller: KeyboardController
    private let keysLayer = CALayer()
    private let previewLayer = KeyPreviewLayer()
    private let alternatesLayer = AlternatesLayer()
    /// One layer per key, indexed by key id.
    private var keyLayers: [KeyLayer] = []
    /// The frames `keyLayers` were built from; nil forces a rebuild.
    private var builtFrames: [KeyFrame]?
    /// The keyboard height when the keys were last built, to tell Auto Layout when a page changes it.
    private var builtHeight: Double?
    /// The state the key layers show; nil after a rebuild, so every key is brought up to date.
    private var renderedState: KeyboardState?
    private var shownPreview: Preview?
    private var shownAlternates: AlternatesPopup?
    /// Calls `advance(to:)` every frame while the controller has a timer pending; paused otherwise.
    private var displayLink: CADisplayLink?
    /// The touches handed to the controller that haven't ended or been cancelled yet.
    private var liveTouchIDs: Set<TouchID> = []

    /// A key preview on screen: the key and the label it shows.
    private struct Preview: Equatable {
        var keyID: Int
        var label: String
    }

    public init(controller: KeyboardController) {
        self.controller = controller
        super.init(frame: .zero)
        isMultipleTouchEnabled = true
        liveTouchIDs.reserveCapacity(Self.touchCapacity)
        backgroundColor = theme.background
        layer.addSublayer(keysLayer)
        layer.addSublayer(previewLayer)
        layer.addSublayer(alternatesLayer)
        controller.onChange = { [weak self] in self?.render() }
        // Text layers are drawn for the screen's scale; a new scale needs new layers or the text blurs.
        registerForTraitChanges([UITraitDisplayScale.self]) { (view: KeyboardView, _: UITraitCollection) in
            view.rebuild()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// The keyboard's height for the current page; the width comes from the host.
    public override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: CGFloat(controller.height))
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        controller.setWidth(Double(bounds.width))
        // setWidth redraws through onChange only when the width changed. Frames the controller already had,
        // such as before this view existed, still need drawing.
        if controller.frames != builtFrames { render() }
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        // A touch whose lift was lost on the way out would otherwise leave cursor mode on (every touch ignored)
        // or a backspace repeat due, which would replay every missed delete once the timer runs again.
        // So every touch ends here, before the timer can restart.
        liveTouchIDs.removeAll(keepingCapacity: true)
        controller.cancelAllTouches()
        if window == nil {
            displayLink?.invalidate()
            displayLink = nil
        } else {
            updateTimer()
        }
    }

    // MARK: Drawing

    /// Brings the layers up to date with the controller's frames and state.
    /// Rebuilds the key layers only when the frames changed; otherwise updates only the keys, preview and popup
    /// whose state changed.
    public func render() {
        let state = controller.state
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if controller.frames != builtFrames { buildKeys() }
        updateKeys(to: state)
        updatePreview(state)
        updateAlternates(state)
        CATransaction.commit()
        renderedState = state
        updateTimer()
        if !keyLayers.isEmpty, let onFirstKeysDrawn {
            self.onFirstKeysDrawn = nil
            onFirstKeysDrawn()
        }
    }

    /// Throws away every key layer and draws again, for a new theme or screen scale.
    private func rebuild() {
        builtFrames = nil
        render()
    }

    private func buildKeys() {
        let frames = controller.frames
        let lastRow = frames.last?.row
        let scale = displayScale
        keyLayers.forEach { $0.removeFromSuperlayer() }
        keyLayers = frames.map { frame in
            let keyLayer = KeyLayer(
                rect: CGRect(frame.rect), style: Self.style(of: frame, lastRow: lastRow),
                hint: Self.cornerHint(of: frame, lastRow: lastRow), theme: theme, scale: scale)
            keysLayer.addSublayer(keyLayer)
            return keyLayer
        }
        builtFrames = frames
        renderedState = nil
        shownPreview = nil
        previewLayer.hide()
        shownAlternates = nil
        alternatesLayer.hide()
        if controller.height != builtHeight {
            builtHeight = controller.height
            invalidateIntrinsicContentSize()
        }
    }

    /// Labels follow shift, cursor mode and the return key type; highlights follow the pressed keys.
    private func updateKeys(to state: KeyboardState) {
        let old = renderedState
        if old?.shift != state.shift || old?.cursorMode != state.cursorMode || old?.returnKey != state.returnKey {
            for (frame, keyLayer) in zip(controller.frames, keyLayers) {
                keyLayer.setLabel(Self.label(of: frame.key, in: state))
                keyLayer.setLabelsHidden(state.cursorMode)
                keyLayer.setActive(frame.key.action == .shift && state.shift != .off)
            }
        }
        let changed = old.map { $0.pressedKeyIDs.symmetricDifference(state.pressedKeyIDs) } ?? state.pressedKeyIDs
        for id in changed where keyLayers.indices.contains(id) {
            keyLayers[id].setPressed(state.pressedKeyIDs.contains(id))
        }
    }

    /// The preview balloon shows the pressed key's label, except while its long-press popup or cursor mode shows.
    private func updatePreview(_ state: KeyboardState) {
        var preview: Preview?
        if let id = state.previewKeyID, state.alternates == nil, !state.cursorMode, controller.frames.indices.contains(id) {
            preview = Preview(keyID: id, label: Self.label(of: controller.frames[id].key, in: state))
        }
        guard preview != shownPreview else { return }
        shownPreview = preview
        if let preview {
            previewLayer.show(
                preview.label, over: CGRect(controller.frames[preview.keyID].rect), within: bounds, theme: theme,
                scale: displayScale)
        } else {
            previewLayer.hide()
        }
    }

    /// The popup's options are drawn as the controller gives them; sliding along it only moves the highlight.
    private func updateAlternates(_ state: KeyboardState) {
        let popup = state.alternates.flatMap { controller.frames.indices.contains($0.keyID) ? $0 : nil }
        guard popup != shownAlternates else { return }
        defer { shownAlternates = popup }
        guard let popup else {
            alternatesLayer.hide()
            return
        }
        let isNewPopup = shownAlternates.map {
            $0.keyID != popup.keyID || $0.options != popup.options || $0.originX != popup.originX
        } ?? true
        if isNewPopup {
            alternatesLayer.show(
                popup.options, originX: CGFloat(popup.originX), cellWidth: Self.alternateWidth,
                above: CGRect(controller.frames[popup.keyID].rect), within: bounds, theme: theme, scale: displayScale)
        }
        alternatesLayer.select(popup.selected)
    }

    private var displayScale: CGFloat {
        max(traitCollection.displayScale, 1)
    }

    /// What `key` shows: letters in capitals while shift is on, ⇪ for caps lock, and the field's return label.
    private static func label(of key: KeySpec, in state: KeyboardState) -> String {
        switch key.action {
        case .character where state.shift != .off && key.output.count == 1:
            key.label.uppercased()
        case .shift where state.shift == .locked:
            capsLockLabel
        case .returnKey:
            ReturnKeyLabel.text(for: state.returnKey)
        default:
            key.label
        }
    }

    /// Letter, number and symbol keys and space rest in the key colour; every other key, and everything else
    /// on the bottom row (`lastRow`), in the special-key colour. Row 0 is the number row (`LayoutPage.rows[0]` always is).
    private static func style(of frame: KeyFrame, lastRow: Int?) -> KeyStyle {
        let key = frame.key
        let isSpace = key.action == .space
        let isSpecial = !isSpace && (key.action != .character || frame.row == lastRow)
        let fontSize: CGFloat
        if isSpace || key.label.count > 1 {
            fontSize = wordFontSize
        } else if frame.row == 0 {
            fontSize = numberFontSize
        } else {
            fontSize = characterFontSize
        }
        return KeyStyle(isSpecial: isSpecial, dimsLabel: isSpace, fontSize: fontSize)
    }

    /// Corner hints go only on the letter and symbol rows between the number row (row 0) and the bottom row
    /// (`lastRow`), as ruling R3 says.
    private static func cornerHint(of frame: KeyFrame, lastRow: Int?) -> String? {
        frame.row > 0 && frame.row != lastRow ? frame.key.cornerHint : nil
    }

    // MARK: Touches

    public override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let onTouchDown {
            for touch in touches { onTouchDown(touch.timestamp) }
        }
        if let stillDown = event?.allTouches { cancelLostTouches(stillDown: stillDown) }
        forward(touches) { controller.touchDown($0, at: $1, time: $2) }
        for touch in touches { liveTouchIDs.insert(Self.id(of: touch)) }
    }

    public override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        forward(touches) { controller.touchMoved($0, to: $1, time: $2) }
    }

    public override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        forward(touches) { controller.touchUp($0, at: $1, time: $2) }
        for touch in touches { liveTouchIDs.remove(Self.id(of: touch)) }
    }

    public override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        forward(touches) { id, _, _ in controller.touchCancelled(id) }
        for touch in touches { liveTouchIDs.remove(Self.id(of: touch)) }
    }

    /// Hands each touch to the controller in time order. Timers due by a touch's time fire first,
    /// so a lift just after a deadline sees the deadline's effect.
    private func forward(_ touches: Set<UITouch>, to send: (TouchID, KeyboardCore.Point, Double) -> Void) {
        for touch in touches.sorted(by: { $0.timestamp < $1.timestamp }) {
            controller.advance(to: touch.timestamp)
            send(Self.id(of: touch), point(of: touch), touch.timestamp)
        }
        updateTimer()
    }

    /// Cancels each touch handed to the controller that `stillDown`, every touch of the event now beginning,
    /// no longer includes: UIKit lost its lift. A touch that is still down is always in its event's touches.
    private func cancelLostTouches(stillDown: Set<UITouch>) {
        func isLost(_ id: TouchID) -> Bool { !stillDown.contains { Self.id(of: $0) == id } }
        // The usual case, nothing lost, only compares ids.
        guard liveTouchIDs.contains(where: isLost) else { return }
        for id in liveTouchIDs.filter(isLost) {
            liveTouchIDs.remove(id)
            controller.touchCancelled(id)
        }
    }

    private static func id(of touch: UITouch) -> TouchID {
        ObjectIdentifier(touch).hashValue
    }

    private func point(of touch: UITouch) -> KeyboardCore.Point {
        let location = touch.location(in: self)
        return KeyboardCore.Point(x: Double(location.x), y: Double(location.y))
    }

    // MARK: Timers

    /// Runs the display link exactly while the controller has a timer pending.
    private func updateTimer() {
        guard controller.nextDeadline != nil, window != nil else {
            displayLink?.isPaused = true
            return
        }
        if displayLink == nil {
            let link = CADisplayLink(target: DisplayLinkTarget(self), selector: #selector(DisplayLinkTarget.tick))
            link.add(to: .main, forMode: .common)
            displayLink = link
        }
        displayLink?.isPaused = false
    }

    fileprivate func displayLinkFired() {
        let now = ProcessInfo.processInfo.systemUptime
        if let deadline = controller.nextDeadline, deadline <= now { controller.advance(to: now) }
        updateTimer()
    }
}

/// The display link's target. A display link keeps its target alive, so it holds the view weakly.
@MainActor private final class DisplayLinkTarget: NSObject {
    private weak var view: KeyboardView?

    init(_ view: KeyboardView) {
        self.view = view
    }

    @objc func tick(_ link: CADisplayLink) {
        guard let view else {
            link.invalidate()
            return
        }
        view.displayLinkFired()
    }
}

extension CGRect {
    fileprivate init(_ rect: KeyboardCore.Rect) {
        self.init(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
    }
}
#endif
