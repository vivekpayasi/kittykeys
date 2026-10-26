import KeyboardCore
import SwiftUI
import UIKit

/// How to turn the keyboard on, what Full Access is for, and whether the keyboard and the app share settings.
struct SetupView: View {
    let store: SettingsStore?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var status = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    // Meant to open this app's page in Settings, which lists its keyboard under Keyboards. The iOS 26.4
                    // simulator opens Settings' main page instead; the footer gives the way from there.
                    Button("Open Settings", systemImage: "gear") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                    SetupStep(1, "Tap **Open Settings**, then **Keyboards**.")
                    SetupStep(2, "Turn on **kittykeys**, then **Allow Full Access**.")
                } header: {
                    Text("Turn on kittykeys")
                } footer: {
                    Text("Or, in Settings, go to General › Keyboard › Keyboards › Add New Keyboard.")
                }
                Section("Full Access") {
                    Text("Full Access lets kittykeys use haptics and read the settings you choose here. kittykeys never connects to the internet: nothing you type leaves your phone.")
                }
                Section("Status") {
                    Text(status)
                }
            }
            .navigationTitle("Setup")
        }
        .onAppear(perform: refreshStatus)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshStatus() }
        }
    }

    /// Re-reads the keyboard's heartbeat, which it writes from another process.
    private func refreshStatus() {
        status = Self.status(of: store, now: .now)
    }

    private static func status(of store: SettingsStore?, now: Date) -> String {
        guard let store else { return appGroupUnavailableMessage }
        // Without Full Access the keyboard can't write its heartbeat, so no heartbeat can mean either.
        guard let opened = store.lastKeyboardOpen else { return "Not opened yet, or Full Access is off" }
        return "Keyboard last opened: \(relativeTime(of: opened, now: now))"
    }

    /// "just now" under a minute (or for a time ahead of the clock), else such as "5 minutes ago".
    private static func relativeTime(of date: Date, now: Date) -> String {
        guard now.timeIntervalSince(date) >= 60 else { return "just now" }
        return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: now)
    }
}

/// One numbered setup step.
private struct SetupStep: View {
    let number: Int
    let text: LocalizedStringKey

    init(_ number: Int, _ text: LocalizedStringKey) {
        self.number = number
        self.text = text
    }

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: "\(number).circle.fill")
                .foregroundStyle(.tint)
        }
    }
}
