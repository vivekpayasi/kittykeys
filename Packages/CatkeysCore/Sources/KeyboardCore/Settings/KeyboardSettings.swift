/// The settings the user picks in the container app. The keyboard reads them through `SettingsStore`.
public struct KeyboardSettings: Codable, Equatable, Sendable {
    /// The seconds `longPressDelay` may take. A finite value outside it is clamped into it on save and on decode;
    /// NaN or infinity becomes the default.
    public static let longPressDelayRange: ClosedRange<Double> = 0.2...0.6

    public var haptics = true, sound = false, keyPopup = true, doubleSpacePeriod = true
    /// Seconds a key is held before its long-press options show.
    public var longPressDelay = 0.3

    public init() {}
}

extension KeyboardSettings {
    private enum CodingKeys: String, CodingKey {
        case haptics, sound, keyPopup, doubleSpacePeriod, longPressDelay
    }

    /// A missing or wrong-typed field takes its default, so settings saved before a field existed still load
    /// and one bad field doesn't lose the others. `longPressDelay` goes through `validLongPressDelay(_:)`.
    public init(from decoder: any Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        haptics = (try? container.decodeIfPresent(Bool.self, forKey: .haptics)) ?? haptics
        sound = (try? container.decodeIfPresent(Bool.self, forKey: .sound)) ?? sound
        keyPopup = (try? container.decodeIfPresent(Bool.self, forKey: .keyPopup)) ?? keyPopup
        doubleSpacePeriod = (try? container.decodeIfPresent(Bool.self, forKey: .doubleSpacePeriod)) ?? doubleSpacePeriod
        let delay = (try? container.decodeIfPresent(Double.self, forKey: .longPressDelay)) ?? longPressDelay
        longPressDelay = Self.validLongPressDelay(delay)
    }

    /// `delay` clamped to `longPressDelayRange`; NaN or infinity gives the default.
    static func validLongPressDelay(_ delay: Double) -> Double {
        guard delay.isFinite else { return KeyboardSettings().longPressDelay }
        return min(max(delay, longPressDelayRange.lowerBound), longPressDelayRange.upperBound)
    }
}
