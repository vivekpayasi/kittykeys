import Foundation

/// An opaque sRGB colour in a theme, such as `#3DF58A`. Saved as that hex string.
public struct ThemeColor: Hashable, Sendable {
    public static let black = ThemeColor(rgb: 0x000000)
    public static let white = ThemeColor(rgb: 0xFFFFFF)

    /// `0xRRGGBB`.
    public var rgb: UInt32

    public init(rgb: UInt32) {
        self.rgb = rgb & 0xFFFFFF
    }

    /// `#RRGGBB` or `RRGGBB`, in either case; nil for anything else.
    public init?(hex: String) {
        let digits = hex.hasPrefix("#") ? hex.dropFirst() : Substring(hex)
        guard digits.count == 6, digits.allSatisfy(\.isHexDigit), let rgb = UInt32(digits, radix: 16) else { return nil }
        self.init(rgb: rgb)
    }

    /// `#RRGGBB` in capitals.
    public var hex: String {
        String(format: "#%06X", rgb)
    }

    /// Each channel from 0 to 1.
    public var red: Double { Self.channel(rgb >> 16) }
    public var green: Double { Self.channel(rgb >> 8) }
    public var blue: Double { Self.channel(rgb) }

    /// WCAG's relative luminance: 0 for black, 1 for white.
    public var luminance: Double {
        0.2126 * Self.linear(red) + 0.7152 * Self.linear(green) + 0.0722 * Self.linear(blue)
    }

    /// WCAG's contrast ratio, from 1 (the same) to 21 (black and white).
    public func contrast(with other: ThemeColor) -> Double {
        let (a, b) = (luminance, other.luminance)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    /// This colour moved `amount` of the way to `other`, channel by channel: 0 gives this colour, 1 gives `other`.
    public func mixed(with other: ThemeColor, _ amount: Double) -> ThemeColor {
        func mix(_ shift: UInt32) -> UInt32 {
            let a = Double((rgb >> shift) & 0xFF), b = Double((other.rgb >> shift) & 0xFF)
            return UInt32(min(max((a + (b - a) * amount).rounded(), 0), 255)) << shift
        }
        return ThemeColor(rgb: mix(16) | mix(8) | mix(0))
    }

    private static func channel(_ shifted: UInt32) -> Double {
        Double(shifted & 0xFF) / 255
    }

    private static func linear(_ value: Double) -> Double {
        value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }
}

extension ThemeColor: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let color = ThemeColor(hex: text) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not a #RRGGBB colour: \(text)")
        }
        self = color
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(hex)
    }
}
