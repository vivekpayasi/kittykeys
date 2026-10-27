import SwiftUI

/// A field to try the keyboard in.
struct TryItView: View {
    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Type here", text: $text, axis: .vertical)
                        .lineLimit(5...)
                        .focused($isFocused)
                } footer: {
                    Text("The kittykeys keyboard must be picked with 🌐: touch and hold 🌐, then choose kittykeys.")
                }
            }
            // The keyboard covers the tab bar; dragging the form down puts it away.
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Try it")
        }
        // A `-kittykeysFocus` launch argument focuses the field, for UI tests on the simulator.
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("-kittykeysFocus") { isFocused = true }
        }
    }
}
