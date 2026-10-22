// UIKit only, so that `swift test` still builds the package on macOS.
#if canImport(UIKit)
import KeyboardCore
import UIKit

/// The emoji panel's bottom bar: ABC on the left, a tab per section in the middle, and ⌫ on the right.
///
/// It handles its own touches and reports what they do through `onAction`. Each acts on touch-down, like the keyboard's
/// page keys. ⌫ repeats while held, with the keyboard's backspace timings. The labels come from the layout data and
/// the tab icons (SF Symbols) from the emoji data.
final class EmojiTabBar: UIView {
    enum Action: Equatable {
        /// ABC: back to the keys.
        case letters
        /// The tab for section `index` (0 is Recent).
        case tab(Int)
        /// ⌫: the first delete of a press, or a repeat while it is held.
        case delete(isRepeat: Bool)
    }

    /// The width of ABC and ⌫, as a share of the bar's width, and never less than `minimumSideWidth`.
    private static let sideShare: CGFloat = 0.13, minimumSideWidth: CGFloat = 44
    /// ABC's text size and ⌫'s, as on the keys.
    private static let lettersFontSize: CGFloat = 15, deleteFontSize: CGFloat = 21
    /// Tab icons are drawn to sit beside text of this size (see `KeyIconCache`).
    private static let iconFontSize: CGFloat = 19
    /// The rounded highlight behind the current tab and behind ⌫ while it is held.
    private static let highlightSize = CGSize(width: 32, height: 30), highlightCornerRadius: CGFloat = 8

    var onAction: ((Action) -> Void)?
    var theme: KeyboardTheme = .light {
        didSet {
            guard theme != oldValue else { return }
            applyTheme()
        }
    }

    private let lettersLabel = UILabel()
    private let deleteLabel = UILabel()
    private let tabHighlight = CALayer()
    private let deleteHighlight = CALayer()
    private var tabIcons: [CALayer] = []
    private var iconNames: [String] = []
    private var selectedTab: Int?
    private let icons = KeyIconCache()
    /// The touch holding ⌫, and the timer repeating its deletes.
    private var deleteTouch: UITouch?
    private var repeatTimer: Timer?

    init(lettersLabel letters: String, deleteLabel delete: String) {
        super.init(frame: .zero)
        isMultipleTouchEnabled = true
        for layer in [tabHighlight, deleteHighlight] {
            layer.cornerRadius = Self.highlightCornerRadius
            layer.isHidden = true
            self.layer.addSublayer(layer)
        }
        lettersLabel.text = letters
        lettersLabel.font = .systemFont(ofSize: Self.lettersFontSize)
        deleteLabel.text = delete
        deleteLabel.font = .systemFont(ofSize: Self.deleteFontSize)
        for label in [lettersLabel, deleteLabel] {
            label.textAlignment = .center
            addSubview(label)
        }
        applyTheme()
        // Icons are drawn for the screen's scale.
        registerForTraitChanges([UITraitDisplayScale.self]) { (bar: EmojiTabBar, _: UITraitCollection) in
            bar.icons.removeAll()
            bar.updateIcons()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// The tabs' SF Symbols, one per section in order. A name the system lacks leaves its tab blank but tappable.
    func setTabs(_ names: [String]) {
        guard names != iconNames else { return }
        iconNames = names
        tabIcons.forEach { $0.removeFromSuperlayer() }
        tabIcons = names.map { _ in
            let icon = CALayer()
            layer.addSublayer(icon)
            return icon
        }
        if let selectedTab, selectedTab >= names.count { self.selectedTab = nil }
        updateIcons()
        setNeedsLayout()
    }

    /// Highlights the tab for section `index`; nil highlights none.
    func select(_ index: Int?) {
        guard index != selectedTab else { return }
        selectedTab = index
        updateIcons()
        setNeedsLayout()
    }

    /// Ends a held ⌫, so nothing repeats: when the panel closes or the keyboard leaves the screen.
    func cancelTouches() {
        deleteTouch = nil
        stopRepeating()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let side = sideWidth
        lettersLabel.frame = CGRect(x: 0, y: 0, width: side, height: bounds.height)
        deleteLabel.frame = CGRect(x: bounds.width - side, y: 0, width: side, height: bounds.height)
        deleteHighlight.frame = highlightFrame(centredIn: deleteLabel.frame)
        let scale = displayScale
        for (index, icon) in tabIcons.enumerated() {
            let tab = tabFrame(index)
            let size = icon.contents == nil ? .zero : icon.bounds.size
            icon.frame = CGRect(
                x: ((tab.midX - size.width / 2) * scale).rounded() / scale,
                y: ((tab.midY - size.height / 2) * scale).rounded() / scale, width: size.width, height: size.height)
        }
        if let selectedTab, tabIcons.indices.contains(selectedTab) {
            tabHighlight.frame = highlightFrame(centredIn: tabFrame(selectedTab))
            tabHighlight.isHidden = false
        } else {
            tabHighlight.isHidden = true
        }
        CATransaction.commit()
    }

    // MARK: Touches

    // None of these call super: the panel's touches must not reach the keyboard view behind it.

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let x = touch.location(in: self).x
            let side = sideWidth
            if x < side {
                onAction?(.letters)
            } else if x >= bounds.width - side {
                beginDelete(touch)
            } else if !tabIcons.isEmpty {
                let width = (bounds.width - 2 * side) / CGFloat(tabIcons.count)
                let index = min(max(Int((x - side) / max(width, 1)), 0), tabIcons.count - 1)
                onAction?(.tab(index))
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {}

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let deleteTouch, touches.contains(deleteTouch) { cancelTouches() }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let deleteTouch, touches.contains(deleteTouch) { cancelTouches() }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { cancelTouches() }
    }

    /// Deletes once now, then after the first-repeat delay once per repeat interval until the finger lifts.
    /// A second finger on ⌫ takes the press over.
    private func beginDelete(_ touch: UITouch) {
        stopRepeating()
        deleteTouch = touch
        deleteHighlight.isHidden = false
        onAction?(.delete(isRepeat: false))
        let timing = TouchTiming()
        let timer = Timer(
            fire: Date(timeIntervalSinceNow: timing.backspaceFirstRepeat), interval: timing.backspaceRepeat, repeats: true
        ) { [weak self] timer in
            // The run loop keeps a repeating timer alive, so one whose bar is gone stops itself.
            guard let self else { return timer.invalidate() }
            MainActor.assumeIsolated { self.onAction?(.delete(isRepeat: true)) }
        }
        // The common modes keep it firing while the emoji list scrolls.
        RunLoop.main.add(timer, forMode: .common)
        repeatTimer = timer
    }

    private func stopRepeating() {
        repeatTimer?.invalidate()
        repeatTimer = nil
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        deleteHighlight.isHidden = true
        CATransaction.commit()
    }

    // MARK: Drawing

    private var sideWidth: CGFloat {
        min(max((bounds.width * Self.sideShare).rounded(), Self.minimumSideWidth), bounds.width / 2)
    }

    private var displayScale: CGFloat {
        max(traitCollection.displayScale, 1)
    }

    private func tabFrame(_ index: Int) -> CGRect {
        let side = sideWidth
        let width = (bounds.width - 2 * side) / CGFloat(max(tabIcons.count, 1))
        return CGRect(x: side + CGFloat(index) * width, y: 0, width: width, height: bounds.height)
    }

    private func highlightFrame(centredIn rect: CGRect) -> CGRect {
        let size = CGSize(width: min(Self.highlightSize.width, rect.width), height: min(Self.highlightSize.height, rect.height))
        return CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height)
    }

    private func applyTheme() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        lettersLabel.textColor = theme.label
        deleteLabel.textColor = theme.label
        tabHighlight.backgroundColor = theme.specialKey.cgColor
        deleteHighlight.backgroundColor = theme.specialKey.cgColor
        CATransaction.commit()
        icons.removeAll()
        updateIcons()
    }

    /// Draws each tab's icon: the current tab's in the label colour, the others in the hint colour.
    private func updateIcons() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let scale = displayScale
        for (index, (name, icon)) in zip(iconNames, tabIcons).enumerated() {
            let color = index == selectedTab ? theme.label : theme.hint
            let image = icons.image(named: name, fontSize: Self.iconFontSize, color: color, scale: scale)
            icon.contents = image
            icon.contentsScale = scale
            icon.bounds.size = image.map { CGSize(width: CGFloat($0.width) / scale, height: CGFloat($0.height) / scale) } ?? .zero
        }
        CATransaction.commit()
    }
}
#endif
