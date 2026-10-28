// UIKit only, so that `swift test` still builds the package on macOS.
#if canImport(UIKit)
import KeyboardCore
import UIKit

/// A `ThemeStyle` as UIKit colours and fonts. The host builds one from the look the settings pick (`Themes.active`);
/// `.light` and `.dark` are Automatic's two looks, close to Apple's keyboard, as in the approved mockups.
///
/// A look without a background leaves the keyboard view clear, so the system's keyboard backdrop (Liquid Glass on
/// iOS 26) shows around and between the keys and in the suggestion row (ruling R42). The key colours read well on it.
public struct KeyboardTheme: Equatable, Sendable {
    public static let light = KeyboardTheme(style: Themes.automaticLight)
    public static let dark = KeyboardTheme(style: Themes.automaticDark)

    /// The look's data; the colours below are drawn from it. Two themes are equal when their styles are.
    public let style: ThemeStyle
    /// What the keys sit on; nil for the system's backdrop.
    public let background: UIColor?
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

    public init(style: ThemeStyle) {
        self.style = style
        background = style.background.map(UIColor.init(themeColor:))
        key = UIColor(themeColor: style.key)
        specialKey = UIColor(themeColor: style.specialKey)
        label = UIColor(themeColor: style.label)
        functionLabel = UIColor(themeColor: style.functionLabel)
        hint = UIColor(themeColor: style.hint)
        popup = UIColor(themeColor: style.popup)
        selection = UIColor(themeColor: style.accent)
        selectedLabel = UIColor(themeColor: style.onAccent)
        searchField = UIColor(themeColor: style.searchField)
    }

    public static func == (a: KeyboardTheme, b: KeyboardTheme) -> Bool {
        a.style == b.style
    }

    /// A grey like iOS's keyboard backdrop and the bar above the keyboard, for a host that has neither behind its
    /// keyboard, such as the app's previews: rounded and faded backgrounds show against it as on the phone.
    public static func systemBackdrop(isDark: Bool) -> UIColor {
        UIColor(themeColor: ThemeStyle.systemBackdrop(isDark: isDark))
    }

    /// The system font in the theme's design and weight.
    public func font(ofSize size: CGFloat) -> UIFont {
        Self.font(ofSize: size, weight: style.fontWeight, design: style.fontDesign)
    }

    /// The standard design at the theme's weight, for function keys' symbol labels such as ⇧ and ⌫: the serif and
    /// monospaced designs draw them small or thin.
    public func symbolFont(ofSize size: CGFloat) -> UIFont {
        Self.font(ofSize: size, weight: style.fontWeight, design: .standard)
    }

    /// The theme's design at regular weight, for the small corner hints.
    public func hintFont(ofSize size: CGFloat) -> UIFont {
        Self.font(ofSize: size, weight: .regular, design: style.fontDesign)
    }

    /// Key icons drawn to match the labels' weight.
    public var symbolWeight: UIImage.SymbolWeight {
        switch style.fontWeight {
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
