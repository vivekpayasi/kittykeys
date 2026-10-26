// UIKit only, so that `swift test` still builds the package on macOS.
#if canImport(UIKit)
import UIKit

/// The keyboard's colours. The host picks `.light` or `.dark` from the trait collection or the field's `keyboardAppearance`.
/// Close to Apple's keyboard, as in the approved mockups.
///
/// The keyboard view has no visible background of its own: the system's keyboard backdrop (Liquid Glass on iOS 26) shows
/// around and between the keys and in the suggestion row (ruling R42). The key colours read well on it.
public struct KeyboardTheme: Equatable, Sendable {
    /// A grey like the system's keyboard backdrop, for a host that has none behind the keys, such as the app's preview.
    /// The keyboard view never draws it.
    public let backdrop: UIColor
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
    /// The emoji search field. Its caret takes `selection`.
    public let searchField: UIColor

    public static let light = KeyboardTheme(
        backdrop: UIColor(rgb: 0xE2E4E8), key: UIColor(rgb: 0xFFFFFF), specialKey: UIColor(rgb: 0xABB0BA),
        label: UIColor(rgb: 0x111111), hint: UIColor(rgb: 0x7A7F88), popup: UIColor(rgb: 0xFFFFFF),
        selection: UIColor(rgb: 0x0A84FF), selectedLabel: UIColor(rgb: 0xFFFFFF), searchField: UIColor(rgb: 0xFFFFFF))

    /// The popup is a shade lighter than the keys, so it stands apart from the keys it covers. The search field is as
    /// dark as the special keys, so its grey placeholder stays readable.
    public static let dark = KeyboardTheme(
        backdrop: UIColor(rgb: 0x171717), key: UIColor(rgb: 0x6B6B6E), specialKey: UIColor(rgb: 0x454548),
        label: UIColor(rgb: 0xFFFFFF), hint: UIColor(rgb: 0xC4C4C8), popup: UIColor(rgb: 0x828286),
        selection: UIColor(rgb: 0x0A84FF), selectedLabel: UIColor(rgb: 0xFFFFFF), searchField: UIColor(rgb: 0x454548))
}

extension UIColor {
    /// A fill that looks clear but still takes touches. iOS doesn't deliver touches that land on fully transparent
    /// parts of a keyboard extension's view, so the keyboard's own background, the emoji panel and its list use this
    /// instead of `.clear` (ruling M3-R8). At 1% opacity it can't be told apart from the system backdrop (ruling R42).
    static let touchableClear = UIColor(white: 0.5, alpha: 0.01)

    /// An opaque sRGB colour from a hex value such as `0xD1D3D9`.
    fileprivate convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }
}
#endif
