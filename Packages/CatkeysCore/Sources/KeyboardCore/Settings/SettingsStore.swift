import Foundation

/// Reads and writes `KeyboardSettings` in a `UserDefaults`. In the app and the keyboard it sits on the
/// App Group's shared defaults: the app writes settings and the keyboard reads them.
/// Never traps: a crash kills the keyboard silently.
public struct SettingsStore {
    private static let settingsKey = "catkeys.settings"
    private static let keyboardOpenedAtKey = "catkeys.keyboardOpenedAt"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// The store on the App Group's shared defaults; nil if `id` is nil or iOS refuses the suite.
    public static func appGroup(id: String?) -> SettingsStore? {
        guard let id, let defaults = UserDefaults(suiteName: id) else { return nil }
        return SettingsStore(defaults: defaults)
    }

    /// The saved settings, stored as JSON. Missing or corrupt data gives the defaults.
    public func load() -> KeyboardSettings {
        guard let data = defaults.data(forKey: Self.settingsKey),
              let settings = try? JSONDecoder().decode(KeyboardSettings.self, from: data)
        else { return KeyboardSettings() }
        return settings
    }

    public func save(_ settings: KeyboardSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: Self.settingsKey)
    }

    /// When the keyboard last appeared. The keyboard writes it and the app shows it, so the user can see
    /// whether the App Group carries data between them. Setting nil removes it.
    public var lastKeyboardOpen: Date? {
        get { defaults.object(forKey: Self.keyboardOpenedAtKey) as? Date }
        nonmutating set { defaults.set(newValue, forKey: Self.keyboardOpenedAtKey) }
    }
}
