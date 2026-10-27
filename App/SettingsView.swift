import KeyboardCore
import SwiftUI

/// The keyboard settings. Each change is saved at once; the keyboard reads them each time it appears.
/// Without a store the controls show the defaults, disabled.
struct SettingsView: View {
    let store: SettingsStore?
    @State private var settings = KeyboardSettings()
    /// The currencies the layouts offer, for the Currency picker. Empty if the layouts can't load.
    private let currencies = (try? LayoutSet.bundled().currencies) ?? []
    /// The region's currency, as the keyboard picks it when the setting is Automatic.
    private let regionCurrency = Locale.current.currencySymbol

    var body: some View {
        NavigationStack {
            Form {
                if store == nil {
                    Section {
                        Text(appGroupUnavailableMessage)
                    }
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
                        ForEach(currencies, id: \.self) { Text($0).tag($0) }
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
        }
        .onAppear {
            if let store { settings = store.load() }
        }
    }

    /// The currency Automatic gives, as `CurrencyOrder` picks it.
    private var automaticCurrency: String {
        CurrencyOrder.ordered(choice: "", region: regionCurrency, all: currencies).first ?? "?"
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

    /// A binding to one setting that saves all the settings whenever it changes.
    private func saving<Value>(_ keyPath: WritableKeyPath<KeyboardSettings, Value> & Sendable) -> Binding<Value> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: { newValue in
                settings[keyPath: keyPath] = newValue
                store?.save(settings)
            })
    }
}
