import SwiftUI

/// A field to try the keyboard in, as each kind of field an app can ask for: the keys change with it.
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

    @State private var text = ""
    @State private var fieldType = FieldType.text
    @FocusState private var isFocused: Bool

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
}
