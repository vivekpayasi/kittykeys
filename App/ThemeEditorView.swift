import KeyboardCore
import KeyboardUI
import SwiftUI
import UIKit

/// Edits one of the user's themes. Each change saves at once. With Dark version on, Light and Dark tabs pick which look
/// the options below them change. A working kittykeys keyboard in the look being edited sits at the top, typing into
/// nothing, so presses and popups can be tried. At the top it stays in sight while iOS's colour picker covers the
/// bottom half of the screen, and while the keyboard for the name field is up.
struct ThemeEditorView: View {
    let store: SettingsStore
    @State private var spec: ThemeSpec
    /// Whether the options change the dark look; only with one.
    @State private var editsDark = false
    /// The dark look while Dark version is off, so turning it back on in this visit restores it.
    @State private var stashedDark: ThemeStyle?
    @State private var confirmsDelete = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    /// Edits `theme` as last saved, falling back to the copy given.
    init(store: SettingsStore, theme: ThemeSpec) {
        self.store = store
        _spec = State(initialValue: store.customThemes.first { $0.id == theme.id } ?? theme)
    }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $spec.name)
            }
            Section {
                Toggle("Dark version", isOn: hasDarkVersion)
                if spec.dark != nil {
                    Picker("Look", selection: $editsDark) {
                        Text("Light").tag(false)
                        Text("Dark").tag(true)
                    }
                    .pickerStyle(.segmented)
                }
                startFromMenu
            } footer: {
                Text(
                    spec.dark == nil
                        ? "One look in light and dark mode. Turn on Dark version for a second look in dark mode."
                        : "The options below change the \(editsDark ? "dark" : "light") look. The dark look shows in dark mode, and in apps that ask for a dark keyboard."
                )
            }
            Section {
                Toggle("Use iOS's background", isOn: usesSystemBackground)
                if style.wrappedValue.background != nil {
                    ColorPicker("Background", selection: backgroundColor, supportsOpacity: false)
                    Toggle("Round top corners", isOn: style.roundsTopCorners)
                    Toggle("Fade into iOS's bar", isOn: style.fadesTopEdge)
                }
            } header: {
                Text("Background")
            } footer: {
                Text(
                    style.wrappedValue.background == nil
                        ? "iOS's own keyboard background is light or dark with your phone."
                        : "iOS draws a rounded bar above the keyboard. Round top corners follows its curve; Fade lets the bar melt into your colour."
                )
            }
            Section {
                Picker("Key style", selection: style.keyShape) {
                    Text("Filled").tag(KeyShape.filled)
                    Text("Outlined").tag(KeyShape.outlined)
                    Text("No borders").tag(KeyShape.borderless)
                }
                .pickerStyle(.segmented)
                ColorPicker("Letter keys", selection: color(\.key), supportsOpacity: false)
                ColorPicker("Function keys", selection: color(\.specialKey), supportsOpacity: false)
                if style.wrappedValue.keyShape == .filled {
                    Toggle("Key shadow", isOn: style.keyShadow)
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
                Toggle("Return key in accent", isOn: style.returnKeyAccent)
            } header: {
                Text("Accent")
            } footer: {
                Text("The accent marks the symbol you'll get when you hold a key.")
            }
            Section("Font") {
                Picker("Font", selection: style.fontDesign) {
                    Text("Default").tag(FontDesign.standard)
                    Text("Rounded").tag(FontDesign.rounded)
                    Text("Serif").tag(FontDesign.serif)
                    Text("Monospaced").tag(FontDesign.monospaced)
                }
                Picker("Weight", selection: style.fontWeight) {
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
        // The tab bar floats over the bottom of the form, which is short with the keyboard above it.
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .top, spacing: 0) {
            ThemePreviewKeyboard(style: style.wrappedValue, isDark: previewIsDark)
        }
        .onChange(of: spec) { _, spec in save(spec) }
        .confirmationDialog("Delete \(spec.name)?", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("Delete theme", role: .destructive) {
                store.removeCustomTheme(id: spec.id)
                dismiss()
            }
        }
    }

    /// The look the options change: the dark one on the Dark tab, else the light one.
    private var style: Binding<ThemeStyle> {
        Binding(
            get: { editsDark ? spec.dark ?? spec.light : spec.light },
            set: { style in
                if editsDark, spec.dark != nil { spec.dark = style } else { spec.light = style }
            })
    }

    /// On adds a dark look, the one turned off earlier in this visit or else a copy of the light one, and opens it.
    private var hasDarkVersion: Binding<Bool> {
        Binding(
            get: { spec.dark != nil },
            set: { on in
                if on {
                    spec.dark = stashedDark ?? spec.light
                    editsDark = true
                } else {
                    stashedDark = spec.dark
                    spec.dark = nil
                    editsDark = false
                }
            })
    }

    /// Copies a ready-made or saved theme's look, for the appearance being edited, into it.
    private var startFromMenu: some View {
        let others = store.customThemes.filter { $0.id != spec.id }
        let isDark = editsDark
        return Menu {
            ForEach(Themes.presets) { preset in
                Button(preset.name) { style.wrappedValue = preset.style(isDark: isDark) }
            }
            if !others.isEmpty {
                Section("Your themes") {
                    ForEach(others) { theme in
                        Button(theme.name) { style.wrappedValue = theme.style(isDark: isDark) }
                    }
                }
            }
        } label: {
            LabeledContent("Start from") {
                Image(systemName: "chevron.up.chevron.down")
            }
        }
    }

    /// The bar behind the live keyboard: dark for the dark look, light for the light one, and for a theme with one
    /// look, as the app is.
    private var previewIsDark: Bool {
        spec.dark == nil ? colorScheme == .dark : editsDark
    }

    private var keysFooter: String {
        switch style.wrappedValue.keyShape {
        case .filled: "Letter keys include space. Function keys include the keys beside space."
        case .outlined: "Keys are drawn as outlines in their colour, and fill with it while pressed."
        case .borderless: "Keys show their colour only while pressed."
        }
    }

    /// Off gives the look a background, starting from the grey it showed.
    private var usesSystemBackground: Binding<Bool> {
        Binding(
            get: { style.wrappedValue.background == nil },
            set: { style.wrappedValue.background = $0 ? nil : style.wrappedValue.previewBackdrop })
    }

    private var backgroundColor: Binding<Color> {
        Binding(
            get: { Color(themeColor: style.wrappedValue.background ?? style.wrappedValue.previewBackdrop) },
            set: { style.wrappedValue.background = ThemeColor($0) })
    }

    private func color(_ keyPath: WritableKeyPath<ThemeStyle, ThemeColor> & Sendable) -> Binding<Color> {
        Binding(
            get: { Color(themeColor: style.wrappedValue[keyPath: keyPath]) },
            set: { style.wrappedValue[keyPath: keyPath] = ThemeColor($0) })
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

/// A working kittykeys keyboard in a look, typing into nothing, on iOS's bar for light or dark mode.
struct ThemePreviewKeyboard: UIViewRepresentable {
    let style: ThemeStyle
    let isDark: Bool

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
        guard let view = view as? ThemePreviewKeyboardView else { return }
        view.theme = KeyboardTheme(style: style)
        view.backgroundColor = KeyboardTheme.systemBackdrop(isDark: isDark)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIView, context: Context) -> CGSize? {
        guard let width = proposal.width else { return nil }
        return CGSize(width: width, height: (uiView as? ThemePreviewKeyboardView)?.keyboardHeight ?? 44)
    }
}

/// The keyboard view over a controller of its own; its host colours what shows behind it.
final class ThemePreviewKeyboardView: UIView {
    /// Its own Recent and skin tones, so trying emoji here leaves the app's defaults alone.
    private static let emojiSuite = "kittykeys.themePreview.emoji"

    var theme = KeyboardTheme.light {
        didSet { keyboardView.theme = theme }
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
        backgroundColor = KeyboardTheme.systemBackdrop(isDark: false)
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
