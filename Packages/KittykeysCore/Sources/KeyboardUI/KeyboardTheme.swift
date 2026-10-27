// UIKit only, so that `swift test` still builds the package on macOS.
#if canImport(UIKit)
import KeyboardCore
import UIKit

/// A `ThemeSpec` as UIKit colours and fonts. The host builds one from the theme the settings pick (`Themes.active`);
/// `.light` and `.dark` are Automatic's two looks, close to Apple's keyboard, as in the approved mockups.
///
/// A theme without a background leaves the keyboard view clear, so the system's keyboard backdrop (Liquid Glass on
/// iOS 26) shows around and between the keys and in the suggestion row (ruling R42). The key colours read well on it.
public struct KeyboardTheme: Equatable, Sendable {
    public static let light = KeyboardTheme(spec: Themes.automaticLight)
    public static let dark = KeyboardTheme(spec: Themes.automaticDark)

    /// The theme's data; the colours below are drawn from it. Two themes are equal when their specs are.
    public let spec: ThemeSpec
    /// What the keys sit on; nil for the system's backdrop.
    public let background: UIColor?
    /// The background, or a grey like the system's backdrop, for a host that has nothing behind the keys, such as the
    /// app's preview. The keyboard view never draws it.
    public let backdrop: UIColor
    /// Letter, number and symbol keys, and space.
    public let key: UIColor
    /// Shift, backspace, the page keys, return and the bottom row's other keys.
    public let specialKey: UIColor
    public let label: UIColor
    /// The function keys' labels and icons, here the emoji panel's ABC and ⌫.
    public let functionLabel: UIColor
    /// Corner hints and the space bar's label.
    public let hint: UIColor
    /// The key preview balloon and the long-press and skin-tone popups.
    public let popup: UIColor
    /// The long-press option that a lift would type, and the search caret.
    public let selection: UIColor
    public let selectedLabel: UIColor
    /// The emoji search field.
    public let searchField: UIColor

    public init(spec: ThemeSpec) {
        self.spec = spec
        background = spec.background.map(UIColor.init(themeColor:))
        backdrop = UIColor(themeColor: spec.previewBackdrop)
        key = UIColor(themeColor: spec.key)
        specialKey = UIColor(themeColor: spec.specialKey)
        label = UIColor(themeColor: spec.label)
        functionLabel = UIColor(themeColor: spec.functionLabel)
        hint = UIColor(themeColor: spec.hint)
        popup = UIColor(themeColor: spec.popup)
        selection = UIColor(themeColor: spec.accent)
        selectedLabel = UIColor(themeColor: spec.onAccent)
        searchField = UIColor(themeColor: spec.searchField)
    }

    public static func == (a: KeyboardTheme, b: KeyboardTheme) -> Bool {
        a.spec == b.spec
    }

    /// The system font in the theme's design and weight.
    public func font(ofSize size: CGFloat) -> UIFont {
        Self.font(ofSize: size, weight: spec.fontWeight, design: spec.fontDesign)
    }

    /// The standard design at the theme's weight, for function keys' symbol labels such as ⇧ and ⌫: the serif and
    /// monospaced designs draw them small or thin.
    public func symbolFont(ofSize size: CGFloat) -> UIFont {
        Self.font(ofSize: size, weight: spec.fontWeight, design: .standard)
    }

    /// The theme's design at regular weight, for the small corner hints.
    public func hintFont(ofSize size: CGFloat) -> UIFont {
        Self.font(ofSize: size, weight: .regular, design: spec.fontDesign)
    }

    /// Key icons drawn to match the labels' weight.
    public var symbolWeight: UIImage.SymbolWeight {
        switch spec.fontWeight {
        case .light: .light
        case .regular: .regular
        case .medium: .medium
        case .bold: .bold
        }
    }

    private static func font(ofSize size: CGFloat, weight: FontWeight, design: FontDesign) -> UIFont {
        let uiWeight: UIFont.Weight = switch weight {
        case .light: .light
        case .regular: .regular
        case .medium: .medium
        case .bold: .bold
        }
        let font = UIFont.systemFont(ofSize: size, weight: uiWeight)
        let systemDesign: UIFontDescriptor.SystemDesign
        switch design {
        case .standard: return font
        case .rounded: systemDesign = .rounded
        case .serif: systemDesign = .serif
        case .monospaced: systemDesign = .monospaced
        }
        guard let descriptor = font.fontDescriptor.withDesign(systemDesign) else { return font }
        return UIFont(descriptor: descriptor, size: size)
    }
}

extension UIColor {
    /// A fill that looks clear but still takes touches. iOS doesn't deliver touches that land on fully transparent
    /// parts of a keyboard extension's view, so the keyboard's own background, the emoji panel and its list use this
    /// instead of `.clear` (ruling M3-R8). At 1% opacity it can't be told apart from the system backdrop (ruling R42).
    static let touchableClear = UIColor(white: 0.5, alpha: 0.01)

    /// An opaque sRGB colour from a theme.
    public convenience init(themeColor: ThemeColor) {
        self.init(red: themeColor.red, green: themeColor.green, blue: themeColor.blue, alpha: 1)
    }
}
#endif
