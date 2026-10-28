/// How keys are drawn.
public enum KeyShape: String, Codable, CaseIterable, Sendable {
    /// Apple's look: each key filled with its colour.
    case filled
    /// A thin outline in the key's colour, and no fill.
    case outlined
    /// Labels on the background; a key shows its colour only while pressed.
    case borderless
}

/// The system font's designs, so no font files ship.
public enum FontDesign: String, Codable, CaseIterable, Sendable {
    case standard, rounded, serif, monospaced
}

public enum FontWeight: String, Codable, CaseIterable, Sendable {
    case light, regular, medium, bold
}

/// What a key is to a theme, which picks its colours.
public enum KeyRole: Sendable {
    /// Letters, numbers and symbols above the bottom row: the key colour and the letter colour.
    case letter
    /// Characters on the bottom row, such as "," and "@": the function-key colour and the letter colour.
    case punctuation
    /// The key colour, with its label in the hint colour.
    case space
    /// Shift, ⌫, the page keys, 😊 and 🌐: the function-key colour and the function-key label colour.
    case function
    /// Like a function key, unless the theme puts it in the accent.
    case returnKey
}

/// One look of a theme, as plain data: what the keyboard draws in light or dark mode (`ThemeSpec` holds one or two).
/// Every colour rule lives here, so it can be tested without UIKit; `KeyboardUI` only turns the results into colours
/// and fonts.
public struct ThemeStyle: Hashable, Sendable {
    /// Below this contrast a pressed key's fill can't be told from what is under it.
    private static let minimumPressContrast = 1.15
    /// Below this contrast a pressed key's label can't be read on its fill.
    private static let minimumPressedLabelContrast = 2.0
    /// Below this contrast text can't be read on a popup or the search field.
    private static let minimumTextContrast = 3.0
    /// Below this contrast the popups can't be told from the background.
    private static let minimumPopupContrast = 1.1
    /// Keys darker than this get popups a shade lighter, so they stand apart from the keys they cover.
    private static let darkKeyLuminance = 0.18
    /// An accent lighter than this takes black text.
    private static let lightAccentLuminance = 0.4

    /// What the keys sit on; nil for iOS's own keyboard backdrop.
    public var background: ThemeColor?
    /// Letter keys and space.
    public var key: ThemeColor
    /// Function keys and the bottom row's characters.
    public var specialKey: ThemeColor
    /// Letters, numbers and symbols.
    public var label: ThemeColor
    /// Shift, ⌫, return and the other function keys' labels and icons.
    public var functionLabel: ThemeColor
    /// Corner hints and the space bar's label.
    public var hint: ThemeColor
    /// The long-press selection, the search caret, and the return key when `returnKeyAccent` is on.
    public var accent: ThemeColor
    public var keyShape: KeyShape
    /// A shadow under each key; only filled keys draw it.
    public var keyShadow: Bool
    /// The return key rests in the accent.
    public var returnKeyAccent: Bool
    public var fontDesign: FontDesign
    public var fontWeight: FontWeight
    /// A colour background rounds its top corners like iOS's bar above the keyboard (`Themes.topCornerRadius`).
    public var roundsTopCorners: Bool
    /// A colour background fades in over the band above the keys, so iOS's bar melts into it.
    public var fadesTopEdge: Bool

    public init(
        background: ThemeColor?, key: ThemeColor, specialKey: ThemeColor, label: ThemeColor, functionLabel: ThemeColor,
        hint: ThemeColor, accent: ThemeColor, keyShape: KeyShape = .filled, keyShadow: Bool = false,
        returnKeyAccent: Bool = false, fontDesign: FontDesign = .standard, fontWeight: FontWeight = .regular,
        roundsTopCorners: Bool = true, fadesTopEdge: Bool = false
    ) {
        self.background = background
        self.key = key
        self.specialKey = specialKey
        self.label = label
        self.functionLabel = functionLabel
        self.hint = hint
        self.accent = accent
        self.keyShape = keyShape
        self.keyShadow = keyShadow
        self.returnKeyAccent = returnKeyAccent
        self.fontDesign = fontDesign
        self.fontWeight = fontWeight
        self.roundsTopCorners = roundsTopCorners
        self.fadesTopEdge = fadesTopEdge
    }

    // MARK: Derived colours

    /// Black or white text on the accent: white unless the accent is light.
    public var onAccent: ThemeColor {
        accent.luminance > Self.lightAccentLuminance ? .black : .white
    }

    /// The key preview, long-press and skin-tone popups: the key colour, a shade lighter for dark keys, and moved
    /// toward the letter colour if it would vanish into the background. Letters must read on it: with no borders or
    /// outlines the key colour is free to match the letters.
    public var popup: ThemeColor {
        var popup = key.luminance < Self.darkKeyLuminance ? key.mixed(with: .white, 0.15) : key
        if let background, popup.contrast(with: background) < Self.minimumPopupContrast {
            popup = popup.mixed(with: label, 0.15)
        }
        return Self.readable(popup, under: label)
    }

    /// The emoji search field: whichever key colour its grey placeholder, in the hint colour, reads better on, as long
    /// as the typed query, in the letter colour, reads on it too.
    public var searchField: ThemeColor {
        Self.readable(hint.contrast(with: key) >= hint.contrast(with: specialKey) ? key : specialKey, under: label)
    }

    /// The background, or for iOS's backdrop a grey like it, dark for dark keys: what the keys are seen against.
    public var previewBackdrop: ThemeColor {
        background ?? Self.systemBackdrop(isDark: key.luminance < 0.3)
    }

    /// A grey like iOS's keyboard backdrop and the bar above the keyboard, for a host that has neither behind its
    /// keyboard, such as the app's previews.
    public static func systemBackdrop(isDark: Bool) -> ThemeColor {
        isDark ? ThemeColor(rgb: 0x171717) : ThemeColor(rgb: 0xE2E4E8)
    }

    // MARK: Keys

    /// The fill a key rests in; nil for none.
    public func restingFill(_ role: KeyRole) -> ThemeColor? {
        if accentsReturn(role) { return accent }
        return keyShape == .filled ? ownColour(role) : nil
    }

    /// The outline a key rests in; nil for none.
    public func outline(_ role: KeyRole) -> ThemeColor? {
        keyShape == .outlined && !accentsReturn(role) ? ownColour(role) : nil
    }

    /// The fill a pressed key shows, as shift does while on. Filled keys swap to the other key colour; outlined and
    /// borderless keys fill with their own. A fill too close to how the key rests is moved toward the label instead,
    /// and one the label can't be read on moves halfway to the background; space keeps its faint label, as Apple's
    /// does. A return key in the accent moves away from its text colour, or toward it where that barely shows, as for
    /// a near-white accent. Whatever the colours, the press shows: as a last resort the resting colour darkens or
    /// lightens. iOS's backdrop counts as `previewBackdrop`.
    public func pressedFill(_ role: KeyRole) -> ThemeColor {
        let resting = restingFill(role) ?? background ?? previewBackdrop
        var fill: ThemeColor
        if accentsReturn(role) {
            fill = accent.mixed(with: onAccent == .white ? .black : .white, 0.25)
            if fill.contrast(with: accent) < Self.minimumPressContrast { fill = accent.mixed(with: onAccent, 0.25) }
        } else {
            let own = ownColour(role)
            fill = keyShape == .filled ? otherColour(role) : own
            if fill.contrast(with: resting) < Self.minimumPressContrast { fill = own.mixed(with: labelColor(role), 0.2) }
            if role != .space, labelColor(role).contrast(with: fill) < Self.minimumPressedLabelContrast {
                fill = fill.mixed(with: background ?? previewBackdrop, 0.5)
            }
        }
        if fill.contrast(with: resting) < Self.minimumPressContrast {
            fill = resting.mixed(with: resting.luminance > Self.darkKeyLuminance ? .black : .white, 0.3)
        }
        return fill
    }

    public func labelColor(_ role: KeyRole) -> ThemeColor {
        switch role {
        case .letter, .punctuation: label
        case .space: hint
        case .function: functionLabel
        case .returnKey: returnKeyAccent ? onAccent : functionLabel
        }
    }

    public func hasShadow(_ role: KeyRole) -> Bool {
        keyShadow && keyShape == .filled
    }

    /// `fill`, or if `text` can't be read on it, `fill` moved in quarter steps toward black or white, whichever `text`
    /// stands out from more, until it reads.
    private static func readable(_ fill: ThemeColor, under text: ThemeColor) -> ThemeColor {
        guard text.contrast(with: fill) < minimumTextContrast else { return fill }
        let away: ThemeColor = text.contrast(with: .black) >= text.contrast(with: .white) ? .black : .white
        for amount in [0.25, 0.5, 0.75] {
            let moved = fill.mixed(with: away, amount)
            if text.contrast(with: moved) >= minimumTextContrast { return moved }
        }
        return away
    }

    private func usesSpecialColour(_ role: KeyRole) -> Bool {
        role != .letter && role != .space
    }

    private func ownColour(_ role: KeyRole) -> ThemeColor {
        usesSpecialColour(role) ? specialKey : key
    }

    private func otherColour(_ role: KeyRole) -> ThemeColor {
        usesSpecialColour(role) ? key : specialKey
    }

    private func accentsReturn(_ role: KeyRole) -> Bool {
        role == .returnKey && returnKeyAccent
    }
}

extension ThemeStyle: Codable {
    private enum CodingKeys: String, CodingKey {
        case background, key, specialKey, label, functionLabel, hint, accent, keyShape, keyShadow, returnKeyAccent,
            fontDesign, fontWeight, roundsTopCorners, fadesTopEdge
    }

    /// A missing or bad field takes Automatic's light value, so looks saved before a field existed still load and one
    /// bad field doesn't lose the rest. A background that is missing or not a colour means iOS's backdrop.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let base = Themes.automaticLight
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? container.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        self.init(
            background: (try? container.decodeIfPresent(ThemeColor.self, forKey: .background)) ?? nil,
            key: value(.key, base.key), specialKey: value(.specialKey, base.specialKey), label: value(.label, base.label),
            functionLabel: value(.functionLabel, base.functionLabel), hint: value(.hint, base.hint),
            accent: value(.accent, base.accent), keyShape: value(.keyShape, base.keyShape),
            keyShadow: value(.keyShadow, base.keyShadow), returnKeyAccent: value(.returnKeyAccent, base.returnKeyAccent),
            fontDesign: value(.fontDesign, base.fontDesign), fontWeight: value(.fontWeight, base.fontWeight),
            roundsTopCorners: value(.roundsTopCorners, base.roundsTopCorners),
            fadesTopEdge: value(.fadesTopEdge, base.fadesTopEdge))
    }
}
