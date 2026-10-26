import Testing
import KeyboardCore

// The controller's side of the emoji panel: the 😊 key opens it, emoji are typed and deleted through the controller,
// and ABC goes back to the keys as the panel found them. `Harness` is in ControllerTests.

@MainActor struct EmojiControllerTests {
    @Test func emojiKeyOpensPanel() throws {
        let k = try Harness("hi")
        #expect(k.controller.state.panel == .keys)
        let p = try k.down("😊")
        #expect(k.changes == 1)
        k.now += 0.1
        // The lift opens the panel and lets go of the key: one notice.
        k.up(at: p)
        k.now += 0.1
        #expect(k.controller.state.panel == .emoji && k.doc.text == "hi" && k.changes == 2)
        // The keys stay as they were under the panel, with nothing held.
        #expect(k.controller.state.pageID == "latin-qwerty" && k.controller.state.pressedKeyIDs.isEmpty)
        // While the panel shows, the keys under it take no touches.
        try k.tap("a")
        let pDelete = try k.down("⌫")
        k.wait(1)
        k.up(at: pDelete)
        #expect(k.doc.text == "hi" && k.controller.state.pressedKeyIDs.isEmpty && k.controller.nextDeadline == nil)
        #expect(k.changes == 2)
    }

    @Test func insertEmojiTypesIt() throws {
        let k = try Harness("hi ")
        try k.tap("😊")
        k.controller.insertEmoji("👋🏽")
        #expect(k.doc.text == "hi 👋🏽" && k.controller.state.panel == .emoji)
    }

    @Test func panelDeleteRemovesWholeEmoji() throws {
        let flag = try Harness("hi 🇮🇳")
        try flag.tap("😊")
        flag.controller.deleteFromPanel()
        #expect(flag.doc.text == "hi ")

        let family = try Harness("👨‍👩‍👧")
        try family.tap("😊")
        family.controller.deleteFromPanel()
        #expect(family.doc.text == "")
        // Nothing left to delete: nothing happens.
        family.controller.deleteFromPanel()
        #expect(family.doc.text == "")

        let skin = try Harness("ok👋🏽")
        try skin.tap("😊")
        skin.controller.deleteFromPanel()
        #expect(skin.doc.text == "ok")
    }

    @Test func closePanelRestoresPage() throws {
        let k = try Harness()
        try k.tap("123")
        try k.tap("😊")
        #expect(k.controller.state.panel == .emoji)
        let changes = k.changes
        k.controller.closePanel()
        #expect(k.controller.state.panel == .keys && k.controller.state.pageID == "symbols-1")
        #expect(k.changes == changes + 1)
        // Closing a panel that isn't showing changes nothing, not even a key held down.
        let p = try k.down("@")
        k.controller.closePanel()
        #expect(k.changes == changes + 2 && !k.controller.state.pressedKeyIDs.isEmpty)
        k.now += 0.1
        k.up(at: p)
        #expect(k.doc.text == "@")

        // Caps lock is still on after the panel, emoji typed or not.
        let caps = try Harness()
        try caps.tap("⇧")
        try caps.tap("⇧")
        try caps.tap("😊")
        caps.controller.insertEmoji("😀")
        caps.controller.closePanel()
        #expect(caps.controller.state.shift == .locked)
        try caps.tap("a")
        #expect(caps.doc.text == "😀A")
    }

    @Test func keyboardWillAppearClosesPanel() throws {
        let k = try Harness()
        try k.tap("123")
        try k.tap("😊")
        k.controller.keyboardWillAppear(FieldTraits(autoCap: .none))
        #expect(k.controller.state.panel == .keys && k.controller.state.pageID == "latin-qwerty")
        try k.tap("a")
        #expect(k.doc.text == "a")
    }

    @Test func leavingThePanelCancelsTouches() throws {
        // Finger 1 holds ⌫ and finger 2 taps 😊: the panel ends the hold, so no repeat comes later.
        let k = try Harness("hi there")
        let p = try k.down("⌫", id: 1)
        k.wait(0.4)
        #expect(k.doc.text == "hi the")
        try k.tap("😊", id: 2)
        #expect(k.controller.state.panel == .emoji && k.controller.state.pressedKeyIDs.isEmpty)
        #expect(k.controller.nextDeadline == nil)
        k.wait(60)
        k.up(at: p, id: 1)
        #expect(k.doc.text == "hi the")
        // Once ABC closes the panel, a late repeat of the panel's ⌫ deletes nothing, and the keys work again.
        k.controller.closePanel()
        k.controller.deleteFromPanel()
        #expect(k.doc.text == "hi the")
        try k.tap("n")
        #expect(k.doc.text == "hi then")

        // A long-press popup goes too, and types nothing.
        let popup = try Harness()
        try popup.down("d", id: 1)
        popup.wait(0.3)
        #expect(popup.controller.state.alternates != nil)
        try popup.tap("😊", id: 2)
        #expect(popup.controller.state.alternates == nil && popup.controller.state.previewKeyID == nil)
        #expect(popup.controller.state.pressedKeyIDs.isEmpty && popup.doc.text == "")
    }

    @Test func panelOpenedByALostLiftLeavesNoHighlight() throws {
        // 😊's lift was lost, and the same finger lands on a: the lost lift opens the panel, which ends the new touch too.
        let k = try Harness()
        try k.down("😊", id: 1)
        k.now += 0.1
        let p = try k.down("a", id: 1)
        #expect(k.controller.state.panel == .emoji && k.controller.state.pressedKeyIDs.isEmpty)
        #expect(k.controller.state.previewKeyID == nil && k.controller.nextDeadline == nil)
        k.now += 0.1
        k.up(at: p, id: 1)
        #expect(k.doc.text == "")
    }

    @Test func lostLiftActsOnNothingUnderThePanel() throws {
        // As above, but the finger lands on a key that acts on touch-down. The panel opens first, so the key does nothing.
        let delete = try Harness("hello")
        try delete.down("😊", id: 1)
        delete.now += 0.1
        let p = try delete.down("⌫", id: 1)
        #expect(delete.controller.state.panel == .emoji && delete.doc.text == "hello")
        #expect(delete.controller.state.pressedKeyIDs.isEmpty && delete.controller.nextDeadline == nil)
        delete.wait(1)
        delete.up(at: p, id: 1)
        #expect(delete.doc.text == "hello")

        let page = try Harness()
        try page.down("😊", id: 1)
        page.now += 0.1
        try page.down("123", id: 1)
        page.controller.closePanel()
        #expect(page.controller.state.pageID == "latin-qwerty")

        let shift = try Harness()
        try shift.down("😊", id: 1)
        shift.now += 0.1
        try shift.down("⇧", id: 1)
        #expect(shift.controller.state.shift == .off && shift.controller.state.pressedKeyIDs.isEmpty)
    }

    @Test func panelEndsAHeldKeyWithoutTypingIt() throws {
        // Ruling M3-R7: a letter held when 😊 lifts goes without being typed, as with any key touch the panel ends.
        let k = try Harness()
        let pEmoji = try k.down("😊", id: 1)
        k.now += 0.05
        let pa = try k.down("a", id: 2)
        k.now += 0.05
        k.up(at: pEmoji, id: 1)
        #expect(k.controller.state.panel == .emoji && k.doc.text == "")
        #expect(k.controller.state.pressedKeyIDs.isEmpty && k.controller.state.previewKeyID == nil)
        #expect(k.controller.nextDeadline == nil)
        k.now += 0.05
        k.up(at: pa, id: 2)
        #expect(k.doc.text == "")
    }

    @Test func panelEndsCursorMode() throws {
        // 😊 is held while space goes into cursor mode; lifting 😊 still opens the panel, which ends cursor mode.
        let k = try Harness("abc")
        let pEmoji = try k.down("😊", id: 1)
        k.now += 0.05
        try k.down("space", id: 2)
        k.wait(0.4)
        #expect(k.controller.state.cursorMode)
        k.up(at: pEmoji, id: 1)
        #expect(k.controller.state.panel == .emoji && !k.controller.state.cursorMode)
        #expect(k.controller.state.pressedKeyIDs.isEmpty && k.controller.nextDeadline == nil && k.doc.text == "abc")
    }

    @Test func emojiThenDoubleSpace() throws {
        let k = try Harness("ok")
        try k.tap("😊")
        k.controller.insertEmoji("😀")
        k.controller.closePanel()
        try k.tap("space")
        try k.tap("space")
        #expect(k.doc.text == "ok😀  ")
    }

    @Test func emojiCountsAsTyping() throws {
        // At a sentence start shift is on by itself. An emoji ends the sentence start; deleting it brings it back.
        let k = try Harness("Hi. ", autoCap: .sentences)
        try k.tap("😊")
        #expect(k.controller.state.shift == .once)
        let changes = k.changes
        k.controller.insertEmoji("😀")
        #expect(k.doc.text == "Hi. 😀" && k.controller.state.shift == .off && k.changes == changes + 1)
        k.controller.deleteFromPanel()
        #expect(k.doc.text == "Hi. " && k.controller.state.shift == .once && k.changes == changes + 2)

        // An emoji uses up a one-letter shift as a letter does (ruling M3-R6), and a quick shift tap after it is
        // a first tap, not caps lock.
        let shift = try Harness()
        try shift.tap("⇧")
        shift.controller.insertEmoji("👋")
        #expect(shift.controller.state.shift == .off)
        try shift.tap("⇧")
        #expect(shift.doc.text == "👋" && shift.controller.state.shift == .once)
    }

    @Test func hostNoticeOfAnEmojiKeepsShiftTappedOff() throws {
        // In an all-capitals field shift is on for every letter. After the panel's edits the user taps it off,
        // and iOS's late notice of those edits brings nothing new, so it stays off (ruling R34).
        let typed = try Harness(autoCap: .all)
        try typed.tap("😊")
        typed.controller.insertEmoji("😀")
        typed.controller.closePanel()
        try typed.tap("⇧")
        #expect(typed.controller.state.shift == .off)
        typed.controller.documentDidChange()
        #expect(typed.controller.state.shift == .off)

        let deleted = try Harness("ok👍", autoCap: .all)
        try deleted.tap("😊")
        deleted.controller.deleteFromPanel()
        deleted.controller.closePanel()
        try deleted.tap("⇧")
        #expect(deleted.doc.text == "ok" && deleted.controller.state.shift == .off)
        deleted.controller.documentDidChange()
        #expect(deleted.controller.state.shift == .off)
    }
}
