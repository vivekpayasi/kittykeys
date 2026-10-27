import KeyboardCore
import SwiftUI

/// Shown on the Setup and Settings tabs when `SettingsStore.appGroup(id:)` returns nil.
let appGroupUnavailableMessage = "Settings can't be shared on this install: the App Group isn't available"

/// The app's tabs. The simulator screenshot script opens one with `-kittykeysTab <raw value>`.
enum AppTab: String {
    case setup, settings, tryIt = "tryit"
}

struct ContentView: View {
    let settingsStore: SettingsStore?
    /// A `-kittykeysTab <tab>` launch argument lands in UserDefaults' argument domain; Setup otherwise.
    @State private var selectedTab = UserDefaults.standard.string(forKey: "kittykeysTab").flatMap(AppTab.init(rawValue:)) ?? .setup

    var body: some View {
        // The simulator screenshot script launches with this argument to see the keyboard view.
        if ProcessInfo.processInfo.arguments.contains("-kittykeysPreview") {
            KeyboardPreviewView()
                .ignoresSafeArea()
        } else {
            TabView(selection: $selectedTab) {
                Tab("Setup", systemImage: "list.number", value: AppTab.setup) {
                    SetupView(store: settingsStore)
                }
                Tab("Settings", systemImage: "gearshape", value: AppTab.settings) {
                    SettingsView(store: settingsStore)
                }
                Tab("Try it", systemImage: "keyboard", value: AppTab.tryIt) {
                    TryItView()
                }
            }
        }
    }
}
