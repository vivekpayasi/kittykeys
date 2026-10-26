// UIKit only, so that `swift test` still builds the package on macOS.
#if canImport(UIKit)
import UIKit

/// One emoji in the panel's list: a `UILabel` in the system font, which draws emoji from the system emoji font.
/// Cells are reused as the list scrolls and nothing is cached per emoji, so memory stays bounded by the visible cells.
/// A pressed cell shows a rounded highlight behind its emoji.
final class EmojiCell: UICollectionViewCell {
    static let reuseIdentifier = "emoji"
    /// Also the size `EmojiFontWarmup` draws at, off the main thread.
    nonisolated static let fontSize: CGFloat = 30
    /// The label is only as big as one emoji, so its backing store stays small.
    private static let labelSize = CGSize(width: 40, height: 38)
    private static let highlightCornerRadius: CGFloat = 8
    /// How far the highlight sits in from the cell's sides.
    private static let highlightInset: CGFloat = 2

    private let label = UILabel()
    private let highlight = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        highlight.isHidden = true
        highlight.layer.cornerRadius = Self.highlightCornerRadius
        contentView.addSubview(highlight)
        label.font = .systemFont(ofSize: Self.fontSize)
        label.textAlignment = .center
        contentView.addSubview(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Shows `emoji`. Setting the same text again draws nothing new.
    func show(_ emoji: String, theme: KeyboardTheme) {
        if label.text != emoji { label.text = emoji }
        highlight.backgroundColor = theme.specialKey
    }

    override var isHighlighted: Bool {
        didSet { highlight.isHidden = !isHighlighted }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let bounds = contentView.bounds
        highlight.frame = bounds.insetBy(dx: Self.highlightInset, dy: Self.highlightInset)
        let size = CGSize(width: min(Self.labelSize.width, bounds.width), height: min(Self.labelSize.height, bounds.height))
        label.frame = CGRect(
            x: ((bounds.width - size.width) / 2).rounded(), y: ((bounds.height - size.height) / 2).rounded(),
            width: size.width, height: size.height)
    }
}

/// A section's title above its emoji: the category name from the emoji data, in small grey capitals.
final class EmojiSectionHeader: UICollectionReusableView {
    static let reuseIdentifier = "header"
    private static let fontSize: CGFloat = 12
    /// The title's distance from the list's left edge.
    private static let titleInset: CGFloat = 10

    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.font = .systemFont(ofSize: Self.fontSize, weight: .semibold)
        addSubview(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func show(_ title: String, theme: KeyboardTheme) {
        label.text = title.localizedUppercase
        label.textColor = theme.hint
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = bounds.inset(by: UIEdgeInsets(top: 0, left: Self.titleInset, bottom: 0, right: Self.titleInset))
    }
}
#endif
