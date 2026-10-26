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

    /// A phrase that starts with a capital where it wants one, such as "iOS" or "iPhone", keeps its case.
    @Test func keepsAPhraseWithItsOwnCapitals() {
        let replacements = TextReplacements(pairs: [(shortcut: "ios", phrase: "iOS"), (shortcut: "ip", phrase: "iPhone 17")])
        #expect(replacements.replacement(before: "Ios")?.phrase == "iOS")
        #expect(replacements.replacement(before: "Ip")?.phrase == "iPhone 17")
    }

    @Test func needsTheWholeShortcut() {
        #expect(Self.omw.replacement(before: "xomw") == nil)
        #expect(Self.omw.replacement(before: "om") == nil)
        #expect(Self.omw.replacement(before: "omw ") == nil)
        #expect(Self.omw.replacement(before: nil) == nil)
        #expect(Self.omw.replacement(before: "") == nil)
    }

    @Test func findsTheShortcutAfterOpeningPunctuation() {
        for opening in ["(", "[", "\"", "'", "“", "¿", "¡"] {
            let found = Self.omw.replacement(before: opening + "omw")
            #expect(found?.length == 3 && found?.phrase == "On my way!")
        }
    }

    /// Only opening punctuation comes off: a shortcut inside a handle, a tag, a path or a longer word stays as typed.
    @Test func ignoresAShortcutInsideOtherText() {
        for text in ["@omw", "#omw", "a/omw", "re-omw", "x.omw"] {
            #expect(Self.omw.replacement(before: text) == nil)
        }
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

    @Test(arguments: [FieldKind.url, .number])
    func noExpansionInURLAndNumberFields(_ kind: FieldKind) throws {
        let k = try harness("omw")
        k.controller.fieldDidChange(FieldTraits(kind: kind, autoCap: .none))
        try k.tap(kind == .number ? "," : "space")
        #expect(!k.doc.text.contains("On my way!"))
    }

    /// In an email field a "." belongs to the address, so only space and return end a shortcut, as for "@@".
    @Test func emailFieldsExpandOnSpaceOnly() throws {
        let k = try harness("x@@")
        k.controller.textReplacements = TextReplacements(pairs: [(shortcut: "x@@", phrase: "me@example.com")])
        k.controller.fieldDidChange(FieldTraits(kind: .email, autoCap: .none))
        try k.tap("space")
        #expect(k.doc.text == "me@example.com ")
        let dot = try harness("omw")
        dot.controller.fieldDidChange(FieldTraits(kind: .email, autoCap: .none))
        try dot.tap(".")
        #expect(dot.doc.text == "omw.")
    }

    /// A field that ignores return, as one that sends with it, leaves nothing after the phrase; ⌫ then deletes as usual.
    @Test func noUndoWhenTheWordEndDidNotLand() throws {
        let k = try harness("I am omw")
        k.doc.ignoredInsertions = ["\n"]
        try k.tap("return")
        #expect(k.doc.text == "I am On my way!")
        try k.tap("⌫")
        #expect(k.doc.text == "I am On my way")
    }

    /// After an undo, the shortcut stays as typed only right there: once anything is typed, it expands again.
    @Test func keepingTheShortcutEndsWithTheNextEdit() throws {
        let k = try harness("omw")
        try k.tap("space")
        try k.tap("⌫")
        #expect(k.doc.text == "omw")
        // The host sends the message and empties the field; the next message types the shortcut again.
        k.doc.deleteBackward(count: 3)
        k.controller.documentDidChange()
        for letter in ["o", "m", "w", "space"] { try k.tap(letter) }
        #expect(k.doc.text == "On my way! ")
    }

    @Test func aNewFieldForgetsTheUndo() throws {
        let k = try harness("omw")
        try k.tap("space")
        k.controller.fieldDidChange(FieldTraits(kind: .email, autoCap: .none))
        try k.tap("⌫")
        #expect(k.doc.text == "On my way!")
    }

    @Test func noShortcutsNoExpansion() throws {
        let k = try Harness("omw")
        try k.tap("space")
        #expect(k.doc.text == "omw ")
    }
}
