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

    /// The store on the App Group's shared defaults. nil if `id` is nil, if the app has no container for
    /// that group (it lacks the App Group entitlement), or if `UserDefaults(suiteName:)` fails. Without the
    /// entitlement iOS still hands back defaults for the suite, but they are private to the process and
    /// share nothing, hence the container check. On macOS the container check always passes.
    public static func appGroup(id: String?) -> SettingsStore? {
        guard let id,
              FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) != nil,
              let defaults = UserDefaults(suiteName: id)
        else { return nil }
        return SettingsStore(defaults: defaults)
    }

    /// The saved settings, stored as JSON. Missing or corrupt data gives the defaults.
    public func load() -> KeyboardSettings {
        guard let data = defaults.data(forKey: Self.settingsKey),
              let settings = try? JSONDecoder().decode(KeyboardSettings.self, from: data)
        else { return KeyboardSettings() }
        return settings
    }

    /// Saves `settings` as JSON. A non-finite `longPressDelay`, which JSON can't hold, is saved as the default
    /// so the other fields are still written.
    public func save(_ settings: KeyboardSettings) {
        var settings = settings
        settings.longPressDelay = KeyboardSettings.validLongPressDelay(settings.longPressDelay)
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
