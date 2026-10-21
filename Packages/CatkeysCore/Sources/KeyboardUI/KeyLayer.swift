// UIKit only, so that `swift test` still builds the package on macOS.
#if canImport(UIKit)
import UIKit

/// How a key looks, fixed when its layer is built.
struct KeyStyle {
    /// Whether the key rests in the special-key colour rather than the key colour.
    var isSpecial: Bool
    /// Whether the label uses the hint colour, as the space bar's does.
    var dimsLabel: Bool
    /// The label's size; a label too wide for the key shrinks to fit.
    var fontSize: CGFloat
}

/// One key: a rounded rectangle with a centred label and, on letter rows, a symbol in its top-right corner.
///
/// Each setter changes Core Animation properties only when its value changes. The caller wraps changes
/// in a `CATransaction` with actions disabled.
final class KeyLayer: CALayer {
    static let cornerRadius: CGFloat = 6
    private static let hintFontSize: CGFloat = 10
    /// The corner hint's distance from the key's top and right edges.
    private static let hintInset = CGSize(width: 4, height: 1)
    /// The least space kept between a label and the key's sides.
    private static let labelInset: CGFloat = 4

    private let labelLayer = CATextLayer()
    private var hintLayer: CATextLayer?
    private var keyStyle = KeyStyle(isSpecial: false, dimsLabel: false, fontSize: 0)
    private var theme = KeyboardTheme.light
    private var label = ""
    private var isPressed = false
    /// Shift is on: the shift key is lit like a pressed key.
    private var isActive = false

    /// A key at `rect` in its parent layer. `scale` is the screen's, so text stays sharp.
    init(rect: CGRect, style: KeyStyle, hint: String?, theme: KeyboardTheme, scale: CGFloat) {
        self.keyStyle = style
        self.theme = theme
        super.init()
        frame = rect
        cornerRadius = Self.cornerRadius
        shadowColor = UIColor.black.cgColor
        shadowOpacity = 0.3
        shadowOffset = CGSize(width: 0, height: 1)
        shadowRadius = 0
        shadowPath = CGPath(
            roundedRect: bounds, cornerWidth: Self.cornerRadius, cornerHeight: Self.cornerRadius, transform: nil)
        updateFill()

        labelLayer.contentsScale = scale
        labelLayer.alignmentMode = .center
        labelLayer.foregroundColor = (style.dimsLabel ? theme.hint : theme.label).cgColor
        addSublayer(labelLayer)

        if let hint {
            let hintLayer = CATextLayer()
            let font = UIFont.systemFont(ofSize: Self.hintFontSize)
            hintLayer.contentsScale = scale
            hintLayer.alignmentMode = .right
            hintLayer.font = font
            hintLayer.fontSize = font.pointSize
            hintLayer.foregroundColor = theme.hint.cgColor
            hintLayer.string = hint
            hintLayer.frame = CGRect(
                x: 0, y: Self.hintInset.height, width: bounds.width - Self.hintInset.width, height: ceil(font.lineHeight))
            addSublayer(hintLayer)
            self.hintLayer = hintLayer
        }
    }

    /// Core Animation's copy for the presentation tree; it never draws text of its own.
    override init(layer: Any) {
        super.init(layer: layer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func setLabel(_ text: String) {
        guard text != label else { return }
        label = text
        labelLayer.string = text
        let font = UIFont.systemFont(ofSize: fittedFontSize(for: text))
        let height = ceil(font.lineHeight)
        labelLayer.font = font
        labelLayer.fontSize = font.pointSize
        labelLayer.frame = CGRect(x: 0, y: ((bounds.height - height) / 2).rounded(), width: bounds.width, height: height)
    }

    /// Hides the label and the corner hint, as cursor mode does.
    func setLabelsHidden(_ hidden: Bool) {
        guard hidden != labelLayer.isHidden else { return }
        labelLayer.isHidden = hidden
        hintLayer?.isHidden = hidden
    }

    func setPressed(_ pressed: Bool) {
        guard pressed != isPressed else { return }
        isPressed = pressed
        updateFill()
    }

    func setActive(_ active: Bool) {
        guard active != isActive else { return }
        isActive = active
        updateFill()
    }

    /// A pressed or active key swaps its resting colour for the other key colour, as Apple's keys do.
    private func updateFill() {
        let lit = isPressed || isActive
        backgroundColor = (keyStyle.isSpecial == lit ? theme.key : theme.specialKey).cgColor
    }

    /// `keyStyle.fontSize`, shrunk so that `text` fits across the key.
    private func fittedFontSize(for text: String) -> CGFloat {
        let width = (text as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: keyStyle.fontSize)]).width
        let available = bounds.width - 2 * Self.labelInset
        guard width > available, width > 0 else { return keyStyle.fontSize }
        return (keyStyle.fontSize * available / width).rounded(.down)
    }
}
#endif
