// UIKit only, so that `swift test` still builds the package on macOS.
#if canImport(UIKit)
import KeyboardCore
import UIKit

/// The "Search emoji" field, in the suggestion row's band above the emoji panel and above search's results
/// (ruling M3-R15), so the keyboard keeps its height.
///
/// - **Beside the panel** it is a button: the magnifier and the placeholder. A touch anywhere on it opens search.
/// - **In search** it shows the query with a blinking caret after it, or the caret and the placeholder while the query is
///   empty, and ✕ while it isn't. A touch on ✕ empties the query.
///
/// The placeholder and both icons (SF Symbols) come from the emoji data. Touches act on touch-down, as the panel's tab
/// bar's do, and none reaches the keyboard view behind. The view's own fill is near-invisible rather than clear, so a
/// touch beside the rounded field still reaches it (ruling M3-R8).
final class EmojiSearchField: UIView {
    enum Mode: Equatable {
        /// Beside the panel: a touch opens search.
        case button
        /// In search, showing `query`.
        case editing(query: String)
    }

    /// The rounded field's distance from the band's edges.
    private static let fieldInset = UIEdgeInsets(top: 6, left: 6, bottom: 6, right: 6)
    private static let fontSize: CGFloat = 17
    /// Where the text starts, from the field's left end, after the magnifier.
    private static let textStart: CGFloat = 32
    /// The magnifier's centre, from the field's left end.
    private static let iconCentre: CGFloat = 17
    /// The room ✕ takes at the field's right end, and the margin after the text without it.
    private static let clearWidth: CGFloat = 34, textEndMargin: CGFloat = 12
    /// A touch this far left of ✕'s room still clears.
    private static let clearTouchSlack: CGFloat = 10
    private static let caretSize = CGSize(width: 2, height: 21)
    /// Seconds the caret stays lit after the query changes, and one blink's whole period.
    private static let caretSteadyTime = 0.5, blinkPeriod = 1.0
    private static let blinkKey = "blink"

    /// A touch on the field beside the panel.
    var onOpen: (() -> Void)?
    /// A touch on ✕.
    var onClear: (() -> Void)?
    var theme: KeyboardTheme = .light {
        didSet {
            guard theme != oldValue else { return }
            applyTheme()
        }
    }

    private(set) var mode = Mode.button
    private let field = CALayer()
    private let magnifier = CALayer()
    private let clearButton = CALayer()
    private let caret = CALayer()
    private let textLabel = UILabel()
    private let icons = KeyIconCache()
    private let placeholder: String
    private let iconName: String, clearIconName: String

    /// A field showing `placeholder` while empty, with the SF Symbols `icon` (the magnifier) and `clearIcon` (✕).
    init(placeholder: String, icon: String, clearIcon: String) {
        self.placeholder = placeholder
        iconName = icon
        clearIconName = clearIcon
        super.init(frame: .zero)
        // Not `.clear`: iOS drops touches on fully transparent parts of a keyboard extension (ruling M3-R8).
        backgroundColor = .touchableClear
        isMultipleTouchEnabled = true
        layer.addSublayer(field)
        layer.addSublayer(magnifier)
        layer.addSublayer(clearButton)
        textLabel.font = .systemFont(ofSize: Self.fontSize)
        textLabel.lineBreakMode = .byTruncatingHead
        addSubview(textLabel)
        caret.cornerRadius = Self.caretSize.width / 2
        caret.isHidden = true
        clearButton.isHidden = true
        layer.addSublayer(caret)
        showText(nil)
        applyTheme()
        // Icons are drawn for the screen's scale.
        registerForTraitChanges([UITraitDisplayScale.self]) { (view: EmojiSearchField, _: UITraitCollection) in
            view.icons.removeAll()
            view.updateIcons()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Shows the field as a button beside the panel, or in search with its query. The caret stays lit while the query
    /// changes, then blinks; it doesn't blink outside search.
    func show(_ mode: Mode) {
        guard mode != self.mode else { return }
        self.mode = mode
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        switch mode {
        case .button:
            caret.removeAnimation(forKey: Self.blinkKey)
            caret.isHidden = true
            clearButton.isHidden = true
            showText(nil)
        case .editing(let query):
            caret.isHidden = false
            clearButton.isHidden = query.isEmpty
            showText(query.isEmpty ? nil : query)
            restartBlinking()
        }
        CATransaction.commit()
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let fieldRect = bounds.inset(by: Self.fieldInset)
        field.frame = fieldRect
        field.cornerRadius = fittedCornerRadius(fieldRect.height / 2, for: fieldRect.size)
        field.isHidden = !hasArea(fieldRect.size)
        let scale = displayScale
        place(magnifier, centredAt: CGPoint(x: fieldRect.minX + Self.iconCentre, y: fieldRect.midY), scale: scale)
        place(clearButton, centredAt: CGPoint(x: fieldRect.maxX - Self.clearWidth / 2, y: fieldRect.midY), scale: scale)

        let textX = fieldRect.minX + Self.textStart
        let textEnd = fieldRect.maxX - (clearButton.isHidden ? Self.textEndMargin : Self.clearWidth)
        let available = max(textEnd - textX, 0)
        let lineHeight = ceil(textLabel.font.lineHeight)
        let textWidth = min(measuredWidth(of: textLabel.text ?? ""), available)
        textLabel.frame = CGRect(
            x: textX, y: (fieldRect.midY - lineHeight / 2).rounded(), width: available, height: lineHeight)
        // After the query, or just before the placeholder while the query is empty.
        let caretX = isShowingQuery ? textX + textWidth + 1 : textX - Self.caretSize.width - 1
        caret.frame = CGRect(
            x: (caretX * scale).rounded() / scale, y: (fieldRect.midY - Self.caretSize.height / 2).rounded(),
            width: Self.caretSize.width, height: Self.caretSize.height)
        CATransaction.commit()
    }

    // MARK: Touches

    // None of these call super: the field's touches must not reach the keyboard view behind it.

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        switch mode {
        case .button:
            onOpen?()
        case .editing(let query):
            let clearStart = bounds.inset(by: Self.fieldInset).maxX - Self.clearWidth - Self.clearTouchSlack
            guard !query.isEmpty, touches.contains(where: { $0.location(in: self).x >= clearStart }) else { return }
            onClear?()
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {}
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {}
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {}

    // MARK: Drawing

    private var displayScale: CGFloat {
        max(traitCollection.displayScale, 1)
    }

    /// Whether the label shows the query rather than the placeholder.
    private var isShowingQuery: Bool {
        if case .editing(let query) = mode { !query.isEmpty } else { false }
    }

    /// Shows `query`, or the placeholder when it is nil.
    private func showText(_ query: String?) {
        textLabel.text = query ?? placeholder
        textLabel.textColor = query == nil ? theme.hint : theme.label
    }

    private func measuredWidth(of text: String) -> CGFloat {
        let width = (text as NSString).size(withAttributes: [.font: textLabel.font as Any]).width
        return width.isFinite ? ceil(width) : 0
    }

    /// The caret blinks as a text field's does: lit for a moment, then on and off once a second.
    private func restartBlinking() {
        caret.removeAnimation(forKey: Self.blinkKey)
        let blink = CAKeyframeAnimation(keyPath: "opacity")
        blink.values = [1, 0]
        blink.keyTimes = [0, 0.5, 1]
        blink.calculationMode = .discrete
        blink.duration = Self.blinkPeriod
        blink.repeatCount = .infinity
        blink.isRemovedOnCompletion = false
        blink.beginTime = caret.convertTime(CACurrentMediaTime(), from: nil) + Self.caretSteadyTime
        caret.add(blink, forKey: Self.blinkKey)
    }

    private func place(_ icon: CALayer, centredAt centre: CGPoint, scale: CGFloat) {
        let size = icon.bounds.size
        icon.frame = CGRect(
            x: ((centre.x - size.width / 2) * scale).rounded() / scale,
            y: ((centre.y - size.height / 2) * scale).rounded() / scale, width: size.width, height: size.height)
    }

    private func applyTheme() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        field.backgroundColor = theme.searchField.cgColor
        caret.backgroundColor = theme.selection.cgColor
        textLabel.textColor = isShowingQuery ? theme.label : theme.hint
        CATransaction.commit()
        icons.removeAll()
        updateIcons()
    }

    /// Draws the magnifier and ✕ in the hint colour, beside text of the field's size.
    private func updateIcons() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let scale = displayScale
        for (icon, name) in [(magnifier, iconName), (clearButton, clearIconName)] {
            let image = icons.image(named: name, fontSize: Self.fontSize, color: theme.hint, scale: scale)
            icon.contents = image
            icon.contentsScale = scale
            icon.bounds.size =
                image.map { CGSize(width: CGFloat($0.width) / scale, height: CGFloat($0.height) / scale) } ?? .zero
        }
        CATransaction.commit()
        setNeedsLayout()
    }
}
#endif
