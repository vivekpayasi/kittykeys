import KeyboardCore
import SwiftUI
import UIKit

/// How to turn the keyboard on and what Full Access is for. Each step shows a green tick once it's done, checked again
/// whenever the app comes back, as from Settings.
struct SetupView: View {
    let store: SettingsStore?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var isKeyboardAdded = false
    @State private var isFullAccessConfirmed = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    // Meant to open this app's page in Settings, which lists its keyboard under Keyboards. The iOS 26.4
                    // simulator opens Settings' main page instead; the footer gives the way from there.
                    Button("Open Settings", systemImage: "gear") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                    SetupStep(1, "Tap **Open Settings**, then **Keyboards**, and turn on **kittykeys**.", done: isKeyboardAdded)
                    SetupStep(2, "Turn on **Allow Full Access**.", done: isFullAccessConfirmed)
                } header: {
                    Text("Turn on kittykeys")
                } footer: {
                    Text(stepsFooter)
                }
                Section("Full Access") {
                    Text("Full Access lets kittykeys use haptics and read the settings you choose here. kittykeys never connects to the internet: nothing you type leaves your phone.")
                }
            }
            .navigationTitle("Setup")
        }
        .onAppear(perform: refresh)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refresh() }
        }
    }

    private var stepsFooter: String {
        let manualPath = "Or, in Settings, go to General › Keyboard › Keyboards › Add New Keyboard."
        guard store != nil else { return "\(manualPath)\n\n\(appGroupUnavailableMessage)." }
        guard isKeyboardAdded, !isFullAccessConfirmed else { return manualPath }
        return "\(manualPath)\n\nStep 2 gets its tick once kittykeys has opened with Full Access on: try it in the Try it tab."
    }

    private func refresh() {
        let added = Self.addedKeyboards()
        isKeyboardAdded = added.map(Self.containsThisKeyboard) ?? false
        // Removing a keyboard turns its Full Access off, so a removed keyboard's last opening proves nothing.
        if added != nil, !isKeyboardAdded { store?.lastKeyboardOpen = nil }
        // Without Full Access the keyboard can't write to the shared settings, so a time it opened means Full Access was on.
        isFullAccessConfirmed = isKeyboardAdded && store?.lastKeyboardOpen != nil
    }

    /// The bundle ids of the user's keyboards, which iOS keeps under "AppleKeyboards" in the defaults every app can
    /// read; nil if it isn't there.
    private static func addedKeyboards() -> [String]? {
        UserDefaults.standard.array(forKey: "AppleKeyboards") as? [String]
    }

    /// Whether `added` lists this app's keyboard. The id comes from the installed extension, since a sideloading tool
    /// may have changed it.
    private static func containsThisKeyboard(_ added: [String]) -> Bool {
        guard let plugIns = Bundle.main.builtInPlugInsURL,
              let extensions = try? FileManager.default.contentsOfDirectory(at: plugIns, includingPropertiesForKeys: nil)
        else { return false }
        return extensions.contains { url in
            url.pathExtension == "appex" && Bundle(url: url)?.bundleIdentifier.map(added.contains) == true
        }
    }
}

/// One numbered setup step, with a green tick in place of its number once it's done.
private struct SetupStep: View {
    let number: Int
    let text: LocalizedStringKey
    let done: Bool

    init(_ number: Int, _ text: LocalizedStringKey, done: Bool) {
        self.number = number
        self.text = text
        self.done = done
    }

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: done ? "checkmark.circle.fill" : "\(number).circle.fill")
                .foregroundStyle(done ? AnyShapeStyle(.green) : AnyShapeStyle(.tint))
        }
        .accessibilityValue(done ? "Done" : "")
    }
}
