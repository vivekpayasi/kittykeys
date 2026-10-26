/// The keyboard's brain, free of UIKit. It runs the host's raw touches through a `TouchProcessor`, applies the events
/// to a `TextDocument`, and keeps the `state` and `frames` the keyboard view draws.
///
/// It applies the typing rules: shift and caps lock, automatic capitals, the double-space full stop, the user's text
/// replacements, the field's bottom row and first page, and the globe key. It opens and closes the emoji panel, and
/// types and deletes the panel's emoji as typing. In emoji search the keys type into `state.searchQuery` instead
/// (ruling M3-R15).
///
/// Times are the host's touch timestamps in seconds. The host calls `advance(to:)` before forwarding each touch,
/// and whenever `nextDeadline` passes.
@MainActor public final class KeyboardController {
    /// Seconds within which a second shift tap turns on caps lock.
    private static let shiftDoubleTapWindow = 0.3
    /// Seconds within which a second space types the full stop.
    private static let doubleSpaceWindow = 0.5
    /// What a double space becomes, replacing the first space.
    private static let doubleSpaceText = ". "
    /// The page a number field opens on.
    private static let numberPageID = "symbols-1"
    /// The longest emoji search query, in characters.
    private static let maxSearchQueryLength = 64

    public var settings: KeyboardSettings {
        didSet {
            processor.timing.longPress = settings.longPressDelay
            notifying {
                if !settings.keyPopup { state.previewKeyID = nil }
            }
        }
    }

    /// Whether the bottom row gets the layout set's globe key, just left of the emoji key.
    /// The host sets it from `needsInputModeSwitchKey`.
    public var needsGlobeKey = false {
        didSet {
            guard needsGlobeKey != oldValue else { return }
            notifying { layOutKeys() }
        }
    }

    /// The user's text replacements, which the host reads from iOS. A shortcut is replaced when a word end follows it
    /// (`TextReplacements.isTrigger(_:)`); in an email field only a space or return does, and in URL and number fields
    /// nothing does.
    public var textReplacements = TextReplacements.none

    /// Called when the globe key is typed: the host switches to the next keyboard.
    public var onGlobe: (() -> Void)?
    /// Called once after each call that changed `state` or `frames`, for the view to redraw.
    public var onChange: (() -> Void)?
    public private(set) var state: KeyboardState
    /// The current page's keys, with its bottom row. Empty until `setWidth(_:)` gives a usable width.
    public private(set) var frames: [KeyFrame] = []

    /// The keyboard's height for the current page.
    public var height: Double {
        metrics.totalHeight(rowCount: (layouts.page(state.pageID)?.rows.count ?? 0) + 1)
    }

    /// When the next timer is due, for scheduling `advance(to:)`. nil when no timer is pending.
    public var nextDeadline: Double? { processor.nextDeadline }

    /// The current key a touch at `p` would land on, by the same hit-test touches use; nil in the suggestion row
    /// or before there are keys. For measurements: it changes nothing.
    public func key(at p: Point) -> KeyFrame? {
        KeyboardGeometry.hitTest(p, in: frames, metrics: metrics)
    }

    /// The layout set the keys come from. The emoji panel copies its ABC and ⌫ labels from it.
    public let layouts: LayoutSet
    /// The sizes the keys are laid out with. The emoji panel sits below `suggestionRowHeight`.
    public let metrics: KeyboardMetrics

    private let document: any TextDocument
    private let feedback: any FeedbackSink
    private let processor: TouchProcessor
    private var width = 0.0
    private var bottomVariant = BottomVariant.standard
    /// The latest traits from `fieldDidChange(_:)` or `keyboardWillAppear(_:)`; nil before the first.
    private var traits: FieldTraits?
    /// How many fingers hold each key in `state.pressedKeyIDs`.
    private var pressCounts: [Int: Int] = [:]
    /// When shift was tapped, while it is the latest key: a second tap soon after locks caps.
    /// Any other key, edit or cursor mode, or the keyboard appearing, clears it.
    private var lastShiftTapTime: Double?
    /// Whether automatic capitals, not a tap, set the current `.once`. Only such a shift turns off by itself.
    private var shiftIsAutomatic = false
    /// While emoji search shows: the page and bottom row the panel covered, which come back when search closes.
    private var keysUnderSearch: (pageID: String, bottom: BottomVariant)?
    /// Whether `frames` are search's, without the number row.
    private var framesAreForSearch = false
    /// Whether the ⌫ that last landed in search found the query empty. Only such a ⌫ leaves search: one held while
    /// it empties the query only stops deleting.
    private var backspaceLeavesSearch = false
    /// The latest space typed, while it is the latest key typed here: when, and the text before the cursor just after it.
    /// Any other key or edit here, or cursor mode, clears it. A change made elsewhere shows up as different text before the cursor.
    private var lastSpace: (time: Double, textBefore: String?)?
    /// The latest shortcut replaced, while ⌫ can still undo it: the shortcut, how many graphemes its phrase and the word
    /// end after it take, and the text before the cursor just after. Cleared like `lastSpace`.
    private var undoableReplacement: (shortcut: String, length: Int, textBefore: String?)?
    /// The text before the cursor just after an undone replacement. A word end typed right there keeps the shortcut;
    /// any other edit here, or another field, clears it.
    private var keepShortcutAt: String?
    /// The text before the cursor when automatic capitals were last checked, which is after every edit made here.
    /// A host notice that finds the same text brings nothing new, so it leaves shift alone (ruling R34).
    private var lastSeenTextBefore: String?
    /// The time of the latest touch or `advance(to:)`.
    private var now = 0.0
    /// Counts `frames` rebuilds, so `notifying` can tell when they changed.
    private var layoutCount = 0

    public init(
        document: any TextDocument, layouts: LayoutSet, settings: KeyboardSettings, feedback: any FeedbackSink,
        metrics: KeyboardMetrics = .standard
    ) {
        self.document = document
        self.layouts = layouts
        self.settings = settings
        self.feedback = feedback
        self.metrics = metrics
        var timing = TouchTiming()
        timing.longPress = settings.longPressDelay
        processor = TouchProcessor(timing: timing, metrics: metrics)
        state = KeyboardState(
            pageID: layouts.lettersPageID, shift: .off, returnKey: .standard, pressedKeyIDs: [], previewKeyID: nil,
            alternates: nil, cursorMode: false)
        updateAutoShift()
    }

    /// Lays the keys out for a new keyboard width. The same width again does nothing.
    public func setWidth(_ width: Double) {
        guard width != self.width else { return }
        notifying {
            self.width = width
            processor.keyboardWidth = width
            layOutKeys()
        }
    }

    /// The host reports the field's traits, on focus and after every text change.
    /// New traits pick the bottom row, the page and the return key, and automatic capitals are checked again.
    /// The same traits again leave the page alone, so the user stays on the symbols page, and check capitals
    /// only if the text before the cursor changed since the controller last saw it (as `documentDidChange()`).
    public func fieldDidChange(_ traits: FieldTraits) {
        notifying {
            if traits != self.traits {
                adopt(traits)
                updateAutoShift()
            } else {
                updateAutoShiftIfTextMoved()
            }
        }
    }

    /// The keyboard is about to show. It starts afresh: no touch left from before (as `cancelAllTouches()`),
    /// the keys rather than the emoji panel or search, the field's first page and bottom row even for the same traits,
    /// shift unlocked, and no earlier shift tap or space to pair with. Then automatic capitals are checked.
    public func keyboardWillAppear(_ traits: FieldTraits) {
        notifying {
            apply(processor.cancelAll())
            if state.panel == .emojiSearch { leaveSearch() }
            state.panel = .keys
            adopt(traits)
            forgetPreviousKey()
            keepShortcutAt = nil
            state.shift = .off
            updateAutoShift()
        }
    }

    /// The host reports that the text or the cursor changed, from any source. Automatic capitals are checked again
    /// only if the text before the cursor differs from what the controller last saw: iOS also reports the
    /// controller's own edits, and checking again then would turn back on a shift the user just tapped off.
    public func documentDidChange() {
        notifying { updateAutoShiftIfTextMoved() }
    }

    /// Touches on the keys, which search has too. While the emoji panel shows, the keys under it take none: the view
    /// sends the panel's touches to the panel, and these three do nothing.
    public func touchDown(_ id: TouchID, at p: Point, time: Double) {
        guard state.panel != .emoji else { return }
        now = time
        notifying { apply(processor.touchDown(id, at: p, time: time)) }
    }

    public func touchMoved(_ id: TouchID, to p: Point, time: Double) {
        guard state.panel != .emoji else { return }
        now = time
        notifying { apply(processor.touchMoved(id, to: p, time: time)) }
    }

    public func touchUp(_ id: TouchID, at p: Point, time: Double) {
        guard state.panel != .emoji else { return }
        now = time
        notifying { apply(processor.touchUp(id, at: p, time: time)) }
    }

    public func touchCancelled(_ id: TouchID) {
        notifying { apply(processor.touchCancelled(id)) }
    }

    /// Ends every touch at once and types nothing, as when the keyboard leaves the screen or a lift never came:
    /// highlights, the preview, the popup and cursor mode go, and no timer is left to fire.
    /// The host calls it when the view leaves or rejoins a window.
    public func cancelAllTouches() {
        notifying { apply(processor.cancelAll()) }
    }

    /// Fires the touch timers due by `time`: long-press popups, cursor mode and backspace repeats.
    public func advance(to time: Double) {
        now = time
        notifying { apply(processor.advance(to: time)) }
    }

    // MARK: Emoji panel

    /// Types `emoji` as a character key would: it uses up a one-letter shift (caps lock stays; ruling M3-R6),
    /// the shift taps and space before it stop pairing up, and automatic capitals are checked again.
    /// From search too, it goes into the document, and search stays as it is.
    public func insertEmoji(_ emoji: String) {
        notifying { typeText(emoji) }
    }

    /// The panel's ⌫: deletes one grapheme, so one whole emoji, flags, skin tones and joined sequences included,
    /// with the same bookkeeping as backspace. Does nothing while the keys show, so a late repeat deletes nothing.
    public func deleteFromPanel() {
        guard state.panel == .emoji else { return }
        notifying { delete(1) }
    }

    /// ABC in the panel: the keys show again, on the page and with the shift the panel left them. Like opening it,
    /// closing ends any touch on the keys. Does nothing while the keys show.
    public func closePanel() {
        guard state.panel == .emoji else { return }
        notifying {
            apply(processor.cancelAll())
            state.panel = .keys
        }
    }

    // MARK: Emoji search

    /// "Search emoji" in the panel (ruling M3-R15): the letter keys come back, on the letters page with the standard
    /// bottom row and without the number row, whose band the results take. They type into `state.searchQuery`, which
    /// starts empty: lowercase, with no shift, automatic capitals, double-space full stop or cursor mode.
    /// The bottom row's page key reads the layout's ABC label (ruling M3-R18). It, the emoji key, return, and ⌫
    /// landing on an empty query go back to the panel. Does nothing unless the panel shows.
    public func openEmojiSearch() {
        guard state.panel == .emoji else { return }
        notifying {
            keysUnderSearch = (state.pageID, bottomVariant)
            state.panel = .emojiSearch
            state.searchQuery = ""
            processor.allowsCursorMode = false
            show(page: layouts.lettersPageID, bottom: .standard)
        }
    }

    /// ✕ in the search field: empties the query and stays in search. Does nothing outside search.
    public func clearEmojiSearch() {
        guard state.panel == .emojiSearch else { return }
        notifying { state.searchQuery = "" }
    }

    /// Back to the panel, for the search view's own way out: every touch on the keys ends, the query empties, and the
    /// keys the panel covered come back under it. Does nothing outside search.
    public func closeEmojiSearch() {
        guard state.panel == .emojiSearch else { return }
        notifying {
            apply(processor.cancelAll())
            leaveSearch()
        }
    }

    /// Search's side of leaving it: the panel shows again over the keys it covered. The caller ends the touches.
    private func leaveSearch() {
        state.panel = .emoji
        state.searchQuery = ""
        processor.allowsCursorMode = true
        let keys = keysUnderSearch ?? (layouts.lettersPageID, bottomVariant)
        keysUnderSearch = nil
        show(page: keys.pageID, bottom: keys.bottom)
    }

    /// A key typed in search. Characters and long-press options go into the query lowercased, and space as one space.
    /// Return, the page key (reading ABC) and the emoji key go back to the panel (ruling M3-R18). Shift does nothing.
    private func activateInSearch(_ key: KeySpec) {
        switch key.action {
        case .character, .space:
            appendToQuery(key.output)
        case .returnKey, .switchPage, .emoji:
            leaveSearch()
        case .globe:
            onGlobe?()
        case .shift, .backspace:
            break
        }
    }

    /// Adds `text` to the query, lowercased. A space at its start, or after another space, adds nothing, and nothing
    /// goes past `maxSearchQueryLength` characters.
    private func appendToQuery(_ text: String) {
        var length = state.searchQuery.count
        for character in text.lowercased() where length < Self.maxSearchQueryLength {
            if character.isWhitespace {
                guard let last = state.searchQuery.last, !last.isWhitespace else { continue }
                state.searchQuery.append(" ")
            } else {
                state.searchQuery.append(character)
            }
            length += 1
        }
    }

    /// ⌫ in search: deletes a character or a word from the query, as from the document. On an empty query, a ⌫ that
    /// landed on it leaves search; repeats do nothing.
    private func deleteFromQuery(word: Bool) {
        guard !state.searchQuery.isEmpty else {
            if backspaceLeavesSearch { leaveSearch() }
            return
        }
        let count = word ? max(TextRules.previousWordLength(before: state.searchQuery), 1) : 1
        state.searchQuery.removeLast(min(count, state.searchQuery.count))
    }

    // MARK: Events

    private func apply(_ events: [TouchEvent]) {
        let panelWasOpen = state.panel == .emoji
        for event in events {
            if !panelWasOpen && state.panel == .emoji {
                // The emoji key opened the panel, or return or ⌫ went back to it from search, and nothing acts under
                // it: the rest of the batch only lets go of keys. A key whose press is skipped has no count, so the
                // cancel below lets go of it quietly.
                switch event {
                case .keyUp, .cursorModeEnded: break
                default: continue
                }
            }
            apply(event)
        }
        // The emoji panel covers the keys, so no touch on them outlives its opening: their highlights, the preview,
        // the popup, cursor mode and backspace repeats end here, held keys untyped (ruling M3-R7). Ending them after
        // the batch, not at the emoji key's activation, also ends a touch that came in it, as when a lost lift opens the panel.
        if state.panel == .emoji {
            for event in processor.cancelAll() { apply(event) }
        }
        // The popup shows exactly while the processor has a finger choosing from it. A second finger on the same key
        // lifting leaves it, and the chooser's lift or cancel ends it.
        if state.alternates != nil && !processor.isShowingAlternates { state.alternates = nil }
    }

    private func apply(_ event: TouchEvent) {
        let searching = state.panel == .emojiSearch
        switch event {
        case .keyDown(let frame):
            if searching && frame.key.action == .backspace { backspaceLeavesSearch = state.searchQuery.isEmpty }
            press(frame)
        case .keyUp(let frame):
            release(frame)
        case .activate(let frame, _):
            if searching {
                activateInSearch(frame.key)
            } else {
                activate(frame.key)
            }
        case let .alternatesShown(frame, options, selected, originX):
            // Only for a key highlighted now, so the popup's id is a current key.
            guard isCurrent(frame), pressCounts[frame.id] != nil else { return }
            state.alternates = AlternatesPopup(keyID: frame.id, options: options, selected: selected, originX: originX)
        case let .alternateSelected(frame, selected):
            guard state.alternates?.keyID == frame.id, isCurrent(frame) else { return }
            state.alternates?.selected = selected
        case .activateAlternate(_, let text) where searching:
            appendToQuery(text)
        case .activateAlternate(_, let text):
            typeCharacters(text)
        case .deleteBackward(let word) where searching:
            deleteFromQuery(word: word)
        case .deleteBackward(let word):
            guard !undoReplacement() else { return }
            delete(word ? max(TextRules.previousWordLength(before: document.textBefore), 1) : 1)
        case .deleteRestOfWord where searching:
            state.searchQuery.removeLast(TextRules.trailingRunLength(before: state.searchQuery))
        case .deleteRestOfWord:
            delete(TextRules.trailingRunLength(before: document.textBefore))
        case .cursorModeBegan:
            state.cursorMode = true
            forgetPreviousKey()
        case .cursorModeEnded:
            state.cursorMode = false
            updateAutoShift()
        case .cursorMoved where searching, .cursorMovedLines where searching:
            // Search has no cursor mode, and its keys never move the document's cursor.
            break
        case .cursorMoved(let characters):
            moveCursor(by: characters, ticks: abs(characters))
        case .cursorMovedLines(let lines):
            let offset = CursorMath.verticalMove(before: document.textBefore, after: document.textAfter, lines: lines)
            moveCursor(by: offset, ticks: lines == 0 ? 0 : 1)
        }
    }

    private func activate(_ key: KeySpec) {
        let previousSpace = lastSpace, previousShiftTap = lastShiftTapTime
        forgetPreviousKey()
        switch key.action {
        case .character:
            // Shift changes a single character; a longer output such as ".com" is typed as written.
            typeCharacters(state.shift == .off || key.output.count != 1 ? key.output : key.output.uppercased())
        case .space:
            typeWordEnd(key.output) { typeSpace(key.output, after: previousSpace) }
        case .returnKey:
            typeWordEnd(key.output) { insert(key.output) }
        case .shift:
            tapShift(after: previousShiftTap)
        case .switchPage(let ref):
            show(page: layouts.resolve(ref), bottom: bottomVariant)
        case .globe:
            onGlobe?()
        case .emoji:
            // The touches still on the keys end once this batch of events is applied (see `apply(_:)`).
            state.panel = .emoji
        case .backspace:
            // Backspace deletes through its own events.
            break
        }
    }

    // MARK: Keys

    /// Whether `frame` is the key at its id in the current frames. An event's frame can come from an earlier page or width.
    private func isCurrent(_ frame: KeyFrame) -> Bool {
        frames.indices.contains(frame.id) && frames[frame.id] == frame
    }

    private func press(_ frame: KeyFrame) {
        feedback.keyDown()
        guard isCurrent(frame) else { return }
        pressCounts[frame.id, default: 0] += 1
        state.pressedKeyIDs.insert(frame.id)
        if settings.keyPopup && frame.key.action == .character { state.previewKeyID = frame.id }
    }

    /// A finger left the key. When it was the last one, the key's highlight and preview go.
    /// A key pressed before the frames were rebuilt has no count here and is ignored.
    private func release(_ frame: KeyFrame) {
        guard isCurrent(frame), let count = pressCounts[frame.id] else { return }
        guard count == 1 else {
            pressCounts[frame.id] = count - 1
            return
        }
        pressCounts[frame.id] = nil
        state.pressedKeyIDs.remove(frame.id)
        if state.previewKeyID == frame.id { state.previewKeyID = nil }
    }

    /// Takes `traits` as the field's: its return key, its bottom row, and its first page (symbols for a number field, else letters).
    /// Search keeps its own keys, and the field's show once it closes.
    private func adopt(_ traits: FieldTraits) {
        self.traits = traits
        undoableReplacement = nil
        keepShortcutAt = nil
        state.returnKey = traits.returnKey
        let variant: BottomVariant = switch traits.kind {
        case .email: .email
        case .url: .url
        case .text, .number: .standard
        }
        let page = traits.kind == .number ? Self.numberPageID : layouts.lettersPageID
        if state.panel == .emojiSearch {
            keysUnderSearch = (page, variant)
        } else {
            show(page: page, bottom: variant)
        }
    }

    /// Shows page `id` with the `variant` bottom row, laid out for search or not as `state.panel` says.
    /// A page the layout set lacks is ignored.
    private func show(page id: String, bottom variant: BottomVariant) {
        let pageChanges = layouts.page(id) != nil && (id != state.pageID || variant != bottomVariant)
        guard pageChanges || framesAreForSearch != (state.panel == .emojiSearch) else { return }
        if pageChanges {
            state.pageID = id
            bottomVariant = variant
        }
        layOutKeys()
    }

    /// Rebuilds `frames` for the current page, bottom row and width, and hands them to the touch processor.
    /// Search's frames leave out the number row. Highlights, the preview and the popup go with the old frames, whose ids
    /// may now mean other keys.
    private func layOutKeys() {
        framesAreForSearch = state.panel == .emojiSearch
        if let page = layouts.page(state.pageID) {
            frames = KeyboardGeometry.frames(
                page: page, bottom: bottomRow(of: page), width: width, metrics: metrics,
                includingNumberRows: !framesAreForSearch)
        } else {
            frames = []
        }
        processor.frames = frames
        layoutCount += 1
        pressCounts.removeAll()
        state.pressedKeyIDs.removeAll()
        state.previewKeyID = nil
        state.alternates = nil
    }

    /// The page's bottom row for the field, with the globe key just left of the emoji key when needed
    /// (second in a row without one). In search, its page key reads ABC (`searchBottomRow(_:letters:)`).
    private func bottomRow(of page: LayoutPage) -> [KeySpec] {
        var row = page.bottomRow(bottomVariant)
        if needsGlobeKey, let globe = layouts.globeKey {
            row.insert(globe, at: row.firstIndex { $0.action == .emoji } ?? min(1, row.count))
        }
        guard framesAreForSearch else { return row }
        return Self.searchBottomRow(row, letters: layouts.firstKey { $0.action == .switchPage(.letters) })
    }

    /// Search's bottom row (ruling M3-R18). Every page key there goes back to the emoji panel, so the row's first page
    /// key reads as `letters`, the layout's way back to the letters (ABC): its label and icon, in the key's own place
    /// and width. A later page key keeps its label; the letters page has none. With no such key in the layout
    /// (`letters` nil) the row is unchanged, and its page key still goes back.
    nonisolated static func searchBottomRow(_ row: [KeySpec], letters: KeySpec?) -> [KeySpec] {
        guard let letters, let index = row.firstIndex(where: \.isPageKey) else { return row }
        var row = row
        row[index].label = letters.label
        row[index].icon = letters.icon
        return row
    }

    // MARK: Text

    /// Types a character key's output or a long-press option, using up a one-letter shift.
    private func typeText(_ text: String) {
        if state.shift == .once { state.shift = .off }
        insert(text)
    }

    /// Types a character key's output or a long-press option; a word end among them replaces a shortcut before it.
    private func typeCharacters(_ text: String) {
        if TextReplacements.isTrigger(text) {
            typeWordEnd(text) { typeText(text) }
        } else {
            typeText(text)
        }
    }

    /// Types the word end `text` through `type`, first replacing a shortcut that ends the text before the cursor with
    /// its phrase. In an email field only a space or return replaces, since a "." belongs to the address; never in URL
    /// or number fields, nor right where an undo kept the shortcut. ⌫ next undoes it.
    private func typeWordEnd(_ text: String, _ type: () -> Void) {
        let textBefore = document.textBefore
        let replaces = switch (traits ?? FieldTraits()).kind {
        case .text: true
        case .email: text.first?.isWhitespace == true
        case .url, .number: false
        }
        let replacement = replaces && textBefore != keepShortcutAt
            ? textReplacements.replacement(before: textBefore) : nil
        guard let replacement, let textBefore else {
            type()
            return
        }
        document.deleteBackward(count: replacement.length)
        document.insert(replacement.phrase)
        type()
        // Only when the word end landed: a field may ignore it, as a single-line field ignores a return that sends.
        let typed = replacement.phrase + text
        guard let after = document.textBefore, after.hasSuffix(typed) else { return }
        undoableReplacement = (
            shortcut: String(textBefore.suffix(replacement.length)), length: typed.count, textBefore: after)
    }

    /// ⌫ right after a replacement puts its shortcut back, without the word end that followed it, and a word end typed
    /// right there keeps the shortcut. False when there is nothing to undo: anything typed, deleted or moved since, or
    /// another field, ends it.
    private func undoReplacement() -> Bool {
        guard let undo = undoableReplacement, document.textBefore == undo.textBefore else { return false }
        document.deleteBackward(count: undo.length)
        insert(undo.shortcut)
        keepShortcutAt = document.textBefore
        return true
    }

    /// A second space soon after a first one, after a word, replaces the first with a full stop and a space,
    /// as long as the cursor is still where the first space left it.
    private func typeSpace(_ space: String, after previousSpace: (time: Double, textBefore: String?)?) {
        let textBefore = document.textBefore
        if settings.doubleSpacePeriod, let previousSpace, now - previousSpace.time <= Self.doubleSpaceWindow,
            textBefore == previousSpace.textBefore, TextRules.isDoubleSpaceCandidate(before: textBefore) {
            document.deleteBackward(count: 1)
            insert(Self.doubleSpaceText)
        } else {
            insert(space)
        }
        lastSpace = (now, document.textBefore)
    }

    private func insert(_ text: String) {
        document.insert(text)
        forgetPreviousKey()
        keepShortcutAt = nil
        updateAutoShift()
    }

    private func delete(_ count: Int) {
        forgetPreviousKey()
        keepShortcutAt = nil
        guard count > 0 else { return }
        document.deleteBackward(count: count)
        updateAutoShift()
    }

    /// Anything typed or deleted between two spaces or two shift taps stops them pairing up, and ends the undo of a
    /// replacement.
    private func forgetPreviousKey() {
        lastSpace = nil
        lastShiftTapTime = nil
        undoableReplacement = nil
    }

    private func moveCursor(by offset: Int, ticks: Int) {
        if offset != 0 { document.moveCursor(by: offset) }
        for _ in 0..<ticks { feedback.cursorTick() }
    }

    // MARK: Shift

    /// Caps lock → off. Otherwise a tap soon after `previousTap`, a shift tap with no other key since, → caps lock,
    /// whatever shift was, so a double-tap locks caps even where an automatic capital had shift on;
    /// else once → off and off → once.
    private func tapShift(after previousTap: Double?) {
        let isDoubleTap = previousTap.map { now - $0 <= Self.shiftDoubleTapWindow } ?? false
        lastShiftTapTime = now
        switch state.shift {
        case .locked:
            state.shift = .off
        case _ where isDoubleTap:
            state.shift = .locked
        case .once:
            state.shift = .off
        case .off:
            state.shift = .once
            shiftIsAutomatic = false
        }
    }

    /// Checks automatic capitals again only if the text before the cursor changed since they were last checked,
    /// as when the user moved the cursor or another source changed the text.
    private func updateAutoShiftIfTextMoved() {
        let textBefore = document.textBefore
        guard textBefore != lastSeenTextBefore else { return }
        updateAutoShift(before: textBefore)
    }

    private func updateAutoShift() {
        updateAutoShift(before: document.textBefore)
    }

    /// Automatic capitals for `textBefore`, the text before the cursor now: shift turns on for one letter where the
    /// field asks for a capital, and an automatic one turns off where it no longer does. A shift the user tapped,
    /// and caps lock, stay as they are. Every edit here ends with this check, so `lastSeenTextBefore` follows them.
    private func updateAutoShift(before textBefore: String?) {
        lastSeenTextBefore = textBefore
        let capitalize = TextRules.shouldCapitalize(before: textBefore, mode: (traits ?? FieldTraits()).autoCap)
        switch state.shift {
        case .off where capitalize:
            state.shift = .once
            shiftIsAutomatic = true
        case .once where !capitalize && shiftIsAutomatic:
            state.shift = .off
        default:
            break
        }
    }

    // MARK: Change notices

    /// Runs `change`, then calls `onChange` once if it changed `state` or `frames`.
    private func notifying(_ change: () -> Void) {
        let oldState = state, oldLayoutCount = layoutCount
        change()
        if layoutCount != oldLayoutCount || state != oldState { onChange?() }
    }
}
