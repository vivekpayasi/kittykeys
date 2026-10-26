import Testing
import KeyboardCore

struct TextReplacementsTests {
    static let omw = TextReplacements(pairs: [(shortcut: "omw", phrase: "On my way!"), (shortcut: "ty", phrase: "thank you")])

    @Test func findsTheShortcutBeforeTheCursor() {
        let found = Self.omw.replacement(before: "see you omw")
        #expect(found?.length == 3 && found?.phrase == "On my way!")
    }

    @Test func matchesInAnyCase() {
        #expect(Self.omw.replacement(before: "OMW")?.phrase == "On my way!")
        #expect(Self.omw.replacement(before: "Omw")?.phrase == "On my way!")
    }

    /// A capital typed at the start, as automatic capitals give at a sentence start, capitalises the phrase.
    @Test func capitalisesThePhraseAfterACapital() {
        #expect(Self.omw.replacement(before: "Ty")?.phrase == "Thank you")
        #expect(Self.omw.replacement(before: "ty")?.phrase == "thank you")
    }

    @Test func needsTheWholeShortcut() {
        #expect(Self.omw.replacement(before: "xomw") == nil)
        #expect(Self.omw.replacement(before: "om") == nil)
        #expect(Self.omw.replacement(before: "omw ") == nil)
        #expect(Self.omw.replacement(before: nil) == nil)
        #expect(Self.omw.replacement(before: "") == nil)
    }

    @Test func findsTheShortcutAfterPunctuation() {
        let found = Self.omw.replacement(before: "(omw")
        #expect(found?.length == 3 && found?.phrase == "On my way!")
    }

    @Test func aShortcutMayHoldPunctuation() {
        let replacements = TextReplacements(pairs: [(shortcut: "addr.", phrase: "221B Baker Street")])
        #expect(replacements.replacement(before: "at addr.")?.length == 5)
    }

    /// iOS's lexicon also lists contact names, each as its own shortcut; those and pairs that can't be typed are dropped.
    @Test func dropsNamesAndPairsThatCannotBeTyped() {
        let replacements = TextReplacements(pairs: [
            (shortcut: "Asha", phrase: "Asha"), (shortcut: "", phrase: "x"), (shortcut: "a b", phrase: "c"),
            (shortcut: "x", phrase: ""),
        ])
        #expect(replacements.isEmpty)
        #expect(TextReplacements.none.isEmpty && !Self.omw.isEmpty)
    }

    @Test func theFirstOfTwoSameShortcutsWins() {
        let replacements = TextReplacements(pairs: [(shortcut: "omw", phrase: "On my way!"), (shortcut: "OMW", phrase: "other")])
        #expect(replacements.replacement(before: "omw")?.phrase == "On my way!")
    }

    @Test(arguments: [" ", "\n", ".", ",", "!", "?", ";", ":", "।"])
    func wordEndsAreTriggers(_ text: String) {
        #expect(TextReplacements.isTrigger(text))
    }

    @Test(arguments: ["a", "'", "-", "@", "/", "😀", ".com", ""])
    func otherTextIsNoTrigger(_ text: String) {
        #expect(!TextReplacements.isTrigger(text))
    }
}

@MainActor struct TextReplacementControllerTests {
    static let replacements = TextReplacements(pairs: [
        (shortcut: "omw", phrase: "On my way!"), (shortcut: "brb", phrase: "be right back"),
    ])

    func harness(_ text: String) throws -> Harness {
        let k = try Harness(text)
        k.controller.textReplacements = Self.replacements
        return k
    }

    @Test func spaceExpandsAShortcut() throws {
        let k = try harness("see you omw")
        try k.tap("space")
        #expect(k.doc.text == "see you On my way! ")
    }

    @Test func returnAndPunctuationExpandToo() throws {
        let k = try harness("omw")
        try k.tap("return")
        #expect(k.doc.text == "On my way!\n")
        let p = try harness("brb")
        try p.tap(".")
        #expect(p.doc.text == "be right back.")
    }

    @Test func lettersDoNotExpand() throws {
        let k = try harness("omw")
        try k.tap("s")
        #expect(k.doc.text == "omws")
    }

    /// ⌫ right after an expansion puts the shortcut back, and the next space leaves it alone.
    @Test func backspaceRightAfterUndoes() throws {
        let k = try harness("omw")
        try k.tap("space")
        try k.tap("⌫")
        #expect(k.doc.text == "omw")
        try k.tap("space")
        #expect(k.doc.text == "omw ")
    }

    @Test func backspaceUndoesOnlyRightAfter() throws {
        let k = try harness("omw")
        try k.tap("space")
        try k.tap("x")
        try k.tap("⌫")
        try k.tap("⌫")
        #expect(k.doc.text == "On my way!")
    }

    @Test func aMovedCursorEndsTheUndo() throws {
        let k = try harness("omw")
        try k.tap("space")
        k.doc.moveCursor(by: -1)
        k.controller.documentDidChange()
        try k.tap("⌫")
        #expect(k.doc.text == "On my way ")
    }

    @Test func doubleSpaceAfterAnExpansion() throws {
        let k = try harness("brb")
        try k.tap("space")
        try k.tap("space")
        #expect(k.doc.text == "be right back. ")
    }

    @Test(arguments: [FieldKind.email, .url, .number])
    func noExpansionInAddressAndNumberFields(_ kind: FieldKind) throws {
        let k = try harness("omw")
        k.controller.fieldDidChange(FieldTraits(kind: kind, autoCap: .none))
        try k.tap(kind == .number ? "," : "space")
        #expect(!k.doc.text.contains("On my way!"))
    }

    @Test func noShortcutsNoExpansion() throws {
        let k = try Harness("omw")
        try k.tap("space")
        #expect(k.doc.text == "omw ")
    }
}
