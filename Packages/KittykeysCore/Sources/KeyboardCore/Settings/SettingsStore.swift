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

    /// The store on the App Group's shared defaults. `id` is the canonical group from Info.plist; a
    /// sideloading tool may have renamed it, so this uses the group `AppGroupResolver` finds. nil if `id`
    /// is nil, if no group has a container for this app (it lacks the App Group entitlement), or if
    /// `UserDefaults(suiteName:)` fails. Without the entitlement iOS still hands back defaults for the
    /// suite, but they are private to the process and share nothing, hence the container check. On macOS
    /// the container check always passes.
    public static func appGroup(id: String?) -> SettingsStore? {
        guard let group = AppGroupResolver.resolve(canonical: id),
              let defaults = UserDefaults(suiteName: group)
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

    /// Saves `settings` as JSON. A finite `longPressDelay` outside `longPressDelayRange` is clamped into it,
    /// and a non-finite one, which JSON can't hold, is saved as the default so the other fields are still written.
    public func save(_ settings: KeyboardSettings) {
        var settings = settings
        settings.longPressDelay = KeyboardSettings.validLongPressDelay(settings.longPressDelay)
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: Self.settingsKey)
    }

    /// When the keyboard last appeared. Without Full Access the keyboard can't write to the App Group, so the app takes
    /// it as proof that Full Access is on. Setting nil removes it.
    public var lastKeyboardOpen: Date? {
        get { defaults.object(forKey: Self.keyboardOpenedAtKey) as? Date }
        nonmutating set { defaults.set(newValue, forKey: Self.keyboardOpenedAtKey) }
    }
}
