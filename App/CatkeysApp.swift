import KeyboardCore
import SwiftUI

@main
struct CatkeysApp: App {
    /// The settings shared with the keyboard through the App Group. nil when this install has no App Group;
    /// the Setup and Settings tabs then say so.
    private let settingsStore = SettingsStore.appGroup(
        id: Bundle.main.object(forInfoDictionaryKey: "CatkeysAppGroup") as? String)

    var body: some Scene {
        WindowGroup {
            ContentView(settingsStore: settingsStore)
        }
    }
}
