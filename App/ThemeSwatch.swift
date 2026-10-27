import KeyboardCore
import SwiftUI

/// A small drawing of the keyboard in a theme, for the gallery's cards: the background and four short rows of keys in
/// the theme's key style, colours and font. It follows `ThemeSpec`'s rules, as the keyboard does.
struct ThemeSwatch: View {
    let spec: ThemeSpec

    /// A key in the drawing: its width in letter-key widths, its role and what it shows.
    private struct Key: Identifiable {
        let id: Int
        var width: CGFloat = 1
        var role: KeyRole
        var label = ""
        var symbol: String?
    }

    private static let gap: CGFloat = 3
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
            let padding = Self.gap
            let unit = (geometry.size.width - 2 * padding - 9 * Self.gap) / 10
            let height = (geometry.size.height - 2 * padding - 3 * Self.gap) / 4
            VStack(spacing: Self.gap) {
                ForEach(Self.rows.indices, id: \.self) { index in
                    HStack(spacing: Self.gap) {
                        ForEach(Self.rows[index]) { key in
                            keyView(key, width: key.width * unit + (key.width - 1) * Self.gap, height: height)
                        }
                    }
                }
            }
            .padding(padding)
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .background(Color(themeColor: spec.previewBackdrop))
        .accessibilityHidden(true)
    }

    private func keyView(_ key: Key, width: CGFloat, height: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: min(3, height / 2))
        let labelColor = Color(themeColor: spec.labelColor(key.role))
        let fontSize = min(height * 0.55, key.label.count > 1 ? 6 : 9)
        return ZStack {
            shape.fill(spec.restingFill(key.role).map { Color(themeColor: $0) } ?? .clear)
            if let outline = spec.outline(key.role) {
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
        .shadow(color: spec.hasShadow(key.role) ? .black.opacity(0.3) : .clear, radius: 0, y: 0.5)
    }

    private var fontDesign: Font.Design {
        switch spec.fontDesign {
        case .standard: .default
        case .rounded: .rounded
        case .serif: .serif
        case .monospaced: .monospaced
        }
    }

    private var fontWeight: Font.Weight {
        switch spec.fontWeight {
        case .light: .light
        case .regular: .regular
        case .medium: .medium
        case .bold: .bold
        }
    }
}

extension Color {
    init(themeColor: ThemeColor) {
        self.init(.sRGB, red: themeColor.red, green: themeColor.green, blue: themeColor.blue)
    }
}
