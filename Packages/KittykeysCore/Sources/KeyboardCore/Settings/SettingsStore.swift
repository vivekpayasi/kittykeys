import Foundation

/// Reads and writes `KeyboardSettings` in a `UserDefaults`. In the app and the keyboard it sits on the
/// App Group's shared defaults: the app writes settings and the keyboard reads them.
/// Never traps: a crash kills the keyboard silently.
public struct SettingsStore {
    private static let settingsKey = "catkeys.settings"
    private static let keyboardOpenedAtKey = "catkeys.keyboardOpenedAt"
    // Keys from before the rename keep "catkeys." so saved data carries over; new keys use "kittykeys.".
    private static let triedFeaturesKey = "kittykeys.triedFeatures"
    private static let customThemesKey = "kittykeys.customThemes"

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

    /// The things to try that the user has done: the keyboard records them and the app's Try it tab ticks them.
    /// Entries that aren't a `TryFeature` read as not tried.
    public var triedFeatures: Set<TryFeature> {
        let saved = (defaults.array(forKey: Self.triedFeaturesKey) ?? []).compactMap { $0 as? String }
        return Set(saved.compactMap(TryFeature.init(rawValue:)))
    }

    /// Records that the user has done `feature`. Writes only when it's new.
    public func markTried(_ feature: TryFeature) {
        var tried = triedFeatures
        guard tried.insert(feature).inserted else { return }
        defaults.set(tried.map(\.rawValue).sorted(), forKey: Self.triedFeaturesKey)
    }

    /// Forgets every thing tried, so the Try it list starts over.
    public func resetTried() {
        defaults.removeObject(forKey: Self.triedFeaturesKey)
    }

    /// The user's own themes, stored as JSON, in the order the app keeps them. A theme that can't be read is dropped
    /// and the rest load; missing or corrupt data gives none.
    public var customThemes: [ThemeSpec] {
        guard let data = defaults.data(forKey: Self.customThemesKey),
              let themes = try? JSONDecoder().decode([Lossy<ThemeSpec>].self, from: data)
        else { return [] }
        return themes.compactMap(\.value)
    }

    public func saveCustomThemes(_ themes: [ThemeSpec]) {
        guard let data = try? JSONEncoder().encode(themes) else { return }
        defaults.set(data, forKey: Self.customThemesKey)
    }

    /// Deletes the custom theme `id`. A slot that picked it goes back to its default: Automatic, or the same as Theme
    /// in dark mode.
    public func removeCustomTheme(id: String) {
        saveCustomThemes(customThemes.filter { $0.id != id })
        var settings = load()
        guard settings.themeID == id || settings.darkThemeID == id else { return }
        if settings.themeID == id { settings.themeID = Themes.automaticID }
        if settings.darkThemeID == id { settings.darkThemeID = "" }
        save(settings)
    }
}

/// One element of a saved array: nil when it can't be decoded, so one bad element doesn't lose the others.
private struct Lossy<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: any Decoder) throws {
        value = try? Value(from: decoder)
    }
}
