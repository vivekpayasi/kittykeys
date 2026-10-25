import SwiftUI

/// Fields to try the keyboard in: free text, and a one-time code field like the ones apps use for codes sent by SMS.
struct TryItView: View {
    /// The fields. A launch argument, `-catkeysFocus text` or `-catkeysFocus code`, focuses one, for UI tests on the
    /// simulator.
    enum Field: String { case text, code }

    @State private var text = ""
    @State private var code = ""
    @FocusState private var focused: Field?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Type here", text: $text, axis: .vertical)
                        .lineLimit(5...)
                        .focused($focused, equals: .text)
                } footer: {
                    Text("The catkeys keyboard must be picked with 🌐: touch and hold 🌐, then choose catkeys.")
                }
                Section {
                    TextField("Code", text: $code)
                        .textContentType(.oneTimeCode)
                        .keyboardType(.numberPad)
                        .focused($focused, equals: .code)
                } footer: {
                    Text("A one-time code field: catkeys hands it to the next keyboard, and 🌐 brings catkeys back.")
                }
            }
            // The keyboard covers the tab bar; dragging the form down puts it away.
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Try it")
        }
        .onAppear {
            if let field = UserDefaults.standard.string(forKey: "catkeysFocus").flatMap(Field.init(rawValue:)) {
                focused = field
            }
        }
    }
}
