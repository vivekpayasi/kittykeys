import Foundation

/// The ready-made themes, and how the keyboard picks the theme to show.
public enum Themes {
    /// Today's look, light or dark with the phone and the field, on iOS's backdrop.
    public static let automaticID = "automatic"
    /// The start of every custom theme's id.
    public static let customIDPrefix = "custom-"

    public static let automaticLight = theme(
        automaticID, "Automatic", background: nil, key: 0xFFFFFF, specialKey: 0xABB0BA, label: 0x111111,
        functionLabel: 0x111111, hint: 0x7A7F88, accent: 0x0A84FF, keyShadow: true)

    /// The popup is a shade lighter than the keys, and the search field as dark as the function keys (ThemeSpec's rules).
    public static let automaticDark = theme(
        automaticID, "Automatic", background: nil, key: 0x6B6B6E, specialKey: 0x454548, label: 0xFFFFFF,
        functionLabel: 0xFFFFFF, hint: 0xC4C4C8, accent: 0x0A84FF, keyShadow: true)

    /// The gallery's order, Automatic first (as its light variant). Ids never change: settings keep them.
    public static let presets: [ThemeSpec] = [
        automaticLight,
        renamed(automaticLight, "light", "Light", background: 0xD1D4DA),
        renamed(automaticDark, "dark", "Dark", background: 0x262628),
        // The user's Android theme: black, with neon green on shift, ⌫, return and the other function keys.
        theme(
            "neon", "Neon", background: 0x000000, key: 0x1C1C1E, specialKey: 0x1C1C1E, label: 0xFFFFFF,
            functionLabel: 0x3DF58A, hint: 0x8E8E93, accent: 0x3DF58A),
        theme(
            "midnight", "Midnight", background: 0x0B1020, key: 0x1B2440, specialKey: 0x141B33, label: 0xEEF2FF,
            functionLabel: 0x8AB4FF, hint: 0x7C88AA, accent: 0x5B8CFF, returnKeyAccent: true),
        theme(
            "amber", "Amber", background: 0x111111, key: 0x2A2A2A, specialKey: 0x2A2A2A, label: 0xF5F5F5,
            functionLabel: 0xFFB020, hint: 0x8A8A8A, accent: 0xFFB020, keyShape: .borderless),
        theme(
            "synthwave", "Synthwave", background: 0x160B26, key: 0x5B3A86, specialKey: 0x7A3C8F, label: 0xF6EDFF,
            functionLabel: 0xFF5BD9, hint: 0xA58BC4, accent: 0xFF5BD9, keyShape: .outlined, fontWeight: .medium),
        theme(
            "terminal", "Terminal", background: 0x050A05, key: 0x143014, specialKey: 0x143014, label: 0x39FF6A,
            functionLabel: 0x39FF6A, hint: 0x1F9E45, accent: 0x39FF6A, keyShape: .borderless, fontDesign: .monospaced),
        theme(
            "paper", "Paper", background: 0xEFE8DC, key: 0xFFFCF5, specialKey: 0xDDD3C2, label: 0x2A241C,
            functionLabel: 0xB4471B, hint: 0x9A8C78, accent: 0xD9581E, keyShadow: true, fontDesign: .serif),
        theme(
            "rose", "Rose", background: 0xF9DCE6, key: 0xFFF7FA, specialKey: 0xF1B9CC, label: 0x3D1828,
            functionLabel: 0xC2255C, hint: 0xA87388, accent: 0xE0407A, keyShadow: true, returnKeyAccent: true,
            fontDesign: .rounded, fontWeight: .medium),
    ]

    /// The theme `id` names: Automatic's variant for the appearance, a ready-made theme, or one of `custom`; nil for
    /// an id that is none of them, such as a deleted custom theme.
    public static func spec(id: String, custom: [ThemeSpec], isDark: Bool) -> ThemeSpec? {
        if id == automaticID { return isDark ? automaticDark : automaticLight }
        return presets.first { $0.id == id } ?? custom.first { $0.id == id }
    }

    /// The theme the keyboard shows. In dark mode `darkThemeID` picks it, unless it is empty ("same as Theme"); an id
    /// that names nothing falls back to `themeID`'s theme, then to Automatic.
    public static func active(themeID: String, darkThemeID: String, custom: [ThemeSpec], isDark: Bool) -> ThemeSpec {
        let dark = isDark && !darkThemeID.isEmpty ? spec(id: darkThemeID, custom: custom, isDark: true) : nil
        return dark ?? spec(id: themeID, custom: custom, isDark: isDark) ?? (isDark ? automaticDark : automaticLight)
    }

    /// A copy of `base` as a new custom theme, with a fresh id and the first free name of "My theme", "My theme 2"…
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

    private static func theme(
        _ id: String, _ name: String, background: UInt32?, key: UInt32, specialKey: UInt32, label: UInt32,
        functionLabel: UInt32, hint: UInt32, accent: UInt32, keyShape: KeyShape = .filled, keyShadow: Bool = false,
        returnKeyAccent: Bool = false, fontDesign: FontDesign = .standard, fontWeight: FontWeight = .regular
    ) -> ThemeSpec {
        ThemeSpec(
            id: id, name: name, background: background.map(ThemeColor.init(rgb:)), key: ThemeColor(rgb: key),
            specialKey: ThemeColor(rgb: specialKey), label: ThemeColor(rgb: label),
            functionLabel: ThemeColor(rgb: functionLabel), hint: ThemeColor(rgb: hint), accent: ThemeColor(rgb: accent),
            keyShape: keyShape, keyShadow: keyShadow, returnKeyAccent: returnKeyAccent, fontDesign: fontDesign,
            fontWeight: fontWeight)
    }

    /// `base` with a solid background, under a new id and name.
    private static func renamed(_ base: ThemeSpec, _ id: String, _ name: String, background: UInt32) -> ThemeSpec {
        var spec = base
        spec.id = id
        spec.name = name
        spec.background = ThemeColor(rgb: background)
        return spec
    }
}
