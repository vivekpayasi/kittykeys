// UIKit only, so that `swift test` still builds the package on macOS.
#if canImport(UIKit)
import KeyboardCore
import UIKit

/// The skin-tone picker shown above a held emoji: the base and its skins in one row, placed by a `SkinTonePopupLayout`,
/// with the option a lift would type highlighted. It takes no touches; the panel's hold gesture drives it.
final class SkinTonePopup: UIView {
    /// The emoji's size in the popup, and the cells' height.
    private static let fontSize: CGFloat = 28, cellHeight: CGFloat = 44
    /// Room around the cells inside the popup. The layout keeps the cells this far inside the keyboard.
    static let padding: CGFloat = 4
    /// Space between the popup and the top of the held emoji's cell.
    private static let gapAboveCell: CGFloat = 4
    private static let cornerRadius: CGFloat = 10, selectionCornerRadius: CGFloat = 7
    /// How far the highlight sits in from its cell's sides, so neighbouring cells read as separate.
    private static let selectionInset: CGFloat = 1

    private let selection = UIView()
    /// One label per cell, left to right, made once and reused.
    private var labels: [UILabel] = []
    private var layout: SkinTonePopupLayout?
    private var selected: Int?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isHidden = true
        isUserInteractionEnabled = false
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.25
        layer.shadowOffset = CGSize(width: 0, height: 3)
        layer.shadowRadius = 6
        selection.layer.cornerRadius = Self.selectionCornerRadius
        addSubview(selection)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Shows `options` (the base, then its skins) as `layout` places them, above `cell` and no higher than `minY`,
    /// both in the superview's coordinates. Nothing is highlighted until `select(_:)`.
    func show(_ options: [String], layout: SkinTonePopupLayout, above cell: CGRect, minY: CGFloat, theme: KeyboardTheme) {
        let cellWidth = CGFloat(layout.cellWidth)
        let count = min(options.count, layout.count)
        let size = CGSize(width: CGFloat(count) * cellWidth + 2 * Self.padding, height: Self.cellHeight + 2 * Self.padding)
        guard count > 0, hasArea(size) else {
            hide()
            return
        }
        self.layout = layout
        selected = nil
        frame = CGRect(
            origin: CGPoint(x: CGFloat(layout.originX) - Self.padding, y: max(cell.minY - Self.gapAboveCell - size.height, minY)),
            size: size)
        backgroundColor = theme.popup
        let radius = fittedCornerRadius(Self.cornerRadius, for: size)
        layer.cornerRadius = radius
        layer.shadowPath = CGPath(roundedRect: bounds, cornerWidth: radius, cornerHeight: radius, transform: nil)
        selection.backgroundColor = theme.selection
        selection.isHidden = true

        while labels.count < count {
            let label = UILabel()
            label.font = .systemFont(ofSize: Self.fontSize)
            label.textAlignment = .center
            addSubview(label)
            labels.append(label)
        }
        for (position, label) in labels.enumerated() {
            label.isHidden = position >= count
            guard position < count else { continue }
            label.text = options[layout.option(atPosition: position)]
            label.frame = cellFrame(at: position, width: cellWidth)
        }
        isHidden = false
    }

    /// Highlights `option`, an index into the options shown (0 is the base).
    func select(_ option: Int) {
        guard let layout, option != selected, (0..<layout.count).contains(option) else { return }
        selected = option
        let position = layout.option(atPosition: option)  // the mapping is its own inverse
        let cell = cellFrame(at: position, width: CGFloat(layout.cellWidth))
        let highlight = cell.insetBy(dx: Self.selectionInset, dy: 0)
        guard hasArea(highlight.size) else {
            selection.isHidden = true
            return
        }
        selection.frame = highlight
        selection.isHidden = false
    }

    func hide() {
        isHidden = true
        layout = nil
        selected = nil
    }

    private func cellFrame(at position: Int, width: CGFloat) -> CGRect {
        CGRect(x: Self.padding + CGFloat(position) * width, y: Self.padding, width: width, height: Self.cellHeight)
    }
}
#endif
