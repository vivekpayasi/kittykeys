/// The settings the user picks in the container app. The keyboard reads them through `SettingsStore`.
public struct KeyboardSettings: Codable, Equatable, Sendable {
    /// The seconds `longPressDelay` may take; a decoded value outside it is clamped into it.
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

    /// A missing field takes its default, so settings saved before a field existed still load.
    /// `longPressDelay` is clamped to `longPressDelayRange`.
    public init(from decoder: any Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        haptics = try container.decodeIfPresent(Bool.self, forKey: .haptics) ?? haptics
        sound = try container.decodeIfPresent(Bool.self, forKey: .sound) ?? sound
        keyPopup = try container.decodeIfPresent(Bool.self, forKey: .keyPopup) ?? keyPopup
        doubleSpacePeriod = try container.decodeIfPresent(Bool.self, forKey: .doubleSpacePeriod) ?? doubleSpacePeriod
        let delay = try container.decodeIfPresent(Double.self, forKey: .longPressDelay) ?? longPressDelay
        let range = Self.longPressDelayRange
        longPressDelay = min(max(delay, range.lowerBound), range.upperBound)
    }
}
