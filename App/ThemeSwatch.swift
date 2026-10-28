import KeyboardCore
import SwiftUI

/// A small drawing of the keyboard in one look of a theme, for the gallery's cards: iOS's bar behind, the background
/// with its rounded or faded top, and four short rows of keys in the look's key style, colours and font. It follows
/// `ThemeStyle`'s rules, as the keyboard does.
struct ThemeSwatch: View {
    let style: ThemeStyle
    /// Whether iOS's bar behind the keyboard is dark, as it is in dark mode.
    let isDark: Bool

    /// A key in the drawing: its width in letter-key widths, its role and what it shows.
    private struct Key: Identifiable {
        let id: Int
        var width: CGFloat = 1
        var role: KeyRole
        var label = ""
        var symbol: String?
    }

    private static let gap: CGFloat = 3
    /// The band of iOS's bar above the background, and the fade below it, as fractions of the drawing's height.
    private static let barHeight: CGFloat = 0.06, fadeHeight: CGFloat = 0.12
    private static let rows: [[Key]] = {
        var id = 0
        func key(_ role: KeyRole, _ label: String = "", symbol: String? = nil, width: CGFloat = 1) -> Key {
            id += 1
            return Key(id: id, width: width, role: role, label: label, symbol: symbol)
        }
        return [
            "qwertyuiop".map { key(.letter, String($0)) },
            "asdfghjkl".map { key(.letter, String($0)) },
            [key(.function, symbol: "shift", width: 1.5)] + "zxcvbnm".map { key(.letter, String($0)) }
                + [key(.function, symbol: "delete.left", width: 1.5)],
            [
                key(.function, "123", width: 1.5), key(.function, symbol: "face.smiling"), key(.space, "space", width: 5),
                key(.returnKey, "return", width: 2.5),
            ],
        ]
    }()

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let top = style.background == nil ? 0 : size.height * Self.barHeight
            let keysTop = top + (style.background == nil ? 0 : size.height * (style.fadesTopEdge ? Self.fadeHeight : 0.03))
            let unit = (size.width - 2 * Self.gap - 9 * Self.gap) / 10
            let height = (size.height - keysTop - 2 * Self.gap - 3 * Self.gap) / 4
            ZStack(alignment: .top) {
                Color(themeColor: style.background == nil ? style.previewBackdrop : ThemeStyle.systemBackdrop(isDark: isDark))
                if let background = style.background {
                    backgroundShape(Color(themeColor: background), size: size, top: top, fadeEnd: keysTop)
                }
                VStack(spacing: Self.gap) {
                    ForEach(Self.rows.indices, id: \.self) { index in
                        HStack(spacing: Self.gap) {
                            ForEach(Self.rows[index]) { key in
                                keyView(key, width: key.width * unit + (key.width - 1) * Self.gap, height: height)
                            }
                        }
                    }
                }
                .padding(Self.gap)
                .padding(.top, keysTop)
            }
            .frame(width: size.width, height: size.height)
        }
        .accessibilityHidden(true)
    }

    /// The background below the bar, its top corners rounded at iOS's bar's radius scaled to the drawing, fading in over
    /// the band above the keys if the look fades.
    private func backgroundShape(_ colour: Color, size: CGSize, top: CGFloat, fadeEnd: CGFloat) -> some View {
        let radius = style.roundsTopCorners ? size.width * Themes.topCornerRadius / 402 : 0
        let shape = UnevenRoundedRectangle(topLeadingRadius: radius, topTrailingRadius: radius, style: .continuous)
        let fill: AnyShapeStyle = style.fadesTopEdge
            ? AnyShapeStyle(LinearGradient(
                stops: [
                    .init(color: colour.opacity(0), location: 0),
                    .init(color: colour, location: (fadeEnd - top) / max(size.height - top, 1)),
                ],
                startPoint: .top, endPoint: .bottom))
            : AnyShapeStyle(colour)
        return shape.fill(fill)
            .frame(width: size.width, height: size.height - top)
            .offset(y: top)
    }

    private func keyView(_ key: Key, width: CGFloat, height: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: min(3, height / 2))
        let labelColor = Color(themeColor: style.labelColor(key.role))
        let fontSize = min(height * 0.55, key.label.count > 1 ? 6 : 9)
        return ZStack {
            shape.fill(style.restingFill(key.role).map { Color(themeColor: $0) } ?? .clear)
            if let outline = style.outline(key.role) {
                shape.strokeBorder(Color(themeColor: outline), lineWidth: 0.75)
            }
            if let symbol = key.symbol {
                // In dark mode iOS 26 draws the smiley filled; the keyboard always uses the light appearance's shape.
                Image(systemName: symbol)
                    .font(.system(size: fontSize * 0.9, weight: fontWeight))
                    .foregroundStyle(labelColor)
                    .environment(\.colorScheme, .light)
            } else {
                Text(key.label)
                    .font(.system(size: fontSize, weight: fontWeight, design: fontDesign))
                    .foregroundStyle(labelColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
        }
        .frame(width: max(width, 0), height: max(height, 0))
        .shadow(color: style.hasShadow(key.role) ? .black.opacity(0.3) : .clear, radius: 0, y: 0.5)
    }

    private var fontDesign: Font.Design {
        switch style.fontDesign {
        case .standard: .default
        case .rounded: .rounded
        case .serif: .serif
        case .monospaced: .monospaced
        }
    }

    private var fontWeight: Font.Weight {
        switch style.fontWeight {
        case .light: .light
        case .regular: .regular
        case .medium: .medium
        case .bold: .bold
        }
    }
}

/// A theme's drawing: its one look, on iOS's bar for the app's light or dark; or, with a dark look, the light look on
/// the left half and the dark look on the right.
struct ThemeSpecSwatch: View {
    let spec: ThemeSpec
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if let dark = spec.dark {
            ThemeSwatch(style: spec.light, isDark: false)
                .overlay {
                    ThemeSwatch(style: dark, isDark: true)
                        .mask(alignment: .trailing) {
                            GeometryReader { geometry in
                                Rectangle().frame(width: geometry.size.width / 2).offset(x: geometry.size.width / 2)
                            }
                        }
                }
        } else {
            ThemeSwatch(style: spec.light, isDark: colorScheme == .dark)
        }
    }
}

extension Color {
    init(themeColor: ThemeColor) {
        self.init(.sRGB, red: themeColor.red, green: themeColor.green, blue: themeColor.blue)
    }
}
