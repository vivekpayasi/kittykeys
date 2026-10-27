import Foundation
import Testing
import KeyboardCore

struct ThemeTests {
    private func preset(_ id: String) -> ThemeSpec {
        Themes.presets.first { $0.id == id }!
    }

    private func decode(_ json: String) throws -> ThemeSpec {
        try JSONDecoder().decode(ThemeSpec.self, from: Data(json.utf8))
    }

    // MARK: Colours

    @Test func hexRoundTrips() {
        #expect(ThemeColor(hex: "#3df58a")?.hex == "#3DF58A")
        #expect(ThemeColor(hex: "3DF58A")?.rgb == 0x3DF58A)
        for bad in ["#12345", "zzzzzz", "", "#1234567", "#12345G"] {
            #expect(ThemeColor(hex: bad) == nil, "\(bad)")
        }
    }

    @Test func contrastAndLuminance() {
        #expect(abs(ThemeColor.black.contrast(with: .white) - 21) < 0.01)
        #expect(abs(ThemeColor.white.contrast(with: .black) - 21) < 0.01)
        #expect(ThemeColor(rgb: 0x3DF58A).contrast(with: ThemeColor(rgb: 0x3DF58A)) == 1)
        #expect(ThemeColor.black.luminance == 0 && abs(ThemeColor.white.luminance - 1) < 1e-9)
    }

    @Test func mixRounds() {
        #expect(ThemeColor.black.mixed(with: .white, 0.5).hex == "#808080")
        #expect(ThemeColor(rgb: 0x123456).mixed(with: .white, 0) == ThemeColor(rgb: 0x123456))
        #expect(ThemeColor(rgb: 0x123456).mixed(with: .white, 1) == .white)
    }

    @Test func onAccentPicksReadableText() {
        var spec = Themes.automaticLight
        #expect(spec.onAccent == .white)
        spec.accent = ThemeColor(rgb: 0x3DF58A)
        #expect(spec.onAccent == .black)
    }

    @Test func derivedColoursMatchTodaysKeyboard() {
        #expect(Themes.automaticLight.popup.hex == "#FFFFFF")
        #expect(Themes.automaticLight.searchField.hex == "#FFFFFF")
        #expect(Themes.automaticDark.popup.hex == "#818184")
        #expect(Themes.automaticDark.searchField.hex == "#454548")
    }

    // MARK: Keys

    @Test func restingAndPressedByShape() {
        var spec = Themes.automaticLight
        #expect(spec.restingFill(.letter) == spec.key)
        #expect(spec.pressedFill(.letter) == spec.specialKey)
        #expect(spec.restingFill(.function) == spec.specialKey)
        #expect(spec.pressedFill(.function) == spec.key)
        #expect(spec.restingFill(.punctuation) == spec.specialKey)
        #expect(spec.outline(.letter) == nil)

        spec.keyShape = .outlined
        #expect(spec.restingFill(.letter) == nil)
        #expect(spec.outline(.letter) == spec.key)
        #expect(spec.outline(.function) == spec.specialKey)
        #expect(spec.pressedFill(.letter) == spec.key)

        spec.keyShape = .borderless
        #expect(spec.restingFill(.letter) == nil && spec.outline(.letter) == nil)
        #expect(spec.pressedFill(.letter) == spec.key)
        #expect(spec.pressedFill(.function) == spec.specialKey)
    }

    @Test func pressedFillShowsWhenColoursMatch() {
        let neon = preset("neon")
        #expect(neon.key == neon.specialKey)
        #expect(neon.pressedFill(.letter) == neon.key.mixed(with: neon.label, 0.2))
        #expect(neon.pressedFill(.function) == neon.specialKey.mixed(with: neon.functionLabel, 0.2))

        var flat = neon
        flat.keyShape = .borderless
        flat.background = flat.key
        #expect(flat.pressedFill(.letter) == flat.key.mixed(with: flat.label, 0.2))
        flat.background = .black
        flat.key = ThemeColor(rgb: 0x2A2A2A)
        #expect(flat.pressedFill(.letter) == flat.key)
    }

    @Test func labelsByRole() {
        let neon = preset("neon")
        #expect(neon.labelColor(.function).hex == "#3DF58A")
        #expect(neon.labelColor(.returnKey).hex == "#3DF58A")
        #expect(neon.labelColor(.letter).hex == "#FFFFFF")
        #expect(neon.labelColor(.punctuation).hex == "#FFFFFF")
        #expect(neon.labelColor(.space) == neon.hint)
        #expect(neon.restingFill(.returnKey) == neon.specialKey)

        let midnight = preset("midnight")
        #expect(midnight.returnKeyAccent)
        #expect(midnight.restingFill(.returnKey) == midnight.accent)
        #expect(midnight.labelColor(.returnKey) == midnight.onAccent)
        #expect(midnight.pressedFill(.returnKey) == midnight.accent.mixed(with: midnight.onAccent, 0.25))
        var outlined = midnight
        outlined.keyShape = .outlined
        #expect(outlined.restingFill(.returnKey) == midnight.accent)
        #expect(outlined.outline(.returnKey) == nil)
    }

    @Test func shadowOnlyOnFilled() {
        var paper = preset("paper")
        #expect(paper.hasShadow(.letter) && paper.hasShadow(.function))
        paper.keyShape = .outlined
        #expect(!paper.hasShadow(.letter))
        paper.keyShape = .borderless
        #expect(!paper.hasShadow(.letter))
        #expect(!preset("neon").hasShadow(.letter))
    }

    // MARK: Ready-made themes

    @Test func presetsAreReadable() {
        for spec in Themes.presets + [Themes.automaticDark] {
            func surface(_ role: KeyRole) -> ThemeColor? { spec.restingFill(role) ?? spec.background }
            if let letters = surface(.letter) {
                #expect(spec.label.contrast(with: letters) >= 4.5, "\(spec.id) letters")
                #expect(spec.hint.contrast(with: letters) >= 2.5, "\(spec.id) hints")
            }
            if let functions = surface(.function) {
                #expect(spec.functionLabel.contrast(with: functions) >= 3, "\(spec.id) function labels")
            }
        }
    }

    @Test func presetIdsAreUniqueAndStable() {
        let ids = Themes.presets.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(Themes.presets.first == Themes.automaticLight)
        #expect(ids.first == Themes.automaticID)
        #expect(!ids.contains { $0.hasPrefix(Themes.customIDPrefix) })
        #expect(ids == ["automatic", "light", "dark", "neon", "midnight", "amber", "synthwave", "terminal", "paper", "rose"])
        #expect(Themes.presets.allSatisfy { !$0.name.isEmpty })
    }

    // MARK: Picking

    @Test func darkSlotPicksByAppearance() {
        let neon = preset("neon"), midnight = preset("midnight")
        for isDark in [false, true] {
            #expect(Themes.active(themeID: "neon", darkThemeID: "", custom: [], isDark: isDark) == neon)
        }
        #expect(Themes.active(themeID: "neon", darkThemeID: "midnight", custom: [], isDark: true) == midnight)
        #expect(Themes.active(themeID: "neon", darkThemeID: "midnight", custom: [], isDark: false) == neon)
        #expect(Themes.active(themeID: "automatic", darkThemeID: "", custom: [], isDark: false) == Themes.automaticLight)
        #expect(Themes.active(themeID: "automatic", darkThemeID: "", custom: [], isDark: true) == Themes.automaticDark)
    }

    @Test func unknownIdsFallBack() {
        let neon = preset("neon")
        #expect(Themes.active(themeID: "neon", darkThemeID: "custom-gone", custom: [], isDark: true) == neon)
        #expect(Themes.active(themeID: "custom-gone", darkThemeID: "", custom: [], isDark: false) == Themes.automaticLight)
        #expect(Themes.active(themeID: "custom-gone", darkThemeID: "nope", custom: [], isDark: true) == Themes.automaticDark)
        var mine = neon
        mine.id = "custom-1"
        mine.name = "Mine"
        #expect(Themes.active(themeID: "custom-1", darkThemeID: "", custom: [mine], isDark: false) == mine)
        #expect(Themes.spec(id: "custom-1", custom: [mine], isDark: false) == mine)
        #expect(Themes.spec(id: "custom-2", custom: [mine], isDark: false) == nil)
    }

    // MARK: Saving

    @Test func specDecodingIsForgiving() throws {
        let midnight = preset("midnight")
        let data = try JSONEncoder().encode(midnight)
        #expect(try JSONDecoder().decode(ThemeSpec.self, from: data) == midnight)

        let sparse = try decode(#"{"id":"custom-1","name":"Sparse"}"#)
        var expected = Themes.automaticLight
        expected.id = "custom-1"
        expected.name = "Sparse"
        #expect(sparse == expected)

        let bad = try decode(#"{"id":"custom-2","key":"nonsense","keyShape":"wavy","fontWeight":7,"background":null}"#)
        #expect(bad.key == Themes.automaticLight.key)
        #expect(bad.keyShape == .filled)
        #expect(bad.fontWeight == .regular)
        #expect(bad.background == nil)

        let solid = try decode(##"{"id":"custom-3","background":"#000000"}"##)
        #expect(solid.background == .black)

        #expect(throws: (any Error).self) { try decode(#"{"name":"No id"}"#) }
        #expect(throws: (any Error).self) { try decode(#"{"id":""}"#) }
    }

    @Test func newCustomNamesAndIds() {
        let neon = preset("neon")
        let first = Themes.newCustom(from: neon, existing: [])
        #expect(first.name == "My theme")
        #expect(first.id.hasPrefix(Themes.customIDPrefix))
        var expected = neon
        expected.id = first.id
        expected.name = first.name
        #expect(first == expected)

        let second = Themes.newCustom(from: neon, existing: [first])
        #expect(second.name == "My theme 2")
        #expect(second.id != first.id)
        #expect(Themes.newCustom(from: neon, existing: [first, second]).name == "My theme 3")
        #expect(Themes.newCustom(from: neon, existing: [second]).name == "My theme")
    }
}
