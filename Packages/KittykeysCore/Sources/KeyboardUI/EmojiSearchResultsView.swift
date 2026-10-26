// UIKit only, so that `swift test` still builds the package on macOS.
#if canImport(UIKit)
import KeyboardCore
import OSLog
import UIKit

/// Emoji search's results (ruling M3-R15): one row of emoji in the number row's band, between the search field and the
/// letter keys, which scrolls sideways. With an empty query it shows Recent; with no results it is empty.
///
/// - **Tap** a result to type it in the skin tone picked for it, as in the panel; search stays open. **Hold** one with
///   skin tones to pick another from the popup (`EmojiSkinHold`), which reaches up over the search field.
/// - **Data:** the catalog comes from `EmojiCatalogStore.shared` (the panel opened it first) and the keywords from
///   `EmojiSearchStore.shared`, which loads them the first time search opens and keeps them for the keyboard process.
///   Every query runs on the store's prepared search, made once per catalog.
/// - **Results never block typing** (ruling M3-R20). A query change only records the query. Its results show on a later
///   turn of the run loop, after the keystroke's own frame has gone out. Before that, the emoji they show first that
///   this process hasn't drawn yet are drawn off the main thread (`EmojiFontWarmup.draw`), so showing them is quick.
///   Keystrokes meanwhile replace the query, so only the latest one's results show, and results never change under a
///   finger on the row, so a lift always types the emoji it pressed.
/// - Recent and the skin tones are read when search opens. Recent is read again at the next query change after
///   something was typed, so results never reshuffle under a finger.
/// - Nothing types unless search shows, and no touch reaches the keyboard view behind.
final class EmojiSearchResultsView: UIView, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    private static let logger = Logger(subsystem: "kittykeys", category: "emoji")
    /// About how wide each result is. The width is fitted so that part of a result always shows at the row's end, which
    /// says the row scrolls. The row is the band's height, and the emoji are the panel's size.
    private static let preferredCellWidth: CGFloat = 46
    /// Space before the first result and after the last, as beside the keys.
    private static let sideInset: CGFloat = 3
    /// How often to look again whether a finger has left the row, while results wait for it.
    private static let touchRetryDelay = 0.05

    /// Runs a stretch of work for timing ("emojiInsert"); the keyboard view passes its own `measure` through.
    var measure: ((_ name: StaticString, _ work: () -> Void) -> Void)?
    /// Starts timing a stretch and returns the call that ends it: "emojiSearchQuery", from a query change (the first
    /// whose results don't show yet) to the committed frame that shows its results, and "emojiSearchDraw", the
    /// off-the-main-thread drawing of results' first-seen emoji. The keyboard view passes its own `startMeasure` through.
    var startMeasure: ((_ name: StaticString) -> @MainActor @Sendable () -> Void)?
    /// A result was typed: Recent and maybe a skin tone changed, which the panel reads again when it next opens.
    var onTyped: (() -> Void)?
    var theme: KeyboardTheme = .light {
        didSet {
            guard theme != oldValue else { return }
            skinHold.theme = theme
            for case let cell as EmojiCell in collectionView.visibleCells {
                guard let indexPath = collectionView.indexPath(for: cell), results.indices.contains(indexPath.item)
                else { continue }
                cell.show(results[indexPath.item].variant, theme: theme)
            }
        }
    }

    /// The query whose results show; nil before the first.
    private(set) var query: String?
    /// The latest query asked for whose results don't show yet; nil when they do.
    private var wantedQuery: String?
    /// The wanted query's results, once worked out.
    private var wantedResults: (query: String, results: [(variant: String, item: EmojiItem)])?
    private var isStepScheduled = false
    /// Whether emoji the wanted results show are being drawn off the main thread.
    private var isDrawing = false
    /// Ends the "emojiSearchQuery" interval of the first query change whose results don't show yet.
    private var endQueryMeasure: (@MainActor @Sendable () -> Void)?
    /// For the app's preview: the emoji to hold once the wanted results show.
    private var heldForPreview: String?

    private let controller: KeyboardController
    private let feedback: any FeedbackSink
    private let preferences: EmojiPreferences
    private let layout = UICollectionViewFlowLayout()
    private let collectionView: UICollectionView
    private let skinHold = EmojiSkinHold()
    /// The emoji data; nil if it couldn't be loaded, which leaves the row empty.
    private var catalog: EmojiCatalogStore.Catalog?
    /// What shows: each result's variant and its catalog item.
    private var results: [(variant: String, item: EmojiItem)] = []
    /// The skin choices, read once per open and kept up to date here.
    private var skins = EmojiSkinChoices()
    /// Recent's emoji as last read, for the ranking and for an empty query.
    private var recents: [String] = []
    private var recentsAreStale = true

    init(controller: KeyboardController, feedback: any FeedbackSink, preferences: EmojiPreferences) {
        self.controller = controller
        self.feedback = feedback
        self.preferences = preferences
        layout.scrollDirection = .horizontal
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        layout.sectionInset = UIEdgeInsets(top: 0, left: Self.sideInset, bottom: 0, right: Self.sideInset)
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(frame: .zero)
        // Not `.clear`: iOS drops touches on fully transparent parts of a keyboard extension (ruling M3-R8).
        backgroundColor = .touchableClear
        // The skin popup reaches up over the search field.
        clipsToBounds = false

        collectionView.backgroundColor = .touchableClear
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.alwaysBounceHorizontal = true
        // No scroll edge effects, as in the panel's list: nothing here needs a fade.
        collectionView.leftEdgeEffect.isHidden = true
        collectionView.rightEdgeEffect.isHidden = true
        collectionView.topEdgeEffect.isHidden = true
        collectionView.bottomEdgeEffect.isHidden = true
        // Highlight a pressed emoji at once; a drag still scrolls, and cancels the press.
        collectionView.delaysContentTouches = false
        collectionView.register(EmojiCell.self, forCellWithReuseIdentifier: EmojiCell.reuseIdentifier)
        collectionView.dataSource = self
        collectionView.delegate = self
        addSubview(collectionView)

        skinHold.attach(to: self, list: collectionView)
        skinHold.theme = theme
        skinHold.target = { [weak self] point in self?.holdTarget(at: point) }
        // A haptic only, without the key click.
        skinHold.onShow = { [weak self] in self?.feedback.cursorTick() }
        skinHold.onPick = { [weak self] variant, item in self?.typePicked(variant, of: item) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// The controller shows search. Nothing types unless this holds.
    private var isOpen: Bool {
        controller.state.panel == .emojiSearch
    }

    // MARK: Opening and closing

    /// Search is about to show: loads the keywords the first time, reads Recent and the skin tones again, takes the hold
    /// delay from the settings, and shows the results for the controller's query.
    func open() {
        layoutIfNeeded()
        skinHold.delay = controller.settings.longPressDelay
        skins = preferences.skinChoices
        recentsAreStale = true
        do {
            let catalog = try EmojiCatalogStore.shared.catalog()
            self.catalog = catalog
            // The first search in the process loads the keywords here.
            _ = try EmojiSearchStore.shared.prepared(for: catalog.data)
        } catch {
            let reason = String(describing: error)
            Self.logger.error("Emoji search can't load its data, so it shows only Recent: \(reason, privacy: .public)")
        }
        // Search's first frame shows the results at once (they are Recent, which the font warm-up drew).
        dropWanted()
        let query = controller.state.searchQuery
        show(query, results(for: query))
    }

    /// The query changed. Its results show later, as the type's description says. Timed as "emojiSearchQuery".
    func request(query: String) {
        guard query != (wantedQuery ?? self.query) else { return }
        wantedQuery = query
        if endQueryMeasure == nil { endQueryMeasure = startMeasure?("emojiSearchQuery") }
        scheduleStep()
    }

    /// Search is hidden, or the keyboard leaves the screen: a hold and a scroll in progress end.
    func endInteractions() {
        skinHold.cancel()
        // Stopped inside the row's range, so a rubber-band past an end doesn't stay frozen there.
        let maxOffset = max(collectionView.contentSize.width - collectionView.bounds.width, 0)
        let x = min(max(collectionView.contentOffset.x, 0), maxOffset)
        collectionView.setContentOffset(CGPoint(x: x, y: 0), animated: false)
    }

    /// For the app's preview: scrolls `emoji`'s result into view and shows its skin popup as if a finger held it there,
    /// once the results asked for show.
    func showHoldForPreview(_ emoji: String) {
        guard wantedQuery == nil else {
            heldForPreview = emoji
            return
        }
        guard let base = catalog?.index.lookup(emoji)?.item.base,
            let index = results.firstIndex(where: { $0.item.base == base })
        else { return }
        let indexPath = IndexPath(item: index, section: 0)
        collectionView.scrollToItem(at: indexPath, at: .centeredHorizontally, animated: false)
        collectionView.layoutIfNeeded()
        guard let cell = collectionView.layoutAttributesForItem(at: indexPath) else { return }
        let rect = convert(cell.frame, from: collectionView)
        let shown = results[index]
        skinHold.showForPreview(
            EmojiSkinHold.Target(item: shown.item, shown: shown.variant, cell: rect), fingerX: Double(rect.midX))
    }

    // MARK: Showing results

    /// Runs `step()` on a later turn of the run loop, after `delay` seconds; once, however often it is asked.
    private func scheduleStep(after delay: TimeInterval = 0) {
        guard !isStepScheduled else { return }
        isStepScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            MainActor.assumeIsolated { self?.step() }
        }
    }

    /// Moves the wanted query on: works out its results, draws the first-seen emoji among those that show first off the
    /// main thread (then comes back here), waits for a finger on the row to lift, and shows them. A query that changed
    /// meanwhile is worked out afresh, so stale work is dropped.
    private func step() {
        isStepScheduled = false
        guard isOpen else { return dropWanted() }
        guard let wanted = wantedQuery, !isDrawing else { return }
        let results: [(variant: String, item: EmojiItem)]
        if let worked = wantedResults, worked.query == wanted {
            results = worked.results
        } else {
            results = self.results(for: wanted)
            wantedResults = (wanted, results)
        }
        let firstSeen = EmojiFontWarmup.notYetDrawn(results.prefix(visibleCount).map(\.variant), limit: visibleCount)
        guard firstSeen.isEmpty else {
            isDrawing = true
            let endDraw = startMeasure?("emojiSearchDraw")
            EmojiFontWarmup.draw(firstSeen, scale: max(traitCollection.displayScale, 1)) { [weak self] in
                endDraw?()
                self?.isDrawing = false
                self?.step()
            }
            return
        }
        // A lift would type whatever the cell under it shows by then.
        guard !collectionView.isTracking, !collectionView.isDragging, !skinHold.isHolding else {
            return scheduleStep(after: Self.touchRetryDelay)
        }
        wantedQuery = nil
        wantedResults = nil
        let endMeasure = endQueryMeasure
        endQueryMeasure = nil
        CATransaction.begin()
        CATransaction.setCompletionBlock(endMeasure.map { end in { MainActor.assumeIsolated { end() } } })
        show(wanted, results)
        CATransaction.commit()
        if let emoji = heldForPreview {
            heldForPreview = nil
            showHoldForPreview(emoji)
        }
    }

    /// Forgets the query asked for, as when search closes or opens again; its timing ends here.
    private func dropWanted() {
        wantedQuery = nil
        wantedResults = nil
        heldForPreview = nil
        if let endMeasure = endQueryMeasure {
            endQueryMeasure = nil
            endMeasure()
        }
    }

    /// Shows `results` for `query`, scrolled to the start. Their emoji count as drawn from now on.
    private func show(_ query: String, _ results: [(variant: String, item: EmojiItem)]) {
        self.query = query
        self.results = results
        collectionView.reloadData()
        collectionView.setContentOffset(.zero, animated: false)
        collectionView.layoutIfNeeded()
        EmojiFontWarmup.markDrawn(results.prefix(visibleCount).map(\.variant))
    }

    /// About how many results show at once, with the part-shown one.
    private var visibleCount: Int {
        let count = bounds.width / max(layout.itemSize.width, 1)
        return count.isFinite ? min(max(Int(count.rounded(.up)), 1), 20) : 10
    }

    /// Recent's emoji for an empty query, else the search's matches in their picked skin tones.
    private func results(for query: String) -> [(variant: String, item: EmojiItem)] {
        guard let catalog else { return [] }
        if recentsAreStale {
            recents = preferences.recents
            recentsAreStale = false
        }
        guard !query.isEmpty else {
            return recents.compactMap { emoji in catalog.index.lookup(emoji).map { ($0.variant, $0.item) } }
        }
        guard let search = try? EmojiSearchStore.shared.prepared(for: catalog.data) else { return [] }
        return search.results(for: query, recents: recents).map { (skins.preferredVariant(for: $0), $0) }
    }

    // MARK: Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        if collectionView.frame != bounds { collectionView.frame = bounds }
        // As tall as the row, in whole points, and never empty: the flow layout needs a positive size.
        let height = bounds.height.isFinite ? max(bounds.height.rounded(.down), 1) : 1
        // As many whole results as fit at about the preferred width, and half of one more, so the last one shows cut
        // off: 8.5 on a 390-point-wide iPhone (45 points each), 9.5 on a 440-point one (46).
        let available = bounds.width - Self.sideInset
        var width = Self.preferredCellWidth
        if available.isFinite, available > Self.preferredCellWidth {
            let whole = (available / Self.preferredCellWidth).rounded(.down)
            width = max((available / (whole + 0.5)).rounded(.down), 1)
        }
        let itemSize = CGSize(width: width, height: height)
        if layout.itemSize != itemSize { layout.itemSize = itemSize }
    }

    // MARK: Touches

    // None of these call super: a touch the row passes up must not reach the keyboard view, which would type a letter.

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {}
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {}
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {}
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {}

    // MARK: Data source

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        results.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: EmojiCell.reuseIdentifier, for: indexPath)
        let variant = results.indices.contains(indexPath.item) ? results[indexPath.item].variant : ""
        (cell as? EmojiCell)?.show(variant, theme: theme)
        return cell
    }

    // MARK: Typing

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: false)
        guard isOpen, results.indices.contains(indexPath.item) else { return }
        let (variant, item) = results[indexPath.item]
        measuring("emojiInsert") {
            feedback.keyDown()
            controller.insertEmoji(variant)
            preferences.recordUse(variant, base: item.base)
        }
        recentsAreStale = true
        onTyped?()
    }

    /// The result under `point`, in this view's coordinates, for a hold; nil unless search shows.
    private func holdTarget(at point: CGPoint) -> EmojiSkinHold.Target? {
        guard isOpen, let indexPath = collectionView.indexPathForItem(at: convert(point, to: collectionView)),
            results.indices.contains(indexPath.item), let cell = collectionView.layoutAttributesForItem(at: indexPath)
        else { return nil }
        let shown = results[indexPath.item]
        return EmojiSkinHold.Target(item: shown.item, shown: shown.variant, cell: convert(cell.frame, from: collectionView))
    }

    /// A hold's lift: types the picked variant and remembers it, unless search closed meanwhile. The results on screen
    /// for that emoji show the new tone.
    private func typePicked(_ variant: String, of item: EmojiItem) {
        guard isOpen else { return }
        let base = item.base
        measuring("emojiInsert") {
            controller.insertEmoji(variant)
            preferences.setPreferredVariant(variant, for: base)
            preferences.recordUse(variant, base: base)
        }
        skins.setPreferredVariant(variant, for: base)
        for index in results.indices where results[index].item.base == base {
            results[index].variant = variant
            let cell = collectionView.cellForItem(at: IndexPath(item: index, section: 0))
            (cell as? EmojiCell)?.show(variant, theme: theme)
        }
        recentsAreStale = true
        onTyped?()
    }

    private func measuring(_ name: StaticString, _ work: () -> Void) {
        if let measure {
            measure(name, work)
        } else {
            work()
        }
    }
}
#endif
