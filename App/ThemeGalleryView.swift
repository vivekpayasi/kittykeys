import KeyboardCore
import SwiftUI

/// Which theme a gallery picks: the keyboard's, or the one it shows in dark mode.
enum ThemeSlot: Hashable {
    case main, dark
}

/// The themes as cards: the ready-made ones, then the user's own and a New theme card. Tapping a card picks it for
/// the slot and saves at once; the keyboard reads it the next time it appears. New, Customise and Duplicate make a
/// custom theme, pick it and open the editor.
struct ThemeGalleryView: View {
    let store: SettingsStore?
    let slot: ThemeSlot
    @State private var settings = KeyboardSettings()
    @State private var custom: [ThemeSpec] = []
    /// The custom theme the editor shows.
    @State private var editing: ThemeSpec?
    @State private var deleting: ThemeSpec?
    @Environment(\.colorScheme) private var colorScheme

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 16)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if store == nil {
                    Text(appGroupUnavailableMessage)
                        .foregroundStyle(.secondary)
                }
                LazyVGrid(columns: columns, spacing: 16) {
                    if slot == .dark {
                        Button { pick("") } label: {
                            ThemeCard(spec: sameAsThemeSpec, title: "Same as Theme", isPicked: pickedID == "")
                        }
                    }
                    ForEach(Themes.presets) { spec in
                        Button { pick(spec.id) } label: {
                            ThemeCard(spec: shown(spec), title: spec.name, isPicked: pickedID == spec.id)
                        }
                        .contextMenu {
                            Button("Customise", systemImage: "paintbrush") { create(from: shown(spec)) }
                        }
                    }
                }
                Text("Your themes")
                    .font(.headline)
                    .padding(.top, 12)
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(custom) { spec in
                        Button { pick(spec.id) } label: {
                            ThemeCard(spec: spec, title: spec.name, isPicked: pickedID == spec.id)
                        }
                        .contextMenu {
                            Button("Edit", systemImage: "slider.horizontal.3") { editing = spec }
                            Button("Duplicate", systemImage: "plus.square.on.square") { create(from: spec) }
                            Button("Delete", systemImage: "trash", role: .destructive) { deleting = spec }
                        }
                    }
                    Button { create(from: currentSpec) } label: { NewThemeCard() }
                }
                Text("Touch and hold a theme to customise, edit or delete it.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding()
        }
        .disabled(store == nil)
        .navigationTitle(slot == .main ? "Theme" : "In dark mode")
        .navigationDestination(item: $editing) { spec in
            if let store { ThemeEditorView(store: store, theme: spec) }
        }
        .confirmationDialog(
            "Delete \(deleting?.name ?? "")?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete theme", role: .destructive) {
                if let deleting { delete(deleting) }
            }
        }
        .onAppear(perform: reload)
    }

    /// The id this gallery's slot holds; empty in the dark slot for the same as Theme.
    private var pickedID: String {
        slot == .main ? settings.themeID : settings.darkThemeID
    }

    /// The theme the slot shows now, which a new theme starts from.
    private var currentSpec: ThemeSpec {
        Themes.active(
            themeID: settings.themeID, darkThemeID: slot == .dark ? settings.darkThemeID : "", custom: custom,
            isDark: slot == .dark || colorScheme == .dark)
    }

    /// Theme's theme as it looks in dark mode, for the Same as Theme card.
    private var sameAsThemeSpec: ThemeSpec {
        Themes.active(themeID: settings.themeID, darkThemeID: "", custom: custom, isDark: true)
    }

    /// Automatic drawn as it looks here: dark in the dark slot and in dark mode.
    private func shown(_ spec: ThemeSpec) -> ThemeSpec {
        guard spec.id == Themes.automaticID else { return spec }
        return slot == .dark || colorScheme == .dark ? Themes.automaticDark : Themes.automaticLight
    }

    private func reload() {
        guard let store else { return }
        settings = store.load()
        custom = store.customThemes
    }

    /// Saves `id` into the slot, over the latest saved settings so nothing changed elsewhere is lost.
    private func pick(_ id: String) {
        guard let store else { return }
        var latest = store.load()
        switch slot {
        case .main: latest.themeID = id
        case .dark: latest.darkThemeID = id
        }
        store.save(latest)
        settings = latest
    }

    private func create(from base: ThemeSpec) {
        guard let store else { return }
        let spec = Themes.newCustom(from: base, existing: custom)
        custom.append(spec)
        store.saveCustomThemes(custom)
        pick(spec.id)
        editing = spec
    }

    private func delete(_ spec: ThemeSpec) {
        store?.removeCustomTheme(id: spec.id)
        reload()
    }
}

/// A theme's card: its swatch, its name, and a tick when it is picked.
struct ThemeCard: View {
    let spec: ThemeSpec
    let title: String
    let isPicked: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ThemeSwatch(spec: spec)
                .aspectRatio(1.7, contentMode: .fit)
                .clipShape(.rect(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(isPicked ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: isPicked ? 3 : 1)
                }
            HStack(spacing: 4) {
                Text(title)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if isPicked {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.tint)
                }
            }
            .font(.subheadline)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isPicked ? [.isSelected] : [])
    }
}

/// The card that makes a new theme.
private struct NewThemeCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                .aspectRatio(1.7, contentMode: .fit)
                .overlay {
                    Image(systemName: "plus")
                        .font(.title2)
                        .foregroundStyle(.tint)
                }
            Text("New theme")
                .font(.subheadline)
        }
        .contentShape(.rect)
    }
}
