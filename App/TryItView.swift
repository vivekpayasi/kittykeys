import SwiftUI

/// A field to try the keyboard in.
struct TryItView: View {
    @State private var text = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Type here", text: $text, axis: .vertical)
                        .lineLimit(5...)
                } footer: {
                    Text("The catkeys keyboard must be picked with 🌐: touch and hold 🌐, then choose catkeys.")
                }
            }
            // The keyboard covers the tab bar; dragging the form down puts it away.
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Try it")
        }
    }
}
