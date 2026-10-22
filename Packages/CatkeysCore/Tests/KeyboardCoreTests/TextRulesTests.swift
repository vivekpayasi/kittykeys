import Testing
import KeyboardCore

@Test func autoCap() {
    #expect(TextRules.shouldCapitalize(before: "", mode: .sentences))
    #expect(TextRules.shouldCapitalize(before: "ok. ", mode: .sentences))
    #expect(TextRules.shouldCapitalize(before: "ok?\n", mode: .sentences))
    #expect(!TextRules.shouldCapitalize(before: "ok ", mode: .sentences))
    #expect(TextRules.shouldCapitalize(before: "ok ", mode: .words) && !TextRules.shouldCapitalize(before: "ok", mode: .words))
    #expect(!TextRules.shouldCapitalize(before: "", mode: .none) && TextRules.shouldCapitalize(before: "a", mode: .all))
}
@Test func rulesTreatNilAsStartOfField() {
    #expect(TextRules.shouldCapitalize(before: nil, mode: .sentences))
    #expect(!TextRules.isDoubleSpaceCandidate(before: nil))
    #expect(TextRules.previousWordLength(before: nil) == 0)
    #expect(CursorMath.verticalMove(before: nil, after: nil, lines: -1) == 0)
}
@Test func doubleSpace() {
    #expect(TextRules.isDoubleSpaceCandidate(before: "hi "))
    #expect(TextRules.isDoubleSpaceCandidate(before: "route 66 "))
    #expect(!TextRules.isDoubleSpaceCandidate(before: "hi. ") && !TextRules.isDoubleSpaceCandidate(before: "hi  "))
}
@Test func wordLength() {
    #expect(TextRules.previousWordLength(before: "hello world") == 5)
    #expect(TextRules.previousWordLength(before: "hello world  ") == 7)
    #expect(TextRules.previousWordLength(before: "kya hua?!") == 2)
    #expect(TextRules.previousWordLength(before: "hi 👍🏽") == 1)
}
@Test func verticalMoves() {
    #expect(CursorMath.verticalMove(before: "abcdef\nxy", after: "z", lines: -1) == -7)   // to column 2 of "abcdef"
    #expect(CursorMath.verticalMove(before: "ab\nwxyz", after: "", lines: -1) == -5)      // clamps to end of "ab"
    #expect(CursorMath.verticalMove(before: "ab", after: "c\nlonger", lines: 1) == 4)     // over "c", "\n", then to column 2 of "longer"
    #expect(CursorMath.verticalMove(before: "one long wrapped line", after: "", lines: -1) == 0)
}
@Test func utf16OffsetCountsWholeEmoji() {
    #expect(TextOffsets.utf16Offset(graphemes: -1, before: "hi 👍🏽", after: nil) == -4)
    #expect(TextOffsets.utf16Offset(graphemes: 2, before: nil, after: "🇮🇳a") == 5)
}

// Edge cases the rules above leave open; each pins the behaviour chosen.

@Test func sentenceCapsAfterAnyWhitespaceRun() {
    #expect(TextRules.shouldCapitalize(before: "ok!  ", mode: .sentences))
    #expect(TextRules.shouldCapitalize(before: "  ", mode: .sentences))   // nothing typed yet but spaces
    #expect(!TextRules.shouldCapitalize(before: "ok.", mode: .sentences))
}

@Test func sentenceEndersComeFromUnicode() {
    #expect(TextRules.shouldCapitalize(before: "ठीक है। ", mode: .sentences) == true)
}

@Test func wordDeleteKeepsContractionsWhole() {
    #expect(TextRules.previousWordLength(before: "don't") == 5)
    #expect(TextRules.previousWordLength(before: "it’s ") == 5)
    #expect(TextRules.previousWordLength(before: "kya hua?!") == 2)
    #expect(TextRules.previousWordLength(before: "'quoted") == 6)   // the leading apostrophe is not inside a word
    #expect(TextRules.previousWordLength(before: "dogs'") == 5)     // a trailing apostrophe stays with its word
    #expect(TextRules.previousWordLength(before: "''") == 2)        // apostrophes with no word before them are punctuation
}

@Test func trailingRunStopsAtWhitespace() {
    #expect(TextRules.trailingRunLength(before: "kya kr rha ") == 0)   // "h" already gone: "rha" is a different word
    #expect(TextRules.trailingRunLength(before: "hell") == 4)
    // An apostrophe right after a letter stays with its word, even with nothing after it yet (R20).
    #expect(TextRules.trailingRunLength(before: "don'") == 4)
    #expect(TextRules.trailingRunLength(before: "don't") == 5)
    #expect(TextRules.trailingRunLength(before: "hi?!") == 2)
    #expect(TextRules.trailingRunLength(before: nil) == 0)
    #expect(TextRules.trailingRunLength(before: "") == 0)
    #expect(TextRules.trailingRunLength(before: "I am ") == 0)
    #expect(TextRules.trailingRunLength(before: "hi 👍🏽") == 1)
}

@Test func verticalMovesSeveralLinesStopAtTheLastLineBreak() {
    // "ab\nlonger\nxyz|": up 2 crosses "xyz", "\n", "longer", "\n", then column 3 clamps to the end of "ab".
    #expect(CursorMath.verticalMove(before: "ab\nlonger\nxyz", after: "", lines: -2) == -11)
    // Only one line break above, so up 5 goes up 1.
    #expect(CursorMath.verticalMove(before: "abc\nxy", after: "", lines: -5) == -4)
    // "x|y\nmid\nlast": down 2 crosses "y", "\n", "mid", "\n", then column 1 of "last".
    #expect(CursorMath.verticalMove(before: "x", after: "y\nmid\nlast", lines: 2) == 7)
    #expect(CursorMath.verticalMove(before: "ab\ncd", after: "ef\ngh", lines: 0) == 0)
}

@Test func utf16OffsetCountsUnknownTextAsOneUnitPerGrapheme() {
    // The proxy may know less text than the move needs; graphemes past the known text count 1 unit each.
    #expect(TextOffsets.utf16Offset(graphemes: -3, before: "👍🏽", after: nil) == -6)
    #expect(TextOffsets.utf16Offset(graphemes: 2, before: nil, after: nil) == 2)
}

@Test @MainActor func fakeDocumentEditsAtTheCursor() {
    let doc = FakeTextDocument("hi 👍🏽", cursor: 2)
    #expect(doc.textBefore == "hi" && doc.textAfter == " 👍🏽")
    doc.insert("ya")
    #expect(doc.text == "hiya 👍🏽" && doc.cursor == 4)
    doc.moveCursor(by: 9)
    #expect(doc.cursor == 6 && doc.textAfter == nil)   // nil like iOS when nothing is on that side
    doc.deleteBackward(count: 1)
    #expect(doc.text == "hiya " && doc.cursor == 5)
    doc.moveCursor(by: -9)
    #expect(doc.cursor == 0 && doc.textBefore == nil)
    doc.deleteBackward(count: 3)
    #expect(doc.text == "hiya " && doc.cursor == 0)
    doc.moveCursor(by: 2)
    doc.deleteBackward(count: 9)
    #expect(doc.text == "ya " && doc.cursor == 0)
    #expect(FakeTextDocument("abc").cursor == 3)
    let empty = FakeTextDocument("")
    #expect(empty.textBefore == nil && empty.textAfter == nil)
}
