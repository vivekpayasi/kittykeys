// UIKit only, so that `swift test` still builds the package on macOS.
#if canImport(UIKit)
import UIKit

/// The magnified copy of a pressed key: a balloon whose head sits above the key and whose stem covers it.
/// The head stays inside the keyboard, so a number key's balloon covers the suggestion row.
final class KeyPreviewLayer: CAShapeLayer {
    private static let headHeight: CGFloat = 50
    /// How far the head reaches past each side of the key.
    private static let headOverhang: CGFloat = 10
    /// The height of the curve from the head's width down to the key's.
    private static let neckHeight: CGFloat = 8
    private static let headCornerRadius: CGFloat = 8
    private static let fontSize: CGFloat = 32

    private let labelLayer = CATextLayer()

    override init() {
        super.init()
        isHidden = true
        shadowColor = UIColor.black.cgColor
        shadowOpacity = 0.25
        shadowOffset = CGSize(width: 0, height: 3)
        shadowRadius = 6
        let font = UIFont.systemFont(ofSize: Self.fontSize)
        labelLayer.font = font
        labelLayer.fontSize = font.pointSize
        labelLayer.alignmentMode = .center
        addSublayer(labelLayer)
    }

    /// Core Animation's copy for the presentation tree.
    override init(layer: Any) {
        super.init(layer: layer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Shows `label` in a balloon over `key`, with the head kept inside `bounds`. A key with no area shows nothing.
    func show(_ label: String, over key: CGRect, within bounds: CGRect, theme: KeyboardTheme, scale: CGFloat) {
        guard hasArea(key.size) else {
            hide()
            return
        }
        let headWidth = key.width + 2 * Self.headOverhang
        let head = CGRect(
            x: min(max(key.midX - headWidth / 2, bounds.minX), bounds.maxX - headWidth),
            y: max(key.minY - Self.headHeight, bounds.minY), width: headWidth, height: Self.headHeight)
        let balloon = Self.balloonPath(head: head, key: key)
        path = balloon
        shadowPath = balloon
        fillColor = theme.popup.cgColor

        let lineHeight = ceil(UIFont.systemFont(ofSize: Self.fontSize).lineHeight)
        labelLayer.contentsScale = scale
        labelLayer.foregroundColor = theme.label.cgColor
        labelLayer.string = label
        labelLayer.frame = CGRect(
            x: head.minX, y: (head.midY - lineHeight / 2).rounded(), width: head.width, height: lineHeight)
        isHidden = false
    }

    func hide() {
        isHidden = true
    }

    /// The head's outline, joined by S-curves to the key's sides, then down around the key's rounded bottom corners.
    /// Each corner's radius fits its rectangle, however narrow.
    private static func balloonPath(head: CGRect, key: CGRect) -> CGPath {
        let neckBottom = head.maxY + neckHeight
        let neckMiddle = head.maxY + neckHeight / 2
        let headRadius = fittedCornerRadius(headCornerRadius, for: head.size)
        let keyRadius = fittedCornerRadius(KeyLayer.cornerRadius, for: key.size)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: head.minX, y: head.minY + headRadius))
        path.addArc(
            tangent1End: CGPoint(x: head.minX, y: head.minY), tangent2End: CGPoint(x: head.maxX, y: head.minY),
            radius: headRadius)
        path.addArc(
            tangent1End: CGPoint(x: head.maxX, y: head.minY), tangent2End: CGPoint(x: head.maxX, y: head.maxY),
            radius: headRadius)
        path.addLine(to: CGPoint(x: head.maxX, y: head.maxY))
        path.addCurve(
            to: CGPoint(x: key.maxX, y: neckBottom), control1: CGPoint(x: head.maxX, y: neckMiddle),
            control2: CGPoint(x: key.maxX, y: neckMiddle))
        path.addArc(
            tangent1End: CGPoint(x: key.maxX, y: key.maxY), tangent2End: CGPoint(x: key.minX, y: key.maxY),
            radius: keyRadius)
        path.addArc(
            tangent1End: CGPoint(x: key.minX, y: key.maxY), tangent2End: CGPoint(x: key.minX, y: neckBottom),
            radius: keyRadius)
        path.addLine(to: CGPoint(x: key.minX, y: neckBottom))
        path.addCurve(
            to: CGPoint(x: head.minX, y: head.maxY), control1: CGPoint(x: key.minX, y: neckMiddle),
            control2: CGPoint(x: head.minX, y: neckMiddle))
        path.closeSubpath()
        return path
    }
}

/// A key's long-press options: one cell per option from a given x, above the key, with one cell highlighted.
/// The cells line up exactly with the touch processor's, so the highlighted cell is the one under the finger.
final class AlternatesLayer: CALayer {
    private static let cellHeight: CGFloat = 40
    /// Room around the cells inside the popup.
    private static let padding: CGFloat = 4
    /// Space between the popup and the top of the key.
    private static let gapAboveKey: CGFloat = 6
    private static let popupCornerRadius: CGFloat = 10
    private static let selectionCornerRadius: CGFloat = 7
    /// How far the highlight sits in from its cell's sides, so neighbouring cells read as separate.
    private static let selectionInset: CGFloat = 1
    private static let fontSize: CGFloat = 22

    private let selectionLayer = CALayer()
    private var cells: [CATextLayer] = []
    private var cellWidth: CGFloat = 0
    private var selected: Int?
    private var theme = KeyboardTheme.light

    override init() {
        super.init()
        isHidden = true
        shadowColor = UIColor.black.cgColor
        shadowOpacity = 0.25
        shadowOffset = CGSize(width: 0, height: 3)
        shadowRadius = 6
        addSublayer(selectionLayer)
    }

    /// Core Animation's copy for the presentation tree.
    override init(layer: Any) {
        super.init(layer: layer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Shows `options` in display order, in `cellWidth` cells from `originX`, above `key`, with nothing selected yet.
    /// The popup's background stays inside `bounds`; the cells never move. A popup with no room inside `bounds`
    /// shows nothing.
    func show(
        _ options: [String], originX: CGFloat, cellWidth: CGFloat, above key: CGRect, within bounds: CGRect,
        theme: KeyboardTheme, scale: CGFloat
    ) {
        self.theme = theme
        self.cellWidth = cellWidth
        cells.forEach { $0.removeFromSuperlayer() }
        cells = []
        selectionLayer.isHidden = true
        selected = nil
        let minX = max(originX - Self.padding, bounds.minX)
        let maxX = min(originX + CGFloat(options.count) * cellWidth + Self.padding, bounds.maxX)
        let size = CGSize(width: maxX - minX, height: Self.cellHeight + 2 * Self.padding)
        guard hasArea(size) else {
            hide()
            return
        }
        frame = CGRect(origin: CGPoint(x: minX, y: max(key.minY - Self.gapAboveKey - size.height, bounds.minY)), size: size)
        backgroundColor = theme.popup.cgColor
        let radius = fittedCornerRadius(Self.popupCornerRadius, for: size)
        cornerRadius = radius
        shadowPath = CGPath(roundedRect: self.bounds, cornerWidth: radius, cornerHeight: radius, transform: nil)
        selectionLayer.backgroundColor = theme.selection.cgColor

        let font = UIFont.systemFont(ofSize: Self.fontSize)
        let lineHeight = ceil(font.lineHeight)
        cells = options.enumerated().map { index, option in
            let cell = CATextLayer()
            cell.contentsScale = scale
            cell.font = font
            cell.fontSize = Self.fittedFontSize(for: option, in: cellWidth)
            cell.alignmentMode = .center
            cell.foregroundColor = theme.label.cgColor
            cell.string = option
            cell.frame = CGRect(
                x: originX + CGFloat(index) * cellWidth - minX,
                y: (Self.padding + (Self.cellHeight - lineHeight) / 2).rounded(), width: cellWidth, height: lineHeight)
            addSublayer(cell)
            return cell
        }
        isHidden = false
    }

    /// The font size that fits `option` in a cell `cellWidth` wide, inside the highlight: `fontSize`, or smaller for an
    /// option too wide for it, so no data can make options overlap.
    private static func fittedFontSize(for option: String, in cellWidth: CGFloat) -> CGFloat {
        let room = cellWidth - 2 * (selectionInset + 2)
        let width = (option as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: fontSize)]).width
        guard width > room, room > 0 else { return fontSize }
        return max(fontSize * room / width, 1)
    }

    /// Highlights the cell at `index`, an index into the options shown. A cell too narrow for the highlight
    /// gets only the highlighted label colour.
    func select(_ index: Int) {
        guard index != selected, cells.indices.contains(index) else { return }
        if let selected, cells.indices.contains(selected) { cells[selected].foregroundColor = theme.label.cgColor }
        selected = index
        let cell = cells[index]
        cell.foregroundColor = theme.selectedLabel.cgColor
        let size = CGSize(width: cellWidth - 2 * Self.selectionInset, height: Self.cellHeight)
        guard hasArea(size) else {
            selectionLayer.isHidden = true
            return
        }
        selectionLayer.frame = CGRect(origin: CGPoint(x: cell.frame.minX + Self.selectionInset, y: Self.padding), size: size)
        selectionLayer.cornerRadius = fittedCornerRadius(Self.selectionCornerRadius, for: size)
        selectionLayer.isHidden = false
    }

    func hide() {
        isHidden = true
    }
}
#endif
