import KeyboardCore
import SwiftUI

/// The keyboard settings. Each change is saved at once; the keyboard reads them each time it appears.
/// Without a store the controls show the defaults, disabled.
struct SettingsView: View {
    let store: SettingsStore?
    @State private var settings = KeyboardSettings()

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
                    Toggle("Switch to Apple's keyboard for codes", isOn: saving(\.handOffCodeFields))
                } footer: {
                    Text(
                        "iOS offers codes from Messages only on its own keyboard. In a code field, catkeys switches to the next keyboard in iOS Settings › General › Keyboard › Keyboards, so list Apple's keyboard right after catkeys. Press 🌐 to come back; catkeys then stays in that field."
                    )
                }
                .disabled(store == nil)
            }
            .navigationTitle("Settings")
        }
        .onAppear {
            if let store { settings = store.load() }
        }
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
