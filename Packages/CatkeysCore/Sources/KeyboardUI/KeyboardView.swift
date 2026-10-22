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
/// - While the controller's `state.panel` is `.emoji`, an `EmojiPanelView` covers the keys below the suggestion row,
///   at the same height, with an `EmojiSearchField` in the suggestion row's band. The panel is made the first time it
///   opens and kept, unless a memory warning frees it while closed.
/// - In `.emojiSearch` (ruling M3-R15) the keys show again without their number row, the field shows the query, and an
///   `EmojiSearchResultsView` fills the number row's band. It is made the first time search opens and kept, unless a
///   memory warning frees it, with the search keywords, while search is closed.
/// - The view looks clear, so the system's keyboard backdrop shows around and between the keys (ruling R42). Its fill
///   is `UIColor.touchableClear`, not `.clear`, so taps between the keys still reach it (ruling M3-R8).
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
            emojiPanel?.theme = theme
            searchField?.theme = theme
            searchResults?.theme = theme
            rebuild()
        }
    }

    /// Called at each touch-down with the touch's timestamp and whether it landed on the bottom row,
    /// before the controller sees the touch. The keyboard extension measures touch delivery with it.
    public var onTouchDown: ((_ timestamp: TimeInterval, _ isBottomRow: Bool) -> Void)?
    /// Runs a stretch of the view's work, for timing: "touch" for each batch of touches handed to the controller
    /// (the touch processor and the controller's whole response), "render" for each `render()`, and "emojiInsert" for
    /// each emoji the panel or search's results type. The keyboard extension wraps `work` in a signpost interval.
    /// Without it the work just runs.
    public var measure: ((_ name: StaticString, _ work: () -> Void) -> Void)?
    /// Starts timing a stretch that ends only once Core Animation has committed and drawn it, and returns the call that
    /// ends it:
    /// - "emojiPanelOpen", from the emoji panel opening to its first frame with emoji drawn;
    /// - "emojiSearchOpen", from search opening (a touch on the search field) to its first frame with the keys and the
    ///   results drawn, including the first search's keyword load;
    /// - "emojiSearchQuery", from a change to the query to the frame with its results drawn.
    /// The keyboard extension begins a signpost interval here. Without it nothing is timed.
    public var startMeasure: ((_ name: StaticString) -> @MainActor @Sendable () -> Void)?
    /// Called once, after the first render that drew keys. The keyboard extension ends its startup measurement with it.
    public var onFirstKeysDrawn: (() -> Void)?

    private let controller: KeyboardController
    /// Haptics and sound for the emoji panel's taps; the controller plays the keys' own.
    private let feedback: any FeedbackSink
    private let emojiPreferences: EmojiPreferences
    /// The emoji panel, once it has opened.
    private var emojiPanel: EmojiPanelView?
    /// The search field above the panel and above search's results, once the panel has opened.
    private var searchField: EmojiSearchField?
    /// Search's results, once search has opened.
    private var searchResults: EmojiSearchResultsView?
    /// What shows below the suggestion row now.
    private var shownPanel = KeyboardPanel.keys
    /// Whether this view has asked for the emoji font warm-up, which it does once, after its keys are first drawn.
    private var hasScheduledFontWarmup = false
    private let keysLayer = CALayer()
    private let previewLayer = KeyPreviewLayer()
    private let alternatesLayer = AlternatesLayer()
    /// One layer per key, indexed by key id.
    private var keyLayers: [KeyLayer] = []
    /// The key icons, rendered once for the theme and scale and reused by every rebuild of the keys.
    private let iconCache = KeyIconCache()
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

    /// The keyboard for `controller`. The emoji panel plays `feedback` on its taps and keeps Recent and skin tones in
    /// `emojiPreferences`.
    public init(controller: KeyboardController, feedback: any FeedbackSink, emojiPreferences: EmojiPreferences) {
        self.controller = controller
        self.feedback = feedback
        self.emojiPreferences = emojiPreferences
        super.init(frame: .zero)
        isMultipleTouchEnabled = true
        liveTouchIDs.reserveCapacity(Self.touchCapacity)
        // Not `.clear`: iOS drops touches on fully transparent parts of a keyboard extension, which would lose taps
        // in the gaps between keys (ruling R9 sends them to the nearest key) and in the suggestion row (ruling M3-R8).
        backgroundColor = .touchableClear
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
        layOutEmojiViews()
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        // A touch whose lift was lost on the way out would otherwise leave cursor mode on (every touch ignored)
        // or a backspace repeat due, which would replay every missed delete once the timer runs again.
        // So every touch ends here, before the timer can restart.
        liveTouchIDs.removeAll(keepingCapacity: true)
        controller.cancelAllTouches()
        emojiPanel?.endInteractions()
        searchResults?.endInteractions()
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
        measuring("render") { renderNow() }
    }

    private func renderNow() {
        let state = controller.state
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if controller.frames != builtFrames { buildKeys() }
        updateKeys(to: state)
        updatePreview(state)
        updateAlternates(state)
        updatePanel(state)
        CATransaction.commit()
        renderedState = state
        updateTimer()
        if !keyLayers.isEmpty, let onFirstKeysDrawn {
            self.onFirstKeysDrawn = nil
            onFirstKeysDrawn()
        }
        // After startup is measured and the keys are drawn, the emoji font loads in the background (ruling M3-R12).
        if !keyLayers.isEmpty && !hasScheduledFontWarmup {
            hasScheduledFontWarmup = true
            EmojiFontWarmup.scheduleIfNeeded(scale: displayScale) { [weak self] in self?.emojiPreferences.recents ?? [] }
        }
    }

    /// Throws away every key layer and icon and draws again, for a new theme or screen scale.
    private func rebuild() {
        iconCache.removeAll()
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
                hint: Self.cornerHint(of: frame, lastRow: lastRow), theme: theme, scale: scale, icons: iconCache)
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

    /// Labels follow the shift shown (none in emoji search), cursor mode and the return key type; highlights follow the
    /// pressed keys.
    private func updateKeys(to state: KeyboardState) {
        let old = renderedState
        if old?.shownShift != state.shownShift || old?.cursorMode != state.cursorMode
            || old?.returnKey != state.returnKey || old?.panel != state.panel
        {
            for (frame, keyLayer) in zip(controller.frames, keyLayers) {
                keyLayer.setLabel(Self.label(of: frame.key, in: state))
                keyLayer.setLabelsHidden(state.cursorMode)
                keyLayer.setActive(frame.key.action == .shift && state.shownShift != .off)
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

    // MARK: Emoji panel and search

    /// Frees what the emoji panel and search keep while they are closed: search's results and the search keywords
    /// unless search shows, and the panel, its cells and the decoded emoji kept for the process while the keys show.
    /// The next open makes them and loads the data again, and the next appearance warms the emoji font again.
    /// The keyboard extension calls this on a memory warning.
    public func didReceiveMemoryWarning() {
        EmojiFontWarmup.forget()
        if shownPanel != .emojiSearch {
            searchResults?.removeFromSuperview()
            searchResults = nil
            EmojiSearchStore.shared.release()
        }
        guard shownPanel == .keys else { return }
        emojiPanel?.removeFromSuperview()
        emojiPanel = nil
        EmojiCatalogStore.shared.release()
    }

    /// For the app's preview: shows the skin popup for `emoji` as if a finger held it, in search's results while search
    /// shows, else in the emoji panel once it is open.
    public func showEmojiHoldForPreview(_ emoji: String) {
        if shownPanel == .emojiSearch {
            searchResults?.showHoldForPreview(emoji)
        } else {
            emojiPanel?.showHoldForPreview(emoji)
        }
    }

    /// Shows what the controller's `state.panel` asks for below the suggestion row (the keys, the emoji panel or search),
    /// and in search the results for its query.
    private func updatePanel(_ state: KeyboardState) {
        guard state.panel != shownPanel else {
            if state.panel == .emojiSearch { updateSearch(query: state.searchQuery) }
            return
        }
        shownPanel = state.panel
        switch state.panel {
        case .keys:
            emojiPanel?.endInteractions()
            emojiPanel?.isHidden = true
            searchResults?.endInteractions()
            searchResults?.isHidden = true
            // As a button it has no caret, so nothing blinks while it is hidden.
            searchField?.show(.button)
            searchField?.isHidden = true
            keysLayer.isHidden = false
        case .emoji:
            openEmojiPanel()
        case .emojiSearch:
            openEmojiSearch(query: state.searchQuery)
        }
    }

    /// Shows the emoji panel in place of the keys or search, with the search field above it as a button. Timed as
    /// "emojiPanelOpen", until Core Animation has committed the frame, so the emoji's first drawing counts.
    private func openEmojiPanel() {
        searchResults?.endInteractions()
        searchResults?.isHidden = true
        let endMeasure = startMeasure?("emojiPanelOpen")
        CATransaction.begin()
        // Called once the outermost transaction has committed, after the new cells' text was drawn.
        CATransaction.setCompletionBlock(endMeasure.map { end in { MainActor.assumeIsolated { end() } } })
        let emojiPanel = self.emojiPanel ?? makeEmojiPanel()
        keysLayer.isHidden = true
        emojiPanel.isHidden = false
        layOutEmojiViews()
        emojiPanel.open()
        // The field's data comes with the catalog, which the panel has just loaded.
        let searchField = self.searchField ?? makeSearchField()
        searchField.show(.button)
        searchField.isHidden = false
        emojiPanel.layoutIfNeeded()
        CATransaction.commit()
    }

    /// Shows search: the keys again (the controller has laid them out without their number row), the field with the
    /// query and the results below it. The first search in the process loads the keywords here. Timed as
    /// "emojiSearchOpen", until Core Animation has committed the frame.
    private func openEmojiSearch(query: String) {
        emojiPanel?.endInteractions()
        emojiPanel?.isHidden = true
        let searchField = self.searchField ?? makeSearchField()
        // Before the timed transaction: the caret's endless blink, added in it, would hold back its completion.
        searchField.show(.editing(query: query))
        let endMeasure = startMeasure?("emojiSearchOpen")
        CATransaction.begin()
        CATransaction.setCompletionBlock(endMeasure.map { end in { MainActor.assumeIsolated { end() } } })
        keysLayer.isHidden = false
        searchField.isHidden = false
        let searchResults = self.searchResults ?? makeSearchResults()
        searchResults.isHidden = false
        layOutEmojiViews()
        searchResults.open()
        CATransaction.commit()
    }

    /// The query changed in search: the field shows it, and the results follow. Timed as "emojiSearchQuery", until Core
    /// Animation has committed the frame with the new results drawn.
    private func updateSearch(query: String) {
        // Before the timed transaction, for the caret's blink as in `openEmojiSearch(query:)`.
        searchField?.show(.editing(query: query))
        guard let searchResults, searchResults.query != query else { return }
        let endMeasure = startMeasure?("emojiSearchQuery")
        CATransaction.begin()
        CATransaction.setCompletionBlock(endMeasure.map { end in { MainActor.assumeIsolated { end() } } })
        searchResults.show(query: query)
        CATransaction.commit()
    }

    private func makeEmojiPanel() -> EmojiPanelView {
        let layouts = controller.layouts
        let emojiPanel = EmojiPanelView(
            controller: controller, feedback: feedback, preferences: emojiPreferences,
            lettersLabel: layouts.firstKey { $0.action == .switchPage(.letters) }?.label ?? "",
            deleteLabel: layouts.firstKey { $0.action == .backspace }?.label ?? "")
        emojiPanel.theme = theme
        emojiPanel.measure = { [weak self] name, work in
            guard let self else { return work() }
            measuring(name, work)
        }
        addSubview(emojiPanel)
        self.emojiPanel = emojiPanel
        restack()
        return emojiPanel
    }

    /// The field, with its placeholder and icons from the emoji data. If the data can't be loaded, it shows none.
    private func makeSearchField() -> EmojiSearchField {
        let data = try? EmojiCatalogStore.shared.catalog().data
        let searchField = EmojiSearchField(
            placeholder: data?.searchPlaceholder ?? "", icon: data?.searchIcon ?? "",
            clearIcon: data?.searchClearIcon ?? "")
        searchField.theme = theme
        searchField.onOpen = { [weak self] in
            guard let self, controller.state.panel == .emoji else { return }
            feedback.keyDown()
            controller.openEmojiSearch()
        }
        searchField.onClear = { [weak self] in
            guard let self, controller.state.panel == .emojiSearch, !controller.state.searchQuery.isEmpty else { return }
            feedback.keyDown()
            controller.clearEmojiSearch()
        }
        addSubview(searchField)
        self.searchField = searchField
        restack()
        return searchField
    }

    private func makeSearchResults() -> EmojiSearchResultsView {
        let searchResults = EmojiSearchResultsView(controller: controller, feedback: feedback, preferences: emojiPreferences)
        searchResults.theme = theme
        searchResults.measure = { [weak self] name, work in
            guard let self else { return work() }
            measuring(name, work)
        }
        searchResults.onTyped = { [weak self] in self?.emojiPanel?.emojiTypedElsewhere() }
        addSubview(searchResults)
        self.searchResults = searchResults
        restack()
        return searchResults
    }

    /// Orders what overlaps, bottom to top: the search field; search's results, whose skin popup reaches up over the
    /// field; the emoji panel, whose skin popup does too; then the key preview and the long-press popup, which reach up
    /// from the top letter row over the results.
    private func restack() {
        for view in [searchField, searchResults, emojiPanel] {
            if let view { bringSubviewToFront(view) }
        }
        layer.addSublayer(previewLayer)
        layer.addSublayer(alternatesLayer)
    }

    /// The panel fills the view below the suggestion row, so the keyboard keeps its height. The field fills the
    /// suggestion row's band, and the results the number row's, down to the middle of the gap above the letters, where
    /// the top letter row's touch band begins.
    private func layOutEmojiViews() {
        let metrics = controller.metrics
        let top = min(CGFloat(metrics.suggestionRowHeight), bounds.height)
        let resultsBottom = min(
            CGFloat(metrics.suggestionRowHeight + metrics.numberRowHeight + metrics.rowGap / 2), bounds.height)
        let frames: [(UIView?, CGRect)] = [
            (emojiPanel, CGRect(x: 0, y: top, width: bounds.width, height: bounds.height - top)),
            (searchField, CGRect(x: 0, y: 0, width: bounds.width, height: top)),
            (searchResults, CGRect(x: 0, y: top, width: bounds.width, height: max(resultsBottom - top, 0))),
        ]
        for case let (view?, frame) in frames where view.frame != frame {
            view.frame = frame
        }
    }

    /// What `key` shows: letters in capitals while shift shows as on, ⇪ for caps lock, and the field's return label.
    /// In emoji search no shift shows, and return reads as a plain return key: it goes back to the panel, not to the
    /// field's action, such as Send.
    private static func label(of key: KeySpec, in state: KeyboardState) -> String {
        switch key.action {
        case .character where state.shownShift != .off && key.output.count == 1:
            key.label.uppercased()
        case .shift where state.shownShift == .locked:
            capsLockLabel
        case .returnKey:
            ReturnKeyLabel.text(for: state.panel == .emojiSearch ? .standard : state.returnKey)
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
        return KeyStyle(isSpecial: isSpecial, dimsLabel: isSpace, fontSize: fontSize, icon: key.icon)
    }

    /// Corner hints go only on the letter and symbol rows between the number row (row 0) and the bottom row
    /// (`lastRow`), as ruling R3 says.
    private static func cornerHint(of frame: KeyFrame, lastRow: Int?) -> String? {
        frame.row > 0 && frame.row != lastRow ? frame.key.cornerHint : nil
    }

    // MARK: Touches

    public override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let onTouchDown {
            let bottomRow = controller.frames.last?.row
            for touch in touches {
                let row = controller.key(at: point(of: touch))?.row
                onTouchDown(touch.timestamp, row != nil && row == bottomRow)
            }
        }
        measuring("touch") {
            if let stillDown = event?.allTouches { cancelLostTouches(stillDown: stillDown) }
            forward(touches) { controller.touchDown($0, at: $1, time: $2) }
            for touch in touches { liveTouchIDs.insert(Self.id(of: touch)) }
        }
    }

    public override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        measuring("touch") {
            forward(touches) { controller.touchMoved($0, to: $1, time: $2) }
        }
    }

    public override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        measuring("touch") {
            forward(touches) { controller.touchUp($0, at: $1, time: $2) }
            for touch in touches { liveTouchIDs.remove(Self.id(of: touch)) }
        }
    }

    public override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        measuring("touch") {
            forward(touches) { id, _, _ in controller.touchCancelled(id) }
            for touch in touches { liveTouchIDs.remove(Self.id(of: touch)) }
        }
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

    /// Runs `work` through `measure` when the host set one.
    private func measuring(_ name: StaticString, _ work: () -> Void) {
        if let measure {
            measure(name, work)
        } else {
            work()
        }
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
