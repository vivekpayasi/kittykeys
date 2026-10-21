// UIKit only, so that `swift test` still builds the package on macOS.
#if canImport(UIKit)
import UIKit

/// The keyboard's colours. The host picks `.light` or `.dark` from the trait collection or the field's `keyboardAppearance`.
/// Close to Apple's keyboard, as in the approved mockups.
public struct KeyboardTheme: Equatable, Sendable {
    /// Behind the keys, including the suggestion row.
    public let background: UIColor
    /// Letter, number and symbol keys, and space.
    public let key: UIColor
    /// Shift, backspace, the page keys, return and the bottom row's other keys. Pressing a key swaps it with `key`.
    public let specialKey: UIColor
    public let label: UIColor
    /// Corner hints and the space bar's label.
    public let hint: UIColor
    /// The key preview balloon and the long-press popup.
    public let popup: UIColor
    /// The long-press option that a lift would type, and its label.
    public let selection: UIColor
    public let selectedLabel: UIColor

    public static let light = KeyboardTheme(
        background: UIColor(rgb: 0xD1D3D9), key: UIColor(rgb: 0xFFFFFF), specialKey: UIColor(rgb: 0xABB0BA),
        label: UIColor(rgb: 0x111111), hint: UIColor(rgb: 0x7A7F88), popup: UIColor(rgb: 0xFFFFFF),
        selection: UIColor(rgb: 0x0A84FF), selectedLabel: UIColor(rgb: 0xFFFFFF))

    /// The popup is a shade lighter than the keys, so it stands apart from the keys it covers.
    public static let dark = KeyboardTheme(
        background: UIColor(rgb: 0x2C2C2E), key: UIColor(rgb: 0x6B6B6E), specialKey: UIColor(rgb: 0x454548),
        label: UIColor(rgb: 0xFFFFFF), hint: UIColor(rgb: 0xC4C4C8), popup: UIColor(rgb: 0x828286),
        selection: UIColor(rgb: 0x0A84FF), selectedLabel: UIColor(rgb: 0xFFFFFF))
}

extension UIColor {
    /// An opaque sRGB colour from a hex value such as `0xD1D3D9`.
    fileprivate convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }
}
#endif
