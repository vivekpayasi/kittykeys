import KeyboardCore
import SwiftUI

/// A field to try the keyboard in, as each kind of field an app can ask for: the keys change with it. Below it, things
/// to try, each ticked once the keyboard reports it done.
struct TryItView: View {
    /// The kinds of field to try.
    enum FieldType: String, CaseIterable, Identifiable {
        case text = "Text", email = "Email", web = "Web", number = "Number"

        var id: Self { self }

        var keyboardType: UIKeyboardType {
            switch self {
            case .text: .default
            case .email: .emailAddress
            case .web: .URL
            case .number: .numberPad
            }
        }
    }

    /// The shared settings, where the keyboard records the things tried. nil without the App Group.
    let store: SettingsStore?
    @State private var text = ""
    @State private var fieldType = FieldType.text
    @FocusState private var isFocused: Bool
    @State private var tried: Set<TryFeature> = []
    /// Whether the list shows after everything is tried, when it folds away.
    @State private var showsFinishedList = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Field", selection: $fieldType) {
                        ForEach(FieldType.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    field
                        .focused($isFocused)
                        // A new field for each type, so iOS brings up the keys for it.
                        .id(fieldType)
                } footer: {
                    Text("The kittykeys keyboard must be picked with 🌐: touch and hold 🌐, then choose kittykeys.")
                }
                thingsToTry
            }
            // The keyboard covers the tab bar; dragging the form down puts it away.
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Try it")
        }
        // The new field exists only after this update, so it's focused on the next turn.
        .onChange(of: fieldType) { Task { isFocused = true } }
        // A `-kittykeysFocus` launch argument focuses the field, for UI tests on the simulator.
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("-kittykeysFocus") { isFocused = true }
        }
        // The keyboard writes from its own process, so the ticks are read again each second while the tab shows.
        .task {
            while !Task.isCancelled {
                tried = store?.triedFeatures ?? []
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    /// Text takes several lines; the others are single-line, as such fields are in apps.
    @ViewBuilder private var field: some View {
        switch fieldType {
        case .text:
            TextField("Type here", text: $text, axis: .vertical)
                .lineLimit(5...)
        case .email, .web, .number:
            TextField("Type here", text: $text)
                .keyboardType(fieldType.keyboardType)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
    }

    /// The things to try, ticked as they're done. Once all are, the list folds into one line that can open it again.
    @ViewBuilder private var thingsToTry: some View {
        let allTried = tried.isSuperset(of: TryFeature.allCases)
        Section {
            if allTried && !showsFinishedList {
                Label("You've tried them all", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Button("Show the list") { showsFinishedList = true }
            } else {
                ForEach(TryFeature.allCases, id: \.self) { feature in
                    ThingToTry(text: Self.text(for: feature), done: tried.contains(feature))
                }
                if !tried.isEmpty {
                    Button("Start over") {
                        store?.resetTried()
                        tried = []
                        showsFinishedList = false
                    }
                }
            }
        } header: {
            Text("Things to try")
        } footer: {
            Text(store == nil
                ? appGroupUnavailableMessage
                : "Each gets its tick when you do it with kittykeys, which needs Full Access. kittykeys notes only that you did it, never what you typed.")
        }
    }

    private static func text(for feature: TryFeature) -> LocalizedStringKey {
        switch feature {
        case .cursorMove: "Hold the **space bar**, then slide to move the cursor"
        case .longPressSymbol: "Hold a key for the symbol in its corner, like **a** for **@**"
        case .wordDelete: "Slide left from **⌫** to delete a whole word"
        case .textReplacement: "Type **omw**, then space, for a shortcut; **⌫** right after undoes it"
        case .emojiSearch: "Tap **😊**, search for an emoji, and tap it"
        }
    }
}

/// One thing to try, with a green tick once it's done.
private struct ThingToTry: View {
    let text: LocalizedStringKey
    let done: Bool

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
        }
        .accessibilityValue(done ? "Done" : "")
    }
}
