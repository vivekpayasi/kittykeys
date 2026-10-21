import SwiftUI

struct ContentView: View {
    var body: some View {
        // The simulator screenshot script launches with this argument to see the keyboard view.
        if ProcessInfo.processInfo.arguments.contains("-catkeysPreview") {
            KeyboardPreviewView()
                .ignoresSafeArea()
        } else {
            Text("catkeys")
        }
    }
}
