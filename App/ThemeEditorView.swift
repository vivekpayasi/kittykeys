import KeyboardCore
import KeyboardUI
import SwiftUI
import UIKit

/// Edits one of the user's themes. Each change saves at once. A working kittykeys keyboard in the theme sits at the
/// bottom, typing into nothing, so presses and popups can be tried.
struct ThemeEditorView: View {
    let store: SettingsStore
    @State private var spec: ThemeSpec
    @State private var confirmsDelete = false
    @Environment(\.dismiss) private var dismiss

    init(store: SettingsStore, theme: ThemeSpec) {
        self.store = store
        _spec = State(initialValue: theme)
    }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $spec.name)
            }
            Section {
                Toggle("Use iOS's background", isOn: usesSystemBackground)
                if spec.background != nil {
                    ColorPicker("Background", selection: backgroundColor, supportsOpacity: false)
                }
            } footer: {
                Text("iOS's own keyboard background is light or dark with your phone.")
            }
            Section {
                Picker("Key style", selection: $spec.keyShape) {
                    Text("Filled").tag(KeyShape.filled)
                    Text("Outlined").tag(KeyShape.outlined)
                    Text("No borders").tag(KeyShape.borderless)
                }
                .pickerStyle(.segmented)
                ColorPicker("Letter keys", selection: color(\.key), supportsOpacity: false)
                ColorPicker("Function keys", selection: color(\.specialKey), supportsOpacity: false)
                if spec.keyShape == .filled {
                    Toggle("Key shadow", isOn: $spec.keyShadow)
                }
            } header: {
                Text("Keys")
            } footer: {
                Text(keysFooter)
            }
            Section {
                ColorPicker("Letters", selection: color(\.label), supportsOpacity: false)
                ColorPicker("Function key labels", selection: color(\.functionLabel), supportsOpacity: false)
                ColorPicker("Symbol hints", selection: color(\.hint), supportsOpacity: false)
            } header: {
                Text("Labels")
            } footer: {
                Text("Function keys are shift, ⌫, 123, 😊, return and the keys beside space.")
            }
            Section {
                ColorPicker("Accent", selection: color(\.accent), supportsOpacity: false)
                Toggle("Return key in accent", isOn: $spec.returnKeyAccent)
            } header: {
                Text("Accent")
            } footer: {
                Text("The accent marks the symbol you'll get when you hold a key.")
            }
            Section("Font") {
                Picker("Font", selection: $spec.fontDesign) {
                    Text("Default").tag(FontDesign.standard)
                    Text("Rounded").tag(FontDesign.rounded)
                    Text("Serif").tag(FontDesign.serif)
                    Text("Monospaced").tag(FontDesign.monospaced)
                }
                Picker("Weight", selection: $spec.fontWeight) {
                    Text("Light").tag(FontWeight.light)
                    Text("Regular").tag(FontWeight.regular)
                    Text("Medium").tag(FontWeight.medium)
                    Text("Bold").tag(FontWeight.bold)
                }
            }
            Section {
                Button("Delete theme", role: .destructive) { confirmsDelete = true }
            }
        }
        .navigationTitle(spec.name.isEmpty ? "Theme" : spec.name)
        .navigationBarTitleDisplayMode(.inline)
        // The tab bar floats over the bottom of the screen, where the keyboard sits.
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ThemePreviewKeyboard(spec: spec)
                .background(Color(themeColor: spec.previewBackdrop).ignoresSafeArea(edges: .bottom))
        }
        .onChange(of: spec) { _, spec in save(spec) }
        .confirmationDialog("Delete \(spec.name)?", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("Delete theme", role: .destructive) {
                store.removeCustomTheme(id: spec.id)
                dismiss()
            }
        }
    }

    private var keysFooter: String {
        switch spec.keyShape {
        case .filled: "Letter keys include space. Function keys include the keys beside space."
        case .outlined: "Keys are drawn as outlines in their colour, and fill with it while pressed."
        case .borderless: "Keys show their colour only while pressed."
        }
    }

    /// Off gives the theme a background, starting from the grey it showed.
    private var usesSystemBackground: Binding<Bool> {
        Binding(
            get: { spec.background == nil },
            set: { spec.background = $0 ? nil : spec.previewBackdrop })
    }

    private var backgroundColor: Binding<Color> {
        Binding(
            get: { Color(themeColor: spec.background ?? spec.previewBackdrop) },
            set: { spec.background = ThemeColor($0) })
    }

    private func color(_ keyPath: WritableKeyPath<ThemeSpec, ThemeColor> & Sendable) -> Binding<Color> {
        Binding(
            get: { Color(themeColor: spec[keyPath: keyPath]) },
            set: { spec[keyPath: keyPath] = ThemeColor($0) })
    }

    /// Writes the theme over its saved copy. A theme deleted meanwhile isn't brought back.
    private func save(_ spec: ThemeSpec) {
        var themes = store.customThemes
        guard let index = themes.firstIndex(where: { $0.id == spec.id }) else { return }
        themes[index] = spec
        store.saveCustomThemes(themes)
    }
}

extension ThemeColor {
    /// The nearest opaque sRGB colour to `color`, as the colour picker gives it.
    init(_ color: Color) {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        func byte(_ value: CGFloat) -> UInt32 { UInt32((min(max(value, 0), 1) * 255).rounded()) }
        self.init(rgb: byte(red) << 16 | byte(green) << 8 | byte(blue))
    }
}

/// A working kittykeys keyboard in a theme, typing into nothing.
struct ThemePreviewKeyboard: UIViewRepresentable {
    let spec: ThemeSpec

    func makeUIView(context: Context) -> UIView {
        do {
            return ThemePreviewKeyboardView(layouts: try LayoutSet.bundled())
        } catch {
            let label = UILabel()
            label.text = "Couldn't load the layouts: \(error)"
            label.numberOfLines = 0
            return label
        }
    }

    func updateUIView(_ view: UIView, context: Context) {
        (view as? ThemePreviewKeyboardView)?.theme = KeyboardTheme(spec: spec)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIView, context: Context) -> CGSize? {
        guard let width = proposal.width else { return nil }
        return CGSize(width: width, height: (uiView as? ThemePreviewKeyboardView)?.keyboardHeight ?? 44)
    }
}

/// The keyboard view over a controller of its own, on the theme's backdrop.
final class ThemePreviewKeyboardView: UIView {
    /// Its own Recent and skin tones, so trying emoji here leaves the app's defaults alone.
    private static let emojiSuite = "kittykeys.themePreview.emoji"

    var theme = KeyboardTheme.light {
        didSet {
            keyboardView.theme = theme
            backgroundColor = theme.backdrop
        }
    }

    var keyboardHeight: CGFloat {
        CGFloat(controller.height)
    }

    private let controller: KeyboardController
    private let keyboardView: KeyboardView

    init(layouts: LayoutSet) {
        controller = KeyboardController(
            document: DiscardingDocument(), layouts: layouts, settings: KeyboardSettings(), feedback: SilentFeedback())
        controller.keyboardWillAppear(FieldTraits())
        keyboardView = KeyboardView(
            controller: controller, feedback: SilentFeedback(),
            emojiPreferences: EmojiPreferences(defaults: UserDefaults(suiteName: Self.emojiSuite) ?? .standard))
        super.init(frame: .zero)
        backgroundColor = theme.backdrop
        keyboardView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(keyboardView)
        NSLayoutConstraint.activate([
            keyboardView.topAnchor.constraint(equalTo: topAnchor),
            keyboardView.leadingAnchor.constraint(equalTo: leadingAnchor),
            keyboardView.trailingAnchor.constraint(equalTo: trailingAnchor),
            keyboardView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }
}

/// A field that keeps what is typed only so shift and the double-space full stop behave as in a real one.
@MainActor private final class DiscardingDocument: TextDocument {
    /// Enough of the end of the text for the controller's rules; older text is dropped.
    private static let kept = 64
    private var text = ""

    var textBefore: String? { text.isEmpty ? nil : text }
    var textAfter: String? { nil }

    func insert(_ inserted: String) {
        text = String((text + inserted).suffix(Self.kept))
    }

    func deleteBackward(count: Int) {
        text = String(text.dropLast(max(count, 0)))
    }

    func moveCursor(by graphemes: Int) {}
}
