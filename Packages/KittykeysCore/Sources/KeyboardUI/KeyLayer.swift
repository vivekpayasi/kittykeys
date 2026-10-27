// UIKit only, so that `swift test` still builds the package on macOS.
#if canImport(UIKit)
import KeyboardCore
import UIKit

/// How a key looks, fixed when its layer is built.
struct KeyStyle {
    /// What the key is to the theme, which picks its colours.
    var role: KeyRole
    /// The label's size; a label too wide for the key shrinks to fit.
    var fontSize: CGFloat
    /// An SF Symbol drawn in place of the label, sized to match it. A name the system lacks leaves the label.
    var icon: String?
}

/// A corner radius that fits a rounded rectangle of `size`: at most half of either side, and never negative.
/// `CGPath(roundedRect:cornerWidth:cornerHeight:transform:)` asserts on a larger one, and a crash kills the keyboard.
/// `size` is used as given; `CGRect.width` and `height` would hide a negative size.
func fittedCornerRadius(_ radius: CGFloat, for size: CGSize) -> CGFloat {
    max(0, min(radius, size.width / 2, size.height / 2))
}

/// Whether `size` has room to draw a rounded rectangle in: both sides above 0.
func hasArea(_ size: CGSize) -> Bool {
    size.width > 0 && size.height > 0
}

/// One key: a rounded rectangle with a centred label or icon and, on letter rows, a symbol in its top-right corner.
/// The theme gives it a fill, an outline or neither (`ThemeSpec`'s rules), worked out once here; a press only switches
/// between the resting and pressed fills.
///
/// Each setter changes Core Animation properties only when its value changes. The caller wraps changes
/// in a `CATransaction` with actions disabled.
final class KeyLayer: CALayer {
    static let cornerRadius: CGFloat = 6
    private static let outlineWidth: CGFloat = 1.5
    private static let hintFontSize: CGFloat = 10
    /// The corner hint's distance from the key's top and right edges.
    private static let hintInset = CGSize(width: 4, height: 1)
    /// The least space kept between a label and the key's sides.
    private static let labelInset: CGFloat = 4

    private let labelLayer = CATextLayer()
    private var hintLayer: CATextLayer?
    /// The key's icon, drawn once in the label colour; nil for a key that shows its label.
    private var iconLayer: CALayer?
    private var labelsHidden = false
    private var keyStyle = KeyStyle(role: .letter, fontSize: 0)
    /// The label's font at the style's size, and the one for a function key's symbol label such as ⌫; a long label
    /// takes a smaller copy.
    private var labelFont = UIFont.systemFont(ofSize: 17)
    private var symbolFont = UIFont.systemFont(ofSize: 17)
    /// The fill at rest, nil for none, and while pressed or active.
    private var restingFill: CGColor?
    private var pressedFill = UIColor.clear.cgColor
    private var label = ""
    private var isPressed = false
    /// Shift is on: the shift key is lit like a pressed key.
    private var isActive = false

    /// A key at `rect` in its parent layer. `scale` is the screen's, so text stays sharp.
    /// A key with an icon takes its image from `icons`, which renders it only the first time.
    init(rect: CGRect, style: KeyStyle, hint: String?, theme: KeyboardTheme, scale: CGFloat, icons: KeyIconCache) {
        self.keyStyle = style
        let spec = theme.spec
        let role = style.role
        restingFill = spec.restingFill(role).map { UIColor(themeColor: $0).cgColor }
        pressedFill = UIColor(themeColor: spec.pressedFill(role)).cgColor
        labelFont = theme.font(ofSize: style.fontSize)
        symbolFont = theme.symbolFont(ofSize: style.fontSize)
        super.init()
        frame = rect
        let radius = fittedCornerRadius(Self.cornerRadius, for: rect.size)
        cornerRadius = radius
        if let outline = spec.outline(role) {
            borderWidth = Self.outlineWidth
            borderColor = UIColor(themeColor: outline).cgColor
        }
        // A key squeezed to nothing, as on a very narrow layout, draws nothing rather than an impossible shape.
        if !hasArea(rect.size) {
            isHidden = true
        } else if spec.hasShadow(role) {
            shadowColor = UIColor.black.cgColor
            shadowOpacity = 0.3
            shadowOffset = CGSize(width: 0, height: 1)
            shadowRadius = 0
            shadowPath = CGPath(roundedRect: bounds, cornerWidth: radius, cornerHeight: radius, transform: nil)
        }
        updateFill()

        let labelColor = UIColor(themeColor: spec.labelColor(role))
        if let icon = style.icon,
            let image = icons.image(
                named: icon, fontSize: style.fontSize, color: labelColor, scale: scale, weight: theme.symbolWeight)
        {
            let iconLayer = CALayer()
            let size = CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
            // Centred on whole pixels, so the icon stays sharp.
            iconLayer.frame = CGRect(
                origin: CGPoint(
                    x: ((bounds.width - size.width) / 2 * scale).rounded() / scale,
                    y: ((bounds.height - size.height) / 2 * scale).rounded() / scale),
                size: size)
            iconLayer.contents = image
            iconLayer.contentsScale = scale
            addSublayer(iconLayer)
            self.iconLayer = iconLayer
        } else {
            labelLayer.contentsScale = scale
            labelLayer.alignmentMode = .center
            labelLayer.foregroundColor = labelColor.cgColor
            addSublayer(labelLayer)
        }

        if let hint {
            let hintLayer = CATextLayer()
            let font = theme.hintFont(ofSize: Self.hintFontSize)
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

    /// Sets the label a key without an icon shows.
    func setLabel(_ text: String) {
        guard iconLayer == nil, text != label else { return }
        label = text
        labelLayer.string = text
        let isSymbol = keyStyle.role == .function && !text.contains { $0.isLetter || $0.isNumber }
        let base = isSymbol ? symbolFont : labelFont
        let font = base.withSize(fittedFontSize(for: text, in: base))
        let height = ceil(font.lineHeight)
        labelLayer.font = font
        labelLayer.fontSize = font.pointSize
        labelLayer.frame = CGRect(x: 0, y: ((bounds.height - height) / 2).rounded(), width: bounds.width, height: height)
    }

    /// Hides the label or icon and the corner hint, as cursor mode does.
    func setLabelsHidden(_ hidden: Bool) {
        guard hidden != labelsHidden else { return }
        labelsHidden = hidden
        labelLayer.isHidden = hidden
        iconLayer?.isHidden = hidden
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

    /// A pressed or active key shows its pressed fill: for filled keys the other key colour, as Apple's keys do.
    private func updateFill() {
        backgroundColor = isPressed || isActive ? pressedFill : restingFill
    }

    /// `keyStyle.fontSize`, shrunk so that `text` in `font` fits across the key.
    private func fittedFontSize(for text: String, in font: UIFont) -> CGFloat {
        let width = (text as NSString).size(withAttributes: [.font: font]).width
        let available = bounds.width - 2 * Self.labelInset
        guard width > available, width > 0 else { return keyStyle.fontSize }
        return (keyStyle.fontSize * available / width).rounded(.down)
    }
}

/// Key icons, each rendered once. Every page switch rebuilds the key layers, and they take their icons from here
/// rather than drawing them again. The owner empties it when the theme or screen scale changes.
final class KeyIconCache {
    /// An icon's point size, in cap heights of the key's label font. Apple's emoji key icon is about 1.2 cap heights
    /// tall beside its letters, and an SF Symbol such as the smiley is about as tall as its point size.
    private static let sizeInCapHeights: CGFloat = 1.2

    private struct Key: Hashable {
        var name: String
        var fontSize: CGFloat
        var color: UIColor
        var scale: CGFloat
        var weight: UIImage.SymbolWeight
    }

    /// Rendered icons, and nil for a name the system lacks, so a missing symbol is looked up only once too.
    private var images: [Key: CGImage?] = [:]

    /// The SF Symbol `name` in `color` and `weight`, drawn at `scale` beside labels of `fontSize`; nil when the system
    /// lacks it.
    func image(
        named name: String, fontSize: CGFloat, color: UIColor, scale: CGFloat, weight: UIImage.SymbolWeight = .regular
    ) -> CGImage? {
        let key = Key(name: name, fontSize: fontSize, color: color, scale: scale, weight: weight)
        if let cached = images[key] { return cached }
        let image = Self.render(key)
        images[key] = image
        return image
    }

    func removeAll() {
        images.removeAll()
    }

    /// The symbol's shape is always the light appearance's; the theme gives the colour. In dark mode iOS 26 swaps
    /// the smiley for a filled one, and the trait collection current while keys are built would pick that.
    private static func render(_ key: Key) -> CGImage? {
        let pointSize = UIFont.systemFont(ofSize: key.fontSize).capHeight * sizeInCapHeights
        let configuration = UIImage.SymbolConfiguration(pointSize: pointSize, weight: key.weight)
            // Only the appearance is pinned; the size and weight come from this configuration, the scale from `key`.
            .withTraitCollection(UITraitCollection(userInterfaceStyle: .light))
        guard let symbol = UIImage(systemName: key.name, withConfiguration: configuration) else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = key.scale
        format.opaque = false
        let tinted = symbol.withTintColor(key.color, renderingMode: .alwaysOriginal)
        return UIGraphicsImageRenderer(size: symbol.size, format: format).image { _ in tinted.draw(at: .zero) }.cgImage
    }
}
#endif
