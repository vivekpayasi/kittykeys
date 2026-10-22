// UIKit only, so that `swift test` still builds the package on macOS.
#if canImport(UIKit)
import KeyboardCore
import OSLog
import UIKit

/// The emoji panel, shown in place of the keys below the suggestion row (design §7, ruling M3-R4): one vertical list of
/// every category with Recent first, and an `EmojiTabBar` below it.
///
/// - **List:** a `UICollectionView` with reused cells, so only the emoji on screen are drawn. Columns are about
///   `minimumCellWidth` wide. Section titles come from the emoji data. Recent is hidden while empty.
/// - **Tap** an emoji to type it in the skin tone picked for it before. **Hold** one with skin tones for the long-press
///   delay to pick another from a `SkinTonePopup`, sliding along it; the lift types the choice and remembers it. The
///   popup opens on the tone the cell shows, under the finger (ruling M3-R10), so a hold lifted without sliding types it.
/// - **Recent** is refreshed lazily, never during a tap: when the panel opens, before a jump to it, and while it is
///   scrolled off the top, with the list moved by the change so nothing on screen shifts.
/// - **Data:** the catalog comes from `EmojiCatalogStore.shared`, decoded the first time any panel opens and kept for
///   the keyboard process (ruling M3-R11). If it can't be loaded the list stays empty, and ABC and ⌫ still work.
/// - Nothing types while the controller has the keys showing: a lift that arrives after the panel closed does nothing.
///   `endInteractions()` ends a hold and a held ⌫.
final class EmojiPanelView: UIView, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    private static let logger = Logger(subsystem: "catkeys", category: "emoji")
    private static let tabBarHeight: CGFloat = 40
    /// Columns are as many as fit at this width or more; 8 on a 390-point-wide iPhone.
    private static let minimumCellWidth: CGFloat = 46
    private static let rowHeight: CGFloat = 44
    private static let headerHeight: CGFloat = 26
    /// Space beside the list, as beside the keys, and below each section.
    private static let sideInset: CGFloat = 3, sectionBottomInset: CGFloat = 6
    /// The skin popup's widest cell.
    private static let preferredPopupCellWidth = 40.0

    /// Runs a stretch of work for timing ("emojiInsert"); the keyboard view passes its own `measure` through.
    var measure: ((_ name: StaticString, _ work: () -> Void) -> Void)?
    var theme: KeyboardTheme = .light {
        didSet {
            guard theme != oldValue else { return }
            applyTheme()
        }
    }

    private let controller: KeyboardController
    private let feedback: any FeedbackSink
    private let preferences: EmojiPreferences
    private let layout = UICollectionViewFlowLayout()
    private let collectionView: UICollectionView
    private let tabBar: EmojiTabBar
    private let popup = SkinTonePopup()
    private let hold = UILongPressGestureRecognizer()
    private let holdGate = HoldGate()

    /// The emoji data, from the shared store; nil before the first open or after a failed load.
    private var catalog: EmojiCatalogStore.Catalog?
    private var loadFailed = false
    /// What Recent shows: each entry's variant and its catalog item.
    private var recent: [(variant: String, item: EmojiItem)] = []
    /// Something was typed since Recent was last read, so it may be out of date.
    private var recentIsStale = false
    private var recentRefreshScheduled = false
    /// The skin choices, read once per load and kept up to date here, so cells never read the defaults.
    private var skins = EmojiSkinChoices()
    /// Emoji per row, from the width.
    private var columns = 1
    /// Each section's top in the list, worked out when first needed after a change to the list.
    private var sectionTops: [CGFloat]?
    /// The emoji held with its skin popup showing, its options (the base, then its skins) and what the finger has picked.
    private var holding: (item: EmojiItem, options: [String], pick: SkinTonePick)?

    init(
        controller: KeyboardController, feedback: any FeedbackSink, preferences: EmojiPreferences, lettersLabel: String,
        deleteLabel: String
    ) {
        self.controller = controller
        self.feedback = feedback
        self.preferences = preferences
        layout.scrollDirection = .vertical
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        tabBar = EmojiTabBar(lettersLabel: lettersLabel, deleteLabel: deleteLabel)
        super.init(frame: .zero)
        // Not `.clear`: iOS drops touches on fully transparent parts of a keyboard extension (ruling M3-R8).
        backgroundColor = .touchableClear
        // The popup reaches up over the suggestion row when the held emoji is near the top.
        clipsToBounds = false

        collectionView.backgroundColor = .touchableClear
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.showsVerticalScrollIndicator = false
        // No scroll edge effects: on iOS 27 the top one fades the top half of the first section title (seen on the
        // iPhone). The suggestion row above and the tab bar below need no blur to stay readable.
        collectionView.topEdgeEffect.isHidden = true
        collectionView.bottomEdgeEffect.isHidden = true
        // Highlight a pressed emoji at once; a drag still scrolls, and cancels the press.
        collectionView.delaysContentTouches = false
        collectionView.register(EmojiCell.self, forCellWithReuseIdentifier: EmojiCell.reuseIdentifier)
        collectionView.register(
            EmojiSectionHeader.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
            withReuseIdentifier: EmojiSectionHeader.reuseIdentifier)
        collectionView.dataSource = self
        collectionView.delegate = self

        hold.addTarget(self, action: #selector(holdChanged(_:)))
        holdGate.shouldBegin = { [weak self] in self?.holdShouldBegin($0) ?? false }
        hold.delegate = holdGate
        collectionView.addGestureRecognizer(hold)

        tabBar.onAction = { [weak self] action in self?.perform(action) }
        addSubview(collectionView)
        addSubview(tabBar)
        addSubview(popup)
        applyTheme()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// The controller shows the panel. Nothing types unless this holds.
    private var isOpen: Bool {
        controller.state.panel == .emoji
    }

    // MARK: Opening and closing

    /// The panel is about to show: loads the emoji the first time, brings Recent up to date, and takes the hold
    /// delay from the settings.
    func open() {
        // The list needs its size before it can place sections.
        layoutIfNeeded()
        hold.minimumPressDuration = controller.settings.longPressDelay
        if catalog == nil && !loadFailed {
            load()
        } else if recentIsStale {
            // At the very top, Recent shows as it now is; scrolled down, the visible emoji stay where they are.
            refreshRecent(keepingVisibleContent: collectionView.contentOffset.y > 0)
        }
        updateSelectedTab()
    }

    /// The panel is hidden, or the keyboard leaves the screen: a hold, a held ⌫ and a scroll in progress all end.
    func endInteractions() {
        // Disabling a recognizer cancels it, which hides the popup.
        hold.isEnabled = false
        hold.isEnabled = true
        holding = nil
        popup.hide()
        tabBar.cancelTouches()
        // Stopped inside the list's range, so a rubber-band past an end doesn't stay frozen there.
        let maxOffset = max(collectionView.contentSize.height - collectionView.bounds.height, 0)
        let y = min(max(collectionView.contentOffset.y, 0), maxOffset)
        collectionView.setContentOffset(CGPoint(x: collectionView.contentOffset.x, y: y), animated: false)
    }

    /// For the app's preview: scrolls `emoji`'s cell into view and shows its skin popup as if a finger held it there.
    /// An emoji without skin tones is only scrolled to.
    func showHoldForPreview(_ emoji: String) {
        guard let catalog, let found = catalog.index.lookup(emoji) else { return }
        for (offset, category) in catalog.data.categories.enumerated() {
            guard let item = category.items.firstIndex(where: { $0.base == found.item.base }) else { continue }
            let indexPath = IndexPath(item: item, section: offset + 1)
            collectionView.scrollToItem(at: indexPath, at: .centeredVertically, animated: false)
            collectionView.layoutIfNeeded()
            if !found.item.skins.isEmpty, let shown = self.emoji(at: indexPath)?.variant,
                let cell = collectionView.layoutAttributesForItem(at: indexPath)
            {
                let rect = convert(cell.frame, from: collectionView)
                showPopup(for: found.item, showing: shown, above: rect, fingerX: Double(rect.midX))
            }
            return
        }
    }

    private func load() {
        do {
            let catalog = try EmojiCatalogStore.shared.catalog()
            self.catalog = catalog
            skins = preferences.skinChoices
            recent = resolvedRecent()
            recentIsStale = false
            tabBar.setTabs([catalog.data.recentIcon] + catalog.data.categories.map(\.icon))
        } catch {
            loadFailed = true
            let reason = String(describing: error)
            Self.logger.error("Couldn't load the emoji, so the panel stays empty: \(reason, privacy: .public)")
        }
        sectionTops = nil
        collectionView.reloadData()
    }

    // MARK: Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        let listHeight = max(bounds.height - Self.tabBarHeight, 0)
        tabBar.frame = CGRect(x: 0, y: listHeight, width: bounds.width, height: bounds.height - listHeight)
        if collectionView.frame.size != CGSize(width: bounds.width, height: listHeight) {
            collectionView.frame = CGRect(x: 0, y: 0, width: bounds.width, height: listHeight)
        }
        let available = bounds.width - 2 * Self.sideInset
        // Clamped while still a CGFloat: `Int(_:)` traps on NaN, and a crash kills the keyboard.
        let columns = available.isFinite ? Int(min(max(available / Self.minimumCellWidth, 1), 100)) : 1
        // Whole points, so the flow layout fits exactly `columns` to a row.
        let itemSize = CGSize(width: max((available / CGFloat(columns)).rounded(.down), 1), height: Self.rowHeight)
        if layout.itemSize != itemSize || self.columns != columns {
            layout.itemSize = itemSize
            self.columns = columns
            sectionTops = nil
        }
    }

    // MARK: Touches

    // None of these call super: a touch the list passes up must not reach the keyboard view behind the panel.

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {}
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {}
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {}
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {}

    // MARK: Data source

    func numberOfSections(in collectionView: UICollectionView) -> Int {
        catalog.map { $0.data.categories.count + 1 } ?? 0
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        guard let catalog else { return 0 }
        if section == 0 { return recent.count }
        return catalog.data.categories.indices.contains(section - 1) ? catalog.data.categories[section - 1].items.count : 0
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: EmojiCell.reuseIdentifier, for: indexPath)
        (cell as? EmojiCell)?.show(emoji(at: indexPath)?.variant ?? "", theme: theme)
        return cell
    }

    func collectionView(
        _ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath
    ) -> UICollectionReusableView {
        let header = collectionView.dequeueReusableSupplementaryView(
            ofKind: kind, withReuseIdentifier: EmojiSectionHeader.reuseIdentifier, for: indexPath)
        (header as? EmojiSectionHeader)?.show(title(of: indexPath.section), theme: theme)
        return header
    }

    func collectionView(
        _ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout,
        referenceSizeForHeaderInSection section: Int
    ) -> CGSize {
        isHiddenSection(section) ? .zero : CGSize(width: collectionView.bounds.width, height: Self.headerHeight)
    }

    func collectionView(
        _ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout,
        insetForSectionAt section: Int
    ) -> UIEdgeInsets {
        isHiddenSection(section)
            ? .zero
            : UIEdgeInsets(top: 0, left: Self.sideInset, bottom: Self.sectionBottomInset, right: Self.sideInset)
    }

    /// Recent while it is empty takes no room at all.
    private func isHiddenSection(_ section: Int) -> Bool {
        section == 0 && recent.isEmpty
    }

    /// The emoji a cell shows and its catalog item: Recent's exact variant, or the skin tone picked for a category's emoji.
    private func emoji(at indexPath: IndexPath) -> (variant: String, item: EmojiItem)? {
        guard let catalog else { return nil }
        if indexPath.section == 0 {
            return recent.indices.contains(indexPath.item) ? recent[indexPath.item] : nil
        }
        let categories = catalog.data.categories
        guard categories.indices.contains(indexPath.section - 1) else { return nil }
        let items = categories[indexPath.section - 1].items
        guard items.indices.contains(indexPath.item) else { return nil }
        let item = items[indexPath.item]
        return (skins.preferredVariant(for: item), item)
    }

    private func title(of section: Int) -> String {
        guard let catalog else { return "" }
        if section == 0 { return catalog.data.recentName }
        return catalog.data.categories.indices.contains(section - 1) ? catalog.data.categories[section - 1].name : ""
    }

    // MARK: Tapping

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: false)
        guard isOpen, let (variant, item) = emoji(at: indexPath) else { return }
        measuring("emojiInsert") {
            feedback.keyDown()
            controller.insertEmoji(variant)
            preferences.recordUse(variant, base: item.base)
        }
        recentIsStale = true
    }

    private func perform(_ action: EmojiTabBar.Action) {
        switch action {
        case .letters:
            feedback.keyDown()
            controller.closePanel()
        case .tab(let section):
            feedback.keyDown()
            scroll(toSection: section)
        case .delete(let isRepeat):
            if !isRepeat { feedback.keyDown() }
            controller.deleteFromPanel()
        }
    }

    // MARK: Skin tones

    /// Only an emoji with skin tones can be held. Holding another one and lifting types it, as a tap does.
    private func holdShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        let point = gestureRecognizer.location(in: collectionView)
        guard isOpen, let indexPath = collectionView.indexPathForItem(at: point) else { return false }
        return !(emoji(at: indexPath)?.item.skins.isEmpty ?? true)
    }

    @objc private func holdChanged(_ recognizer: UILongPressGestureRecognizer) {
        let x = Double(recognizer.location(in: self).x)
        switch recognizer.state {
        case .began:
            let point = recognizer.location(in: collectionView)
            guard isOpen, let indexPath = collectionView.indexPathForItem(at: point),
                let (shown, item) = emoji(at: indexPath), !item.skins.isEmpty,
                let cell = collectionView.layoutAttributesForItem(at: indexPath)
            else { return }
            showPopup(for: item, showing: shown, above: convert(cell.frame, from: collectionView), fingerX: x)
            // A haptic only, without the key click.
            if holding != nil { feedback.cursorTick() }
        case .changed:
            guard var holding else { return }
            holding.pick.move(toX: x)
            self.holding = holding
            popup.select(holding.pick.selected)
        case .ended:
            guard var holding else { return }
            self.holding = nil
            popup.hide()
            holding.pick.move(toX: x)
            let option = holding.pick.selected
            guard isOpen, holding.options.indices.contains(option) else { return }
            let variant = holding.options[option]
            let base = holding.item.base
            measuring("emojiInsert") {
                controller.insertEmoji(variant)
                preferences.setPreferredVariant(variant, for: base)
                preferences.recordUse(variant, base: base)
            }
            skins.setPreferredVariant(variant, for: base)
            showPickedSkin(of: base)
            recentIsStale = true
        default:
            holding = nil
            popup.hide()
        }
    }

    /// Shows `item`'s base and skins above `cell` (in this view's coordinates), inside the keyboard view, with `shown`
    /// (the variant the cell shows) under `fingerX` and highlighted.
    private func showPopup(for item: EmojiItem, showing shown: String, above cell: CGRect, fingerX: Double) {
        let options = [item.base] + item.skins
        let keyboard = superview.map { convert($0.bounds, from: $0) } ?? bounds
        let minX = Double(keyboard.minX + SkinTonePopup.padding), maxX = Double(keyboard.maxX - SkinTonePopup.padding)
        let cellWidth = SkinTonePopupLayout.cellWidth(
            count: options.count, available: maxX - minX, preferred: Self.preferredPopupCellWidth)
        let layout = SkinTonePopupLayout(
            count: options.count, anchor: options.firstIndex(of: shown) ?? 0, cellWidth: cellWidth, fingerX: fingerX,
            minX: minX, maxX: maxX)
        popup.show(options, layout: layout, above: cell, minY: keyboard.minY, theme: theme)
        guard !popup.isHidden else { return }
        let pick = SkinTonePick(layout: layout, fingerX: fingerX)
        popup.select(pick.selected)
        holding = (item, options, pick)
    }

    /// Redraws the category cells on screen that show `base`, after a new skin tone was picked for it.
    private func showPickedSkin(of base: String) {
        for indexPath in collectionView.indexPathsForVisibleItems where indexPath.section > 0 {
            guard let shown = emoji(at: indexPath), shown.item.base == base else { continue }
            (collectionView.cellForItem(at: indexPath) as? EmojiCell)?.show(shown.variant, theme: theme)
        }
    }

    // MARK: Recent

    /// Recent from the preferences, each entry matched to its catalog item. Entries the catalog lacks are left out.
    private func resolvedRecent() -> [(variant: String, item: EmojiItem)] {
        guard let catalog else { return [] }
        return preferences.recents.compactMap { emoji in
            catalog.index.lookup(emoji).map { (variant: $0.variant, item: $0.item) }
        }
    }

    /// Reads Recent again. With `keepingVisibleContent`, the list moves by however much Recent grew or shrank, so
    /// the emoji on screen stay put; for use while Recent is off the top of the list.
    private func refreshRecent(keepingVisibleContent: Bool) {
        recentIsStale = false
        guard catalog != nil else { return }
        let fresh = resolvedRecent()
        guard fresh.map(\.variant) != recent.map(\.variant) else { return }
        let oldTop = sectionTop(1)
        let offset = collectionView.contentOffset.y
        recent = fresh
        sectionTops = nil
        UIView.performWithoutAnimation {
            collectionView.reloadSections(IndexSet(integer: 0))
            collectionView.layoutIfNeeded()
        }
        guard keepingVisibleContent else { return }
        let maxOffset = max(collectionView.contentSize.height - collectionView.bounds.height, 0)
        let moved = offset + sectionTop(1) - oldTop
        collectionView.contentOffset.y = min(max(moved, 0), maxOffset)
    }

    /// Refreshes a stale Recent once it is entirely above the visible part of the list, on the next turn of the run
    /// loop rather than inside the scroll callback.
    private func refreshRecentIfOffScreen() {
        guard recentIsStale, !recentRefreshScheduled, isRecentOffScreen else { return }
        recentRefreshScheduled = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            recentRefreshScheduled = false
            guard recentIsStale, isOpen, isRecentOffScreen else { return }
            refreshRecent(keepingVisibleContent: true)
        }
    }

    private var isRecentOffScreen: Bool {
        catalog != nil && collectionView.contentOffset.y >= sectionTop(1)
    }

    // MARK: Sections and tabs

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        refreshRecentIfOffScreen()
        updateSelectedTab()
    }

    /// Jumps to the top of `section`, or as far as the list goes, and highlights its tab.
    private func scroll(toSection section: Int) {
        guard section < numberOfSections(in: collectionView) else { return }
        // Recent is about to show, so it is brought up to date first.
        if section == 0 && recentIsStale { refreshRecent(keepingVisibleContent: false) }
        collectionView.layoutIfNeeded()
        let maxOffset = max(collectionView.contentSize.height - collectionView.bounds.height, 0)
        collectionView.setContentOffset(CGPoint(x: 0, y: min(max(sectionTop(section), 0), maxOffset)), animated: false)
        // A section near the end may not reach the top, so its tab is highlighted here; an empty Recent's never is.
        if isHiddenSection(section) {
            updateSelectedTab()
        } else {
            tabBar.select(section)
        }
    }

    /// Highlights the tab of the section at the top of the visible list. An empty Recent is never highlighted.
    private func updateSelectedTab() {
        let sections = numberOfSections(in: collectionView)
        guard sections > 0 else { return tabBar.select(nil) }
        let y = collectionView.contentOffset.y + 1
        var current = recent.isEmpty && sections > 1 ? 1 : 0
        for section in current..<sections where sectionTop(section) <= y {
            current = section
        }
        tabBar.select(current)
    }

    /// Where `section` starts in the list; 0 for a section the list doesn't have. Worked out from the data the way the
    /// flow layout stacks sections (a header, whole rows, the bottom inset; nothing for a hidden Recent), so it never
    /// asks the collection view for a layout in the middle of one.
    private func sectionTop(_ section: Int) -> CGFloat {
        if sectionTops == nil {
            var top: CGFloat = 0
            sectionTops = (0..<numberOfSections(in: collectionView)).map { section in
                defer { top += sectionHeight(section) }
                return top
            }
        }
        guard let sectionTops, sectionTops.indices.contains(section) else { return 0 }
        return sectionTops[section]
    }

    private func sectionHeight(_ section: Int) -> CGFloat {
        guard !isHiddenSection(section) else { return 0 }
        let count = collectionView(collectionView, numberOfItemsInSection: section)
        let rows = (count + columns - 1) / columns
        return Self.headerHeight + CGFloat(rows) * Self.rowHeight + Self.sectionBottomInset
    }

    // MARK: Look

    private func applyTheme() {
        tabBar.theme = theme
        for case let cell as EmojiCell in collectionView.visibleCells {
            guard let indexPath = collectionView.indexPath(for: cell), let shown = emoji(at: indexPath) else { continue }
            cell.show(shown.variant, theme: theme)
        }
        let headerKind = UICollectionView.elementKindSectionHeader
        for indexPath in collectionView.indexPathsForVisibleSupplementaryElements(ofKind: headerKind) {
            let header = collectionView.supplementaryView(forElementKind: headerKind, at: indexPath)
            (header as? EmojiSectionHeader)?.show(title(of: indexPath.section), theme: theme)
        }
    }

    private func measuring(_ name: StaticString, _ work: () -> Void) {
        if let measure {
            measure(name, work)
        } else {
            work()
        }
    }
}
/// The hold gesture's delegate. A separate object, because `UIView` has a `gestureRecognizerShouldBegin(_:)` of its own.
private final class HoldGate: NSObject, UIGestureRecognizerDelegate {
    var shouldBegin: ((UIGestureRecognizer) -> Bool)?

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        shouldBegin?(gestureRecognizer) ?? false
    }
}
#endif
