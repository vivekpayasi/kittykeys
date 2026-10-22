import Testing
import KeyboardCore

// Emoji search's keys (ruling M3-R15): "Search emoji" in the panel brings back the letter keys, which type into
// `state.searchQuery` instead of the document; a result tapped still goes into the document. `Harness` is in
// ControllerTests.

@MainActor struct EmojiSearchControllerTests {
    /// A harness over `text` with the emoji panel open and then search.
    func searching(_ text: String = "", autoCap: AutoCapMode = .none) throws -> Harness {
        let k = try Harness(text, autoCap: autoCap)
        try k.tap("😊")
        k.controller.openEmojiSearch()
        #expect(k.controller.state.panel == .emojiSearch)
        return k
    }

    func type(_ labels: String, into k: Harness) throws {
        for label in labels { try k.tap(label == " " ? "space" : String(label)) }
    }

    func hasKey(_ label: String, _ k: Harness) -> Bool {
        k.controller.frames.contains { $0.key.label == label }
    }

    // MARK: Opening and closing

    @Test func openingShowsTheLetterKeysWithoutTheNumberRow() throws {
        let k = try Harness()
        let height = k.controller.height
        let qRect = try k.key("q").rect
        try k.tap("123")
        try k.tap("😊")
        let changes = k.changes
        k.controller.openEmojiSearch()
        #expect(k.changes == changes + 1)
        #expect(k.controller.state.panel == .emojiSearch && k.controller.state.searchQuery == "")
        #expect(k.controller.state.pageID == "latin-qwerty" && k.controller.state.pressedKeyIDs.isEmpty)
        // The number row's band is left for the results; the other rows stay where they were, so the height too.
        #expect(!hasKey("1", k) && hasKey("q", k) && hasKey("123", k))
        #expect(try k.key("q").rect == qRect && k.controller.height == height)
    }

    @Test func searchOpensOnlyFromThePanel() throws {
        let k = try Harness()
        k.controller.openEmojiSearch()
        k.controller.clearEmojiSearch()
        k.controller.closeEmojiSearch()
        #expect(k.controller.state.panel == .keys && k.changes == 0)
        // In search, the panel's own ⌫ and ABC do nothing.
        let s = try searching("ok")
        try type("a", into: s)
        s.controller.deleteFromPanel()
        s.controller.closePanel()
        #expect(s.controller.state.panel == .emojiSearch && s.doc.text == "ok" && s.controller.state.searchQuery == "a")
    }

    @Test func clearAndClose() throws {
        let k = try searching()
        try type("ab", into: k)
        var changes = k.changes
        k.controller.clearEmojiSearch()
        #expect(k.controller.state.searchQuery == "" && k.controller.state.panel == .emojiSearch && k.changes == changes + 1)
        try type("c", into: k)
        changes = k.changes
        k.controller.closeEmojiSearch()
        #expect(k.controller.state.panel == .emoji && k.controller.state.searchQuery == "" && k.changes == changes + 1)
        // The keys under the panel have their number row again.
        #expect(hasKey("1", k))
        // Search opens empty again.
        k.controller.openEmojiSearch()
        #expect(k.controller.state.searchQuery == "")
    }

    @Test func closingBringsBackTheKeysThePanelCovered() throws {
        // An email field on the symbols page. Search shows the letters with the standard bottom row; once it closes,
        // the panel's ABC shows the symbols page with the email row again.
        let k = try Harness()
        k.controller.fieldDidChange(FieldTraits(kind: .email, autoCap: .none))
        try k.tap("123")
        try k.tap("😊")
        k.controller.openEmojiSearch()
        let bottom = { k.controller.frames.filter { $0.row == k.controller.frames.last?.row }.map(\.key.label) }
        #expect(k.controller.state.pageID == "latin-qwerty" && bottom().contains(",") && !bottom().contains("@"))
        k.controller.closeEmojiSearch()
        k.controller.closePanel()
        #expect(k.controller.state.pageID == "symbols-1" && bottom().contains("@") && hasKey("1", k))
    }

    @Test func keyboardWillAppearEndsSearch() throws {
        let k = try searching()
        try type("a", into: k)
        k.controller.keyboardWillAppear(FieldTraits(autoCap: .none))
        #expect(k.controller.state.panel == .keys && k.controller.state.searchQuery == "")
        #expect(k.controller.state.pageID == "latin-qwerty" && hasKey("1", k))
        try k.tap("b")
        #expect(k.doc.text == "b")
        // Space's hold moves the cursor again.
        try k.down("space")
        k.wait(0.4)
        #expect(k.controller.state.cursorMode)
    }

    @Test func aNewFieldDuringSearchKeepsTheSearchKeys() throws {
        let k = try searching()
        k.controller.fieldDidChange(FieldTraits(kind: .number, autoCap: .none))
        #expect(k.controller.state.panel == .emojiSearch && k.controller.state.pageID == "latin-qwerty" && !hasKey("1", k))
        try type("a", into: k)
        #expect(k.controller.state.searchQuery == "a")
        // The new field's first page shows once search and the panel close.
        k.controller.closeEmojiSearch()
        k.controller.closePanel()
        #expect(k.controller.state.pageID == "symbols-1")
    }

    // MARK: Typing into the query

    @Test func keysTypeIntoTheQueryNotTheDocument() throws {
        let k = try searching("hi")
        let changes = k.changes
        try type("lau", into: k)
        #expect(k.controller.state.searchQuery == "lau" && k.doc.text == "hi")
        // Each tap notifies on its press, its query edit and its release.
        #expect(k.changes > changes)
    }

    @Test func noShiftOrAutoCapitalsInTheQuery() throws {
        // At a sentence start shift is on by itself. It stays on for the document, but the query takes none of it.
        let k = try searching("Hi. ", autoCap: .sentences)
        #expect(k.controller.state.shift == .once)
        try type("r", into: k)
        // Shift taps change nothing, not even a double tap.
        try k.tap("⇧")
        try k.tap("⇧")
        try type("e d", into: k)
        #expect(k.controller.state.searchQuery == "re d" && k.controller.state.shift == .once && k.doc.text == "Hi. ")
        // Caps lock from before search types nothing in capitals either.
        let caps = try Harness()
        try caps.tap("⇧")
        try caps.tap("⇧")
        try caps.tap("😊")
        caps.controller.openEmojiSearch()
        try type("ok", into: caps)
        #expect(caps.controller.state.searchQuery == "ok" && caps.controller.state.shift == .locked)
    }

    @Test func keysShowNoShiftWhileSearching() throws {
        let k = try searching("Hi. ", autoCap: .sentences)
        #expect(k.controller.state.shift == .once && k.controller.state.shownShift == .off)
        k.controller.closeEmojiSearch()
        k.controller.closePanel()
        #expect(k.controller.state.shownShift == .once)
    }

    @Test func spacesCollapse() throws {
        let k = try searching()
        // A space at the start adds nothing; two spaces make one, never a full stop.
        try type(" red  h", into: k)
        #expect(k.controller.state.searchQuery == "red h" && k.doc.text == "")
    }

    @Test func queryStopsAt64Characters() throws {
        let k = try searching()
        try type(String(repeating: "ab ", count: 23), into: k)
        #expect(k.controller.state.searchQuery.count == 64 && k.controller.state.searchQuery.hasPrefix("ab ab"))
        try type("c", into: k)
        #expect(k.controller.state.searchQuery.count == 64 && k.doc.text == "")
        try k.tap("⌫")
        try type("z", into: k)
        #expect(k.controller.state.searchQuery.count == 64 && k.controller.state.searchQuery.hasSuffix("z"))
    }

    @Test func spaceHoldTypesASpace() throws {
        let k = try searching()
        try type("a", into: k)
        let p = try k.down("space")
        #expect(k.controller.nextDeadline == nil)
        k.wait(1)
        #expect(!k.controller.state.cursorMode)
        k.up(at: p)
        try type("b", into: k)
        #expect(k.controller.state.searchQuery == "a b")
        // Out of search, the hold moves the cursor again.
        k.controller.closeEmojiSearch()
        k.controller.closePanel()
        try k.down("space")
        k.wait(0.4)
        #expect(k.controller.state.cursorMode)
    }

    @Test func symbolsAndLongPressOptionsGoIntoTheQuery() throws {
        let k = try searching()
        try k.tap("123")
        #expect(k.controller.state.pageID == "symbols-1" && !hasKey("1", k))
        try k.tap("#")
        try k.tap("ABC")
        #expect(k.controller.state.pageID == "latin-qwerty")
        // Holding d offers ₹ $ €, ₹ first.
        let p = try k.down("d")
        k.wait(0.3)
        #expect(k.controller.state.alternates != nil)
        k.up(at: p)
        #expect(k.controller.state.searchQuery == "#₹" && k.doc.text == "")
    }

    @Test func emojiKeyDoesNothingInSearch() throws {
        let k = try searching()
        try type("a", into: k)
        try k.tap("😊")
        #expect(k.controller.state.panel == .emojiSearch && k.controller.state.searchQuery == "a")
    }

    // MARK: Backspace and return

    @Test func backspaceEditsTheQueryThenLeaves() throws {
        let k = try searching("ok")
        try type("hi", into: k)
        try k.tap("⌫")
        #expect(k.controller.state.searchQuery == "h" && k.controller.state.panel == .emojiSearch)
        try k.tap("⌫")
        #expect(k.controller.state.searchQuery == "" && k.controller.state.panel == .emojiSearch)
        // ⌫ on the empty query goes back to the panel, ending its own touch.
        let p = try k.down("⌫")
        #expect(k.controller.state.panel == .emoji && k.doc.text == "ok")
        #expect(k.controller.state.pressedKeyIDs.isEmpty && k.controller.nextDeadline == nil)
        k.wait(1)
        k.up(at: p)
        #expect(k.doc.text == "ok" && hasKey("1", k))
    }

    @Test func heldBackspaceEmptiesTheQueryButStays() throws {
        let k = try searching()
        try type("heart", into: k)
        let p = try k.down("⌫")
        // Repeats at 0.4, 0.47, 0.54 and 0.61 s take the rest, and more repeats find the query empty.
        k.wait(1)
        #expect(k.controller.state.searchQuery == "" && k.controller.state.panel == .emojiSearch)
        k.up(at: p)
        // A new ⌫ on the empty query leaves.
        try k.tap("⌫")
        #expect(k.controller.state.panel == .emoji)
    }

    @Test func backspaceSwipeDeletesTheRestOfTheWord() throws {
        let k = try searching()
        try type("red hea", into: k)
        let p = try k.down("⌫")
        #expect(k.controller.state.searchQuery == "red he")
        k.move(to: Point(x: p.x - 30, y: p.y))
        #expect(k.controller.state.searchQuery == "red ")
        k.up(at: Point(x: p.x - 30, y: p.y))
    }

    @Test func returnClosesSearch() throws {
        let k = try searching("ok")
        try type("c", into: k)
        try k.tap("return")
        #expect(k.controller.state.panel == .emoji && k.controller.state.searchQuery == "" && k.doc.text == "ok")
        #expect(k.controller.state.pressedKeyIDs.isEmpty && hasKey("1", k))
    }

    @Test func leavingSearchEndsOtherTouches() throws {
        // Finger 2 holds a long-press on d while finger 1 taps return: search closes and d types nothing.
        let k = try searching()
        let pd = try k.down("d", id: 2)
        k.wait(0.3)
        #expect(k.controller.state.alternates != nil)
        try k.tap("return", id: 1)
        #expect(k.controller.state.panel == .emoji && k.controller.state.alternates == nil)
        #expect(k.controller.state.pressedKeyIDs.isEmpty && k.controller.nextDeadline == nil)
        k.up(at: pd, id: 2)
        #expect(k.controller.state.searchQuery == "" && k.doc.text == "")
    }

    // MARK: Results into the document

    @Test func insertingFromSearchTypesIntoTheDocument() throws {
        let k = try searching("Hi. ", autoCap: .sentences)
        try type("jo", into: k)
        k.controller.insertEmoji("😂")
        #expect(k.doc.text == "Hi. 😂" && k.controller.state.searchQuery == "jo" && k.controller.state.panel == .emojiSearch)
        // The document's shift follows the emoji, as from the panel.
        #expect(k.controller.state.shift == .off)
        try type("y", into: k)
        #expect(k.doc.text == "Hi. 😂" && k.controller.state.searchQuery == "joy")
    }
}
