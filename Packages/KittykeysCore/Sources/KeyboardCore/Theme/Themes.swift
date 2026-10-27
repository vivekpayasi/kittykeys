import Foundation

/// The ready-made themes, and how the keyboard picks the theme to show.
public enum Themes {
    /// Today's look, light or dark with the phone and the field, on iOS's backdrop.
    public static let automaticID = "automatic"
    /// The start of every custom theme's id.
    public static let customIDPrefix = "custom-"
    /// The corner radius of iOS's bar above the keyboard, drawn with Apple's continuous curve: a colour background
    /// that rounds its top corners uses it. A keyboard extension can't read the bar's shape (a container-concentric
    /// corner reports 0 there), so it was fitted to a screenshot of iOS 26 on an iPhone 16, to about a pixel at 3x.
    public static let topCornerRadius = 26.4

    public static let automaticLight = style(
        background: nil, key: 0xFFFFFF, specialKey: 0xABB0BA, label: 0x111111, functionLabel: 0x111111, hint: 0x7A7F88,
        accent: 0x0A84FF, keyShadow: true)

    /// The popup is a shade lighter than the keys, and the search field as dark as the function keys (ThemeStyle's
    /// rules).
    public static let automaticDark = style(
        background: nil, key: 0x6B6B6E, specialKey: 0x454548, label: 0xFFFFFF, functionLabel: 0xFFFFFF, hint: 0xC4C4C8,
        accent: 0x0A84FF, keyShadow: true)

    /// Today's look, light or dark with the phone and the field.
    public static let automatic = ThemeSpec(id: automaticID, name: "Automatic", light: automaticLight, dark: automaticDark)

    /// The gallery's order, Automatic first. Ids never change: settings keep them. Only Automatic has a dark look.
    public static let presets: [ThemeSpec] = [
        automatic,
        theme("light", "Light", withBackground(automaticLight, 0xD1D4DA)),
        theme("dark", "Dark", withBackground(automaticDark, 0x262628)),
        // The user's Android theme: black, with neon green on shift, ⌫, return and the other function keys.
        theme(
            "neon", "Neon", style(background: 0x000000, key: 0x1C1C1E, specialKey: 0x1C1C1E, label: 0xFFFFFF,
            functionLabel: 0x3DF58A, hint: 0x8E8E93, accent: 0x3DF58A)),
        theme(
            "midnight", "Midnight", style(background: 0x0B1020, key: 0x1B2440, specialKey: 0x141B33, label: 0xEEF2FF,
            functionLabel: 0x8AB4FF, hint: 0x7C88AA, accent: 0x5B8CFF, returnKeyAccent: true)),
        theme(
            "amber", "Amber", style(background: 0x111111, key: 0x2A2A2A, specialKey: 0x2A2A2A, label: 0xF5F5F5,
            functionLabel: 0xFFB020, hint: 0x8A8A8A, accent: 0xFFB020, keyShape: .borderless)),
        theme(
            "synthwave", "Synthwave", style(background: 0x160B26, key: 0x5B3A86, specialKey: 0x7A3C8F, label: 0xF6EDFF,
            functionLabel: 0xFF5BD9, hint: 0xA58BC4, accent: 0xFF5BD9, keyShape: .outlined, fontWeight: .medium)),
        theme(
            "terminal", "Terminal", style(background: 0x050A05, key: 0x143014, specialKey: 0x143014, label: 0x39FF6A,
            functionLabel: 0x39FF6A, hint: 0x1F9E45, accent: 0x39FF6A, keyShape: .borderless, fontDesign: .monospaced)),
        theme(
            "paper", "Paper", style(background: 0xEFE8DC, key: 0xFFFCF5, specialKey: 0xDDD3C2, label: 0x2A241C,
            functionLabel: 0xB4471B, hint: 0x9A8C78, accent: 0xD9581E, keyShadow: true, fontDesign: .serif)),
        theme(
            "rose", "Rose", style(background: 0xF9DCE6, key: 0xFFF7FA, specialKey: 0xF1B9CC, label: 0x3D1828,
            functionLabel: 0xC2255C, hint: 0xA87388, accent: 0xE0407A, keyShadow: true, returnKeyAccent: true,
            fontDesign: .rounded, fontWeight: .medium)),
    ]

    /// The theme `id` names: a ready-made theme or one of `custom`; nil for an id that is neither, such as a deleted
    /// custom theme.
    public static func spec(id: String, custom: [ThemeSpec]) -> ThemeSpec? {
        presets.first { $0.id == id } ?? custom.first { $0.id == id }
    }

    /// The look the keyboard shows: the picked theme's for the appearance, or Automatic's for an id that names nothing.
    public static func active(themeID: String, custom: [ThemeSpec], isDark: Bool) -> ThemeStyle {
        (spec(id: themeID, custom: custom) ?? automatic).style(isDark: isDark)
    }

    /// A copy of `base`, both looks, as a new custom theme, with a fresh id and the first free name of "My theme",
    /// "My theme 2"…
    public static func newCustom(from base: ThemeSpec, existing: [ThemeSpec]) -> ThemeSpec {
        let names = Set(existing.map(\.name))
        var number = 1
        while names.contains(customName(number)) { number += 1 }
        var spec = base
        spec.id = customIDPrefix + UUID().uuidString
        spec.name = customName(number)
        return spec
    }

    private static func customName(_ number: Int) -> String {
        number == 1 ? "My theme" : "My theme \(number)"
    }

    /// A ready-made theme with one look.
    private static func theme(_ id: String, _ name: String, _ style: ThemeStyle) -> ThemeSpec {
        ThemeSpec(id: id, name: name, light: style, dark: nil)
    }

    private static func style(
        background: UInt32?, key: UInt32, specialKey: UInt32, label: UInt32, functionLabel: UInt32, hint: UInt32,
        accent: UInt32, keyShape: KeyShape = .filled, keyShadow: Bool = false, returnKeyAccent: Bool = false,
        fontDesign: FontDesign = .standard, fontWeight: FontWeight = .regular
    ) -> ThemeStyle {
        ThemeStyle(
            background: background.map(ThemeColor.init(rgb:)), key: ThemeColor(rgb: key),
            specialKey: ThemeColor(rgb: specialKey), label: ThemeColor(rgb: label),
            functionLabel: ThemeColor(rgb: functionLabel), hint: ThemeColor(rgb: hint), accent: ThemeColor(rgb: accent),
            keyShape: keyShape, keyShadow: keyShadow, returnKeyAccent: returnKeyAccent, fontDesign: fontDesign,
            fontWeight: fontWeight)
    }

    /// `base` with a solid background.
    private static func withBackground(_ base: ThemeStyle, _ background: UInt32) -> ThemeStyle {
        var style = base
        style.background = ThemeColor(rgb: background)
        return style
    }
}
