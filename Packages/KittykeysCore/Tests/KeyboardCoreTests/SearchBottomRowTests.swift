@testable import KeyboardCore
import Testing

/// How emoji search relabels its bottom row's page key (ruling M3-R18), for rows the bundled layouts don't have.
struct SearchBottomRowTests {
    static func key(_ label: String, _ action: KeyAction, icon: String? = nil) -> KeySpec {
        KeySpec(label: label, output: label, longPress: [], width: 1.5, action: action, icon: icon)
    }

    static let abc = key("ABC", .switchPage(.letters))

    @Test func onlyTheFirstPageKeyReadsABC() {
        // A row with two page keys: the first takes ABC's label and icon in its own place and width; the second keeps
        // its label (both go back to the panel in search).
        let row = [
            Self.key("123", .switchPage(.named("symbols-1")), icon: "number"), Self.key("😊", .emoji),
            Self.key("#+=", .switchPage(.named("symbols-2"))),
        ]
        let searched = KeyboardController.searchBottomRow(row, letters: Self.abc)
        #expect(searched.map(\.label) == ["ABC", "😊", "#+="])
        #expect(searched[0].icon == nil && searched[0].width == 1.5)
        #expect(searched[0].action == .switchPage(.named("symbols-1")) && searched[2] == row[2])
    }

    @Test func withoutALettersKeyTheRowStays() {
        let row = [Self.key("123", .switchPage(.named("symbols-1"))), Self.key("😊", .emoji)]
        #expect(KeyboardController.searchBottomRow(row, letters: nil) == row)
    }

    @Test func aRowWithoutAPageKeyStays() {
        let row = [Self.key("😊", .emoji), Self.key("space", .space)]
        #expect(KeyboardController.searchBottomRow(row, letters: Self.abc) == row)
    }
}
