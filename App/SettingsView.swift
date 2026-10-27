import KeyboardCore
import SwiftUI

/// A page Settings opens. The simulator screenshot script opens one with `-kittykeysSettingsPage <raw value>`.
enum SettingsPage: String, Hashable {
    case themes, darkThemes = "darkthemes"
}

/// The keyboard settings. Each change is saved at once; the keyboard reads them each time it appears.
/// Without a store the controls show the defaults, disabled.
struct SettingsView: View {
    let store: SettingsStore?
    @State private var settings = KeyboardSettings()
    /// The custom themes, for the picked themes' names.
    @State private var customThemes: [ThemeSpec] = []
    /// A `-kittykeysSettingsPage <page>` launch argument opens that page.
    @State private var path: [SettingsPage] =
        UserDefaults.standard.string(forKey: "kittykeysSettingsPage").flatMap(SettingsPage.init(rawValue:)).map { [$0] } ?? []
    /// The layouts, for the currencies they offer. nil if they can't load.
    private static let layouts = try? LayoutSet.bundled()
    private static var currencies: [String] { layouts?.currencies ?? [] }

    var body: some View {
        NavigationStack(path: $path) {
            Form {
                if store == nil {
                    Section {
                        Text(appGroupUnavailableMessage)
                    }
                }
                Section {
                    NavigationLink(value: SettingsPage.themes) {
                        LabeledContent("Theme", value: themeName(settings.themeID))
                    }
                    NavigationLink(value: SettingsPage.darkThemes) {
                        LabeledContent(
                            "In dark mode",
                            value: settings.darkThemeID.isEmpty ? "Same as Theme" : themeName(settings.darkThemeID))
                    }
                } footer: {
                    Text(
                        "iOS draws the strip below the keys, with 🌐 and the microphone, light or dark to match your phone. Pick a dark theme for dark mode to match it."
                    )
                }
                Section {
                    Toggle("Haptics", isOn: saving(\.haptics))
                    Toggle("Key click sound", isOn: saving(\.sound))
                    Toggle("Key popup", isOn: saving(\.keyPopup))
                    Toggle("Double-space full stop", isOn: saving(\.doubleSpacePeriod))
                }
                .disabled(store == nil)
                Section {
                    LabeledContent("Long-press delay") {
                        Text("\(delayText) s")
                    }
                    Slider(value: saving(\.longPressDelay), in: KeyboardSettings.longPressDelayRange, step: 0.05) {
                        Text("Long-press delay")
                    }
                    .accessibilityValue("\(delayText) seconds")
                } footer: {
                    Text("How long you hold a key before its symbols show.")
                }
                .disabled(store == nil)
                Section {
                    Picker("Currency", selection: saving(\.currency)) {
                        Text("Automatic (\(automaticCurrency))").tag("")
                        ForEach(Self.currencies, id: \.self) { Text($0).tag($0) }
                    }
                    Toggle("Show a .com key in web addresses", isOn: saving(\.showDotComKey))
                } footer: {
                    Text(
                        "Your currency comes first when you hold d, and on the 123 page. In web addresses, hold . for .com and other endings; the .com key makes the space bar narrower."
                    )
                }
                .disabled(store == nil)
                Section {
                    Toggle("Switch to Apple's keyboard for codes", isOn: saving(\.handOffCodeFields))
                } footer: {
                    Text(
                        "iOS offers codes from Messages only on its own keyboard. In a code field, kittykeys switches to the next keyboard in iOS Settings › General › Keyboard › Keyboards, so list Apple's keyboard right after kittykeys. Press 🌐 to come back; kittykeys then stays in that field."
                    )
                }
                .disabled(store == nil)
                Section {
                    LabeledContent("Version", value: appVersion)
                }
            }
            .navigationTitle("Settings")
            .navigationDestination(for: SettingsPage.self) { page in
                ThemeGalleryView(store: store, slot: page == .themes ? .main : .dark)
            }
        }
        .onAppear(perform: reload)
        // Coming back from a gallery: show what it picked.
        .onChange(of: path) { reload() }
    }

    private func reload() {
        guard let store else { return }
        settings = store.load()
        customThemes = store.customThemes
    }

    /// A theme's name; an id that names nothing, such as a deleted theme's, shows as the theme the keyboard falls back to.
    private func themeName(_ id: String) -> String {
        Themes.spec(id: id, custom: customThemes, isDark: false)?.name ?? "Automatic"
    }

    /// The currency Automatic gives, picked from the region's currency code as the keyboard picks it.
    private var automaticCurrency: String {
        let region = Self.layouts?.currencySymbol(forCode: Locale.current.currency?.identifier)
        return CurrencyOrder.ordered(choice: "", region: region, all: Self.currencies).first ?? "?"
    }

    /// The app's version and build, such as "0.2.0 (2)".
    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    /// The delay in seconds to two decimals, such as "0.30".
    private var delayText: String {
        settings.longPressDelay.formatted(.number.precision(.fractionLength(2)))
    }

    /// A binding to one setting that saves it over the latest saved settings whenever it changes, so a theme picked in
    /// a gallery meanwhile isn't lost.
    private func saving<Value>(_ keyPath: WritableKeyPath<KeyboardSettings, Value> & Sendable) -> Binding<Value> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: { newValue in
                var latest = store?.load() ?? settings
                latest[keyPath: keyPath] = newValue
                settings = latest
                store?.save(latest)
            })
    }
}
