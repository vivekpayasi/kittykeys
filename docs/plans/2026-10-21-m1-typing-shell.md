# Milestone 1: Typing Shell Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** a working catkeys keyboard with every typing feature from milestone 1 in `docs/design.md`, plus the container app. It's checked on the simulator first, then measured on the user's iPhone 16 for speed and memory.

**Architecture:** a local Swift package, `Packages/CatkeysCore`, has two library targets.

- `KeyboardCore` holds all logic and builds on macOS, so `swift test` runs it on the Mac. It contains:
  - layout data and its loader
  - key geometry and hit-testing
  - the touch state machine
  - the text rules
  - the controller that applies everything to a text-document protocol
  - settings
- `KeyboardUI` is UIKit only: a single custom view that draws keys with layers and forwards raw touches to the controller.

The keyboard extension and the container app both link these targets. The app also hosts the same view in a preview screen, used for simulator screenshots. XcodeGen generates the Xcode project.

**Tech Stack:** Swift 6 language mode on Xcode 27.1, iOS 26.0 deployment target, UIKit for the keyboard, SwiftUI for the container app, Swift Testing (`import Testing`), XcodeGen. No third-party dependencies in M1.

**Spec:** `docs/design.md`. Read sections 3-5, 9, 10 and 12 before starting any task.

## Global Constraints

- **Deployment target:** iOS 26.0 for both targets. The package platforms are `.iOS(.v26)` and `.macOS(.v26)`.
- **No network code at all:** no `URLSession` and no sockets. Anything typed must never leave the phone.
- **No private data:** never read `../private`. Test text is invented or comes from public word lists.
- **No language baked into code:** key labels, outputs and long-press options live only in JSON layout files under `Packages/CatkeysCore/Sources/KeyboardCore/Layouts/`.
- **Pinned timings:**
  - Long-press delay: `0.3` s, adjustable in settings.
  - Hold space for cursor mode: `0.33` s.
  - Backspace switches to whole words after `1.5` s of holding.
- **Builder's timings,** which this plan pins:
  - Backspace repeat: first repeat after `0.4` s, then every `0.07` s for characters and every `0.2` s for words.
  - Shift double-tap window: `0.3` s.
  - Double-space window: `0.5` s.
  - Cursor step: `9` pt per character. Above `300` pt/s, each step moves `3` characters.
  - Cursor vertical step: `30` pt per line.
  - Backspace swipe: `20` pt to the left.
  - Long-press option cell width: `36` pt.
- **Keys:**
  - The key is chosen by where the finger landed. That landing point is the one recorded for every tap.
  - Character keys and space are typed on lift.
  - Shift, page-switch keys and backspace act on touch-down.
- **Fast typing (rollover):** when a new finger lands while an earlier key or space is still held and hasn't fired its long-press, the earlier key is typed immediately and its timers are cancelled.
- **Autocorrect:** catkeys never replaces or alters a word it didn't just type.
- **Build output:** goes only to `build/` (gitignored), using `-derivedDataPath build/DerivedData`. The simulator is the existing iOS 26.4 runtime with the "iPhone 17" device; don't download other runtimes. Instruments traces go to `/Volumes/Extreme SSD/catkeys-traces/` and are deleted after reading.
- **Commits:** work on branch `m1-typing-shell`, one commit per task. It merges to `main` at the end of the milestone (Task 12). The commit message has no attribution lines.

## Review Focus

These five situations are what's most likely to hurt a user while no task's main tests cover them. Each has a pinned test in the task named.

1. **Emoji and other multi-part characters before the cursor** (👍🏽, 🇮🇳). Backspace, word delete and cursor moves treat each one as one character. iOS's `adjustTextPosition` gets the matching UTF-16 offset. Tested in Task 4 (`utf16OffsetCountsWholeEmoji`) and Task 7 (`wordDeleteRemovesEmojiAsOneUnit`).
2. **Missing or empty text before the cursor** (`nil` at the start of a field, or a short window iOS hands over). Auto-capitals, the double-space full stop and word delete behave as if at the start of a field, with no crash. Tested in Task 4 (`rulesTreatNilAsStartOfField`).
3. **A touch cancelled by the system mid-press,** such as an incoming call or a notification pull-down. It leaves no stuck highlight, types nothing and leaves no live timers. Tested in Task 5 (`cancelClearsEverything`) and Task 6 (`cancelDuringCursorModeEndsIt`). A lift that never arrives is ended by `cancelAll()` (ruling R33), tested in `cancelAllEndsCursorMode`, `cancelAllStopsHeldBackspace` and `keyboardWillAppearEndsAStuckCursorMode`.
4. **The page changes while another finger is still down,** for example holding a letter and tapping `123`. The held key types its original character, and nothing reads an out-of-range key. Tested in Task 5 (`framesReplacedMidTouchUseOriginalKey`).
5. **Many fingers or a palm at once, or a touch starting in the suggestion row.** No crash, nothing typed from the suggestion row, and commits in finger-down order. Tested in Task 5 (`elevenTouchesCommitInOrder`, `suggestionRowTouchesIgnored`).

---

## File Structure

```
project.yml                                   XcodeGen spec (Task 1)
Config/Base.xcconfig                          shared settings; includes Local.xcconfig if present (Task 1)
Config/Local.xcconfig.example                 DEVELOPMENT_TEAM, CATKEYS_BUNDLE_PREFIX template (Task 1)
App/                                          container app (SwiftUI)
  CatkeysApp.swift, ContentView.swift         entry + tab layout (Task 1, Task 11)
  SetupView.swift, SettingsView.swift, TryItView.swift   (Task 11)
  KeyboardPreviewView.swift                   hosts KeyboardView for screenshots (Task 9)
  Info.plist, Catkeys.entitlements
Keyboard/                                     keyboard extension (UIKit)
  KeyboardViewController.swift                UIInputViewController glue (Task 10)
  ProxyTextDocument.swift                     TextDocument over UITextDocumentProxy (Task 10)
  DeviceFeedback.swift                        haptics + click sound (Task 10)
  Info.plist, CatkeysKeyboard.entitlements
Packages/CatkeysCore/
  Package.swift
  Sources/KeyboardCore/
    Layout/KeySpec.swift, Layout/LayoutPage.swift, Layout/LayoutSet.swift   (Task 2)
    Layouts/index.json, latin-qwerty.json, symbols-1.json, symbols-2.json   (Task 2)
    Geometry/KeyboardMetrics.swift, Geometry/KeyFrame.swift, Geometry/KeyboardGeometry.swift (Task 3)
    Text/TextDocument.swift, Text/TextRules.swift, Text/CursorMath.swift, Text/TextOffsets.swift (Task 4)
    Touch/TouchEvent.swift, Touch/TouchTiming.swift, Touch/TouchProcessor.swift (Tasks 5-6)
    Controller/FieldTraits.swift, Controller/KeyboardState.swift, Controller/KeyboardController.swift, Controller/FeedbackSink.swift (Task 7)
    Settings/KeyboardSettings.swift, Settings/SettingsStore.swift (Task 8)
  Sources/KeyboardUI/                         all files wrapped in #if canImport(UIKit)
    KeyboardTheme.swift, KeyLayer.swift, PopupLayers.swift, KeyboardView.swift (Task 9)
  Tests/KeyboardCoreTests/
    FakeTextDocument.swift, RecordingFeedback.swift (Task 4, Task 7)
    LayoutTests.swift, GeometryTests.swift, TextRulesTests.swift, TouchTapTests.swift,
    TouchHoldTests.swift, ControllerTests.swift, SettingsTests.swift
scripts/sim-screenshots.sh                    build + launch preview + capture PNGs (Task 9)
```

---

### Task 1: Project scaffold

**Files:**
- Create: `project.yml`, `Config/Base.xcconfig`, `Config/Local.xcconfig.example`, `App/CatkeysApp.swift`, `App/ContentView.swift`, `App/Info.plist`, `App/Catkeys.entitlements`, `Keyboard/KeyboardViewController.swift`, `Keyboard/Info.plist`, `Keyboard/CatkeysKeyboard.entitlements`, `Packages/CatkeysCore/Package.swift`, `Packages/CatkeysCore/Sources/KeyboardCore/KeyboardCore.swift`, `Packages/CatkeysCore/Sources/KeyboardUI/KeyboardUI.swift`, `Packages/CatkeysCore/Tests/KeyboardCoreTests/SmokeTests.swift`
- Modify: `.gitignore`: add `Catkeys.xcodeproj/`, because the project is generated.

**Interfaces:**
- Produces:
  - Build settings `CATKEYS_BUNDLE_PREFIX` (default `com.example`) and `CATKEYS_APP_GROUP = group.$(CATKEYS_BUNDLE_PREFIX).catkeys`.
  - An Info.plist key `CatkeysAppGroup = $(CATKEYS_APP_GROUP)` in both targets.
  - Package products `KeyboardCore` and `KeyboardUI`.
  - Bundle IDs `$(CATKEYS_BUNDLE_PREFIX).catkeys` (app) and `$(CATKEYS_BUNDLE_PREFIX).catkeys.keyboard` (extension).

- [x] **Step 1: Create the branch.** Run `git checkout -b m1-typing-shell`.
- [x] **Step 2: Write the package and a smoke test.**
  - `Package.swift`: tools version 6.2 and package name `CatkeysCore`.
    - Targets: `KeyboardCore` with `resources: [.copy("Layouts")]`, `KeyboardUI` depending on `KeyboardCore`, and test target `KeyboardCoreTests`.
    - Create an empty `Layouts/` folder with a `.gitkeep`.
  - `SmokeTests.swift`:
    ```swift
    import Testing
    @testable import KeyboardCore
    @Test func packageBuilds() { #expect(KeyboardCore.version == "0.1.0") }
    ```
  - Add `public enum KeyboardCore { public static let version = "0.1.0" }`.
- [x] **Step 3: Run the tests.** Run `cd Packages/CatkeysCore && swift test`. Expected: 1 test passed.
- [x] **Step 4: Write the project.**
  - `Base.xcconfig`:
    - Set `CATKEYS_BUNDLE_PREFIX`, `CATKEYS_APP_GROUP`, an empty `DEVELOPMENT_TEAM`, `CODE_SIGN_STYLE = Automatic`, `SWIFT_VERSION = 6.0` and `IPHONEOS_DEPLOYMENT_TARGET = 26.0`.
    - End with `#include? "Local.xcconfig"`.
  - `project.yml`:
    - App target `Catkeys` (application) embeds `CatkeysKeyboard` (app-extension). Both depend on the `KeyboardCore` and `KeyboardUI` products from package path `Packages/CatkeysCore`.
    - Both entitlements files list `$(CATKEYS_APP_GROUP)` under `com.apple.security.application-groups`.
  - Keyboard `Info.plist`, under `NSExtension`:
    - `NSExtensionPointIdentifier = com.apple.keyboard-service`
    - `NSExtensionPrincipalClass = $(PRODUCT_MODULE_NAME).KeyboardViewController`
    - `NSExtensionAttributes`: `IsASCIICapable = true` (ruling R7: catkeys types ASCII), `PrefersRightToLeft = false`, `PrimaryLanguage = en-IN`, `RequestsOpenAccess = true`
  - `KeyboardViewController`: a `UIInputViewController` subclass that shows a 292 pt tall empty view for now.
  - The app: a single `Text("catkeys")` view.
- [x] **Step 5: Generate and build for the simulator.**
  - Run `xcodegen generate && xcodebuild -project Catkeys.xcodeproj -scheme Catkeys -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.4' -derivedDataPath build/DerivedData build`.
  - Expected: `** BUILD SUCCEEDED **`.
- [x] **Step 6: Commit.** `git add -A && git commit -m "Scaffold app, keyboard extension and core package"`

### Task 2: Layout model and layout files

**Files:**
- Create: `Sources/KeyboardCore/Layout/KeySpec.swift`, `Layout/LayoutPage.swift`, `Layout/LayoutSet.swift`, `Layouts/index.json`, `Layouts/latin-qwerty.json`, `Layouts/symbols-1.json`, `Layouts/symbols-2.json`
- Test: `Tests/KeyboardCoreTests/LayoutTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public enum PageRef: Equatable, Sendable { case letters; case named(String) }
  public enum KeyAction: Equatable, Sendable, Decodable {   // JSON string: "character" (default) | "shift" | "backspace" |
      case character, shift, backspace, space, returnKey, emoji, globe   // "space" | "return" | "emoji" | "globe" |
      case switchPage(PageRef)                                           // "page:letters" | "page:<id>"
  }
  public struct KeySpec: Equatable, Sendable, Decodable {
      public var label: String; public var output: String          // output defaults to label
      public var longPress: [String]                                // defaults to []
      public var width: Double                                      // in key units; defaults to 1; 0 = fill remaining space
      public var action: KeyAction
      public var cornerHint: String? { get }                        // first longPress option, only for .character keys on letter rows
  }
  public enum RowKind: String, Sendable, Decodable { case number, keys }
  public struct LayoutRow: Equatable, Sendable, Decodable { public var kind: RowKind; public var keys: [KeySpec] }
  public enum BottomVariant: String, Sendable, CaseIterable { case standard = "default", email, url }
  public struct LayoutPage: Equatable, Sendable, Decodable {
      public var id: String; public var rows: [LayoutRow]           // rows above the bottom row; rows[0] is the number row
      public func bottomRow(_ variant: BottomVariant) -> [KeySpec]  // falls back to .standard
  }
  public struct LayoutSet: Sendable {
      public static func bundled() throws -> LayoutSet              // reads Layouts/index.json via Bundle.module
      public var lettersPageID: String
      public func page(_ id: String) -> LayoutPage?
      public func resolve(_ ref: PageRef) -> String                 // .letters -> lettersPageID
  }
  ```
- JSON shape: `{"id": "...", "rows": [{"kind": "number", "keys": [...]}, ...], "bottom": {"default": [...], "email": [...], "url": [...]}}`. Here `index.json` is `{"letters": "latin-qwerty", "pages": ["latin-qwerty", "symbols-1", "symbols-2"]}`.
- Unknown JSON keys are ignored.
- **Bottom rows** (the email and URL rows put `@`, or `/` and `.com`, where the comma sits; shown as label:width, where width 0 fills the remaining space):
  - **Default:** `123`:1.5 (or `ABC`:1.5 on the symbols pages), `😊`:1, `,`:1, space:0, `.`:1, return:2. The `.` key's long-press options are `[".", "?", "!", "…", ":", "/"]`.
  - **Email:** `@` replaces `,`.
  - **URL:** `/` replaces `,`, and a `.com`:1.5 key (output `.com`) goes right of space.
- **Letters row 3:** shift 1.5, seven letters, backspace 1.5.
- **Symbols rows 1-3:** as in design §4.2. `1/2` and `2/2` are 1.5 wide.

- [x] **Step 1: Write the failing tests**
  ```swift
  @Test func lettersPageMatchesDesign() throws {
      let set = try LayoutSet.bundled()
      let p = try #require(set.page(set.lettersPageID))
      #expect(p.rows.map(\.kind) == [.number, .keys, .keys, .keys])
      #expect(p.rows[0].keys.map(\.label) == ["1","2","3","4","5","6","7","8","9","0"])
      #expect(p.rows[1].keys.map(\.label) == ["q","w","e","r","t","y","u","i","o","p"])
      #expect(p.rows[1].keys.map(\.cornerHint) == ["%","\\","|","=","[","]","<",">","{","}"])
      #expect(p.rows[2].keys.map(\.cornerHint) == ["@","#","₹","_","&","-","+","(",")"])
      #expect(p.rows[3].keys.map(\.cornerHint) == [nil,"*","\"","'",":",";","!","?",nil])
      #expect(p.rows[3].keys.first?.action == .shift && p.rows[3].keys.last?.action == .backspace)
      #expect(p.rows[2].keys[2].longPress == ["₹","$","€"])
      #expect(p.bottomRow(.standard).map(\.action) == [.switchPage(.named("symbols-1")), .emoji, .character, .space, .character, .returnKey])
      #expect(p.bottomRow(.standard)[4].longPress == [".","?","!","…",":","/"])
  }
  @Test func symbolsPagesMatchDesign() throws {
      let set = try LayoutSet.bundled()
      let s1 = try #require(set.page("symbols-1")), s2 = try #require(set.page("symbols-2"))
      #expect(s1.rows[1].keys.map(\.label) == ["@","#","₹","$","_","&","-","+","(",")"])
      #expect(s1.rows[2].keys.map(\.label) == ["*","\"","'",":",";","!","?","/","%","="])
      #expect(s1.rows[3].keys.map(\.label) == ["1/2","<",">","[","]","{","}","|","⌫"])
      #expect(s2.rows[1].keys.map(\.label) == ["~","`","\\","^","•","°","…","§","¶","©"])
      #expect(s2.rows[2].keys.map(\.label) == ["€","£","¥","¢","×","÷","√","π","∞","™"])
      #expect(s2.rows[3].keys.map(\.label) == ["2/2","®","✓","«","»","¿","¡","‰","⌫"])
      #expect(s1.rows[0] == set.page(set.lettersPageID)!.rows[0])
      #expect(s1.bottomRow(.standard).first?.action == .switchPage(.letters))
      #expect(s1.rows[1].keys.allSatisfy { $0.cornerHint == nil })
  }
  @Test func fieldVariants() throws {
      let p = try #require(try LayoutSet.bundled().page("latin-qwerty"))
      #expect(p.bottomRow(.email).map(\.output).contains("@"))
      #expect(p.bottomRow(.url).map(\.output).contains("/") && p.bottomRow(.url).map(\.output).contains(".com"))
  }
  @Test func decodingDefaults() throws {
      let k = try JSONDecoder().decode(KeySpec.self, from: Data(#"{"label":"a","extra":1}"#.utf8))
      #expect(k.output == "a" && k.width == 1 && k.longPress.isEmpty && k.action == .character)
  }
  ```
- [x] **Step 2: Run them to verify they fail.** Run `swift test --filter LayoutTests`. Expected: compile errors for the missing types.
- [x] **Step 3: Implement the types and write the four JSON files.** `cornerHint` returns `longPress.first` only when `action == .character` and the key isn't on the number row. Pass this into the row's keys when decoding, or compute it in `LayoutPage`. Either works, but the test above must hold.
- [x] **Step 4: Run the tests.** Run `swift test --filter LayoutTests`. Expected: PASS.
- [x] **Step 5: Commit.** `git commit -am "Add layout model and letters/symbols layout files"`, after `git add` of the new files.

### Task 3: Geometry and hit-testing

**Files:**
- Create: `Sources/KeyboardCore/Geometry/KeyboardMetrics.swift`, `Geometry/KeyFrame.swift`, `Geometry/KeyboardGeometry.swift`
- Test: `Tests/KeyboardCoreTests/GeometryTests.swift`

**Interfaces:**
- Consumes: `LayoutPage` and `KeySpec` from Task 2.
- Produces:
  ```swift
  public struct Point: Equatable, Sendable { public var x: Double; public var y: Double }
  public struct Rect: Equatable, Sendable { public var x, y, width, height: Double; /* minX, maxX, minY, maxY, midX, midY, contains(_:), distance(to: Point) -> Double (0 inside) */ }
  public struct KeyboardMetrics: Sendable {
      public var suggestionRowHeight = 44.0, numberRowHeight = 36.0, keyHeight = 42.0
      public var rowGap = 10.0, keyGap = 6.0, sidePadding = 3.0, bottomPadding = 4.0
      public static let standard = KeyboardMetrics()
      public func totalHeight(rowCount: Int) -> Double   // suggestion + number row + (rowCount-1) key rows + gaps + bottom padding
  }
  public struct KeyFrame: Equatable, Sendable, Identifiable { public var id: Int; public var key: KeySpec; public var rect: Rect; public var row: Int }
  public enum KeyboardGeometry {
      public static func frames(page: LayoutPage, bottom: [KeySpec], width: Double, metrics: KeyboardMetrics) -> [KeyFrame]
      public static func hitTest(_ p: Point, in frames: [KeyFrame], metrics: KeyboardMetrics) -> KeyFrame?
  }
  ```
- Rules:
  - One key unit is `(width - 2*sidePadding - 9*keyGap) / 10`. A key of width `w` is `unit*w + keyGap*(w-1)` wide.
  - Width-0 keys share whatever space is left in their row.
  - Every row is centred.
  - `id` is the key's index in the returned array, in row-major order.
  - `hitTest` returns nil when `p.y < metrics.suggestionRowHeight`. Otherwise it picks the row first, then the key, so gaps and edges go to the nearest key in that row (ruling R9). A pure nearest-rectangle rule would send edge-gutter taps to the row above.
    - **Row:** each row owns the vertical band from the midpoint of the gap above it down to the midpoint of the gap below it, and a midpoint belongs to the row above. The top row starts at `suggestionRowHeight`, and the bottom row extends down without limit.
    - **Key:** within the row, the key with the smallest horizontal distance wins. Ties go to the earlier key.
  - `frames` returns `[]` when the unit width is ≤ 0, and `Rect.contains` uses plain comparisons, never ranges.

- [x] **Step 1: Write the failing tests**
  ```swift
  // width 390 → unit = (390 - 6 - 54) / 10 = 33
  @Test func rowsLayOutEdgeToEdge() throws {
      let page = try #require(try LayoutSet.bundled().page("latin-qwerty"))
      let f = KeyboardGeometry.frames(page: page, bottom: page.bottomRow(.standard), width: 390, metrics: .standard)
      let q = try #require(f.first { $0.key.label == "q" }), p = try #require(f.first { $0.key.label == "p" })
      #expect(abs(q.rect.minX - 3) < 0.01 && abs(p.rect.maxX - 387) < 0.01 && abs(q.rect.width - 33) < 0.01)
      #expect(f.first { $0.key.label == "1" }!.rect.height == 36 && q.rect.height == 42)
      #expect(abs(f.first { $0.key.label == "a" }!.rect.minX - (390 - (9*33 + 8*6)) / 2) < 0.01)
      let space = try #require(f.first { $0.key.action == .space })
      let ret = try #require(f.first { $0.key.action == .returnKey })
      #expect(abs(ret.rect.maxX - 387) < 0.01 && space.rect.width > 100)
      #expect(KeyboardMetrics.standard.totalHeight(rowCount: 5) == 292)
  }
  @Test func gapsGoToNearestKey() throws { /* point midway+1pt toward g in the f|g gap → "g"; x=0 on row 2 → "a"; below the bottom row → nearest bottom key */ }
  @Test func suggestionRowIsNotAKey() throws { /* hitTest(Point(x: 200, y: 20)) == nil */ }
  ```
- [x] **Step 2: Run them to verify they fail.** Run `swift test --filter GeometryTests`. Expected: compile errors.
- [x] **Step 3: Implement the geometry types and functions.** Rows run top to bottom: number row, letter rows, bottom row. The number row starts at `y = suggestionRowHeight`.
- [x] **Step 4: Run the tests.** Run `swift test --filter GeometryTests`. Expected: PASS.
- [x] **Step 5: Commit.** "Add key geometry and nearest-key hit-testing"

### Task 4: Text document protocol and text rules

**Files:**
- Create: `Sources/KeyboardCore/Text/TextDocument.swift`, `Text/TextRules.swift`, `Text/CursorMath.swift`, `Text/TextOffsets.swift`, `Tests/KeyboardCoreTests/FakeTextDocument.swift`
- Test: `Tests/KeyboardCoreTests/TextRulesTests.swift`

**Interfaces:**
- Produces:
  ```swift
  @MainActor public protocol TextDocument: AnyObject {   // ruling R12
      var textBefore: String? { get }      // nil = unknown/start of field
      var textAfter: String? { get }
      func insert(_ text: String)
      func deleteBackward(count: Int)      // count in grapheme clusters
      func moveCursor(by graphemes: Int)   // negative = left
  }
  public enum AutoCapMode: Sendable { case none, words, sentences, all }
  public enum TextRules {
      public static func shouldCapitalize(before: String?, mode: AutoCapMode) -> Bool
      public static func isDoubleSpaceCandidate(before: String?) -> Bool   // true iff before ends with letter/digit + exactly one space
      public static func previousWordLength(before: String?) -> Int        // graphemes: trailing whitespace + one run of word chars, or one run of other non-space chars
  }
  public enum CursorMath {
      public static func verticalMove(before: String?, after: String?, lines: Int) -> Int   // grapheme offset; 0 if no hard line break that way
  }
  public enum TextOffsets {
      public static func utf16Offset(graphemes: Int, before: String?, after: String?) -> Int  // UTF-16 length of the graphemes crossed
  }
  ```
- `FakeTextDocument` (test target only): `init(_ text: String, cursor: Int? = nil)`, with `text: String` and `cursor: Int` counted in graphemes. It implements the protocol over a `[Character]`, is `@MainActor`, and returns nil for an empty side, as iOS does (ruling R10).
- Rules:
  - **Sentences:** capitalise when the text before is nil or empty, ends in a newline, or ends in a sentence terminal (Unicode `isSentenceTerminal`, ruling R11) followed by whitespace. Apostrophes between letters count as part of a word for word delete.
  - **Words:** capitalise when the text before is nil, empty or ends in whitespace.
  - **All:** always capitalise. **None:** never.
  - **Vertical moves:** the cursor keeps its column, meaning the number of graphemes since the last `\n`. When moving to a shorter line, it clamps to that line's end.

- [x] **Step 1: Write the failing tests**
  ```swift
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
  ```
- [x] **Step 2: Run them to verify they fail.** Run `swift test --filter TextRulesTests`. Expected: compile errors.
- [x] **Step 3: Implement the rules and `FakeTextDocument`.** Iterate over `Character`s, never over UTF-16 units, except inside `TextOffsets`.
- [x] **Step 4: Run the tests.** Run `swift test --filter TextRulesTests`. Expected: PASS.
- [x] **Step 5: Commit.** "Add text document protocol and text rules"

### Task 5: Touch processor (taps, fast typing, long-press)

**Files:**
- Create: `Sources/KeyboardCore/Touch/TouchEvent.swift`, `Touch/TouchTiming.swift`, `Touch/TouchProcessor.swift`
- Test: `Tests/KeyboardCoreTests/TouchTapTests.swift`

**Interfaces:**
- Consumes: `KeyFrame`, `KeyboardGeometry.hitTest` and `KeyboardMetrics` from Task 3.
- Produces:
  ```swift
  public typealias TouchID = Int
  public enum TouchEvent: Equatable, Sendable {
      case keyDown(KeyFrame)                                   // highlight + feedback
      case keyUp(KeyFrame)                                     // clear highlight/preview
      case activate(KeyFrame, landing: Point)                  // perform the key's action
      case alternatesShown(KeyFrame, options: [String], selected: Int, originX: Double)
      case alternateSelected(KeyFrame, selected: Int)
      case activateAlternate(KeyFrame, text: String)
      case deleteBackward(word: Bool)                          // Task 6: held backspace
      case deleteRestOfWord                                    // Task 6: backspace swipe (ruling R18)
      case cursorModeBegan, cursorModeEnded                    // Task 6
      case cursorMoved(characters: Int)                        // Task 6
      case cursorMovedLines(Int)                               // Task 6
  }
  public struct TouchTiming: Sendable {
      public var longPress = 0.3, cursorHold = 0.33
      public var backspaceFirstRepeat = 0.4, backspaceRepeat = 0.07, backspaceWordsAfter = 1.5, backspaceWordRepeat = 0.2
      public var cursorStep = 9.0, cursorFastSpeed = 300.0, cursorFastMultiplier = 3, cursorLineStep = 30.0
      public var backspaceSwipe = 20.0, alternateWidth = 36.0
  }
  public final class TouchProcessor {
      public init(timing: TouchTiming = .init(), metrics: KeyboardMetrics = .standard)
      public var timing: TouchTiming
      public var frames: [KeyFrame]          // replaced on page/width change; touches in flight keep their original KeyFrame
      public var keyboardWidth: Double
      public func touchDown(_ id: TouchID, at p: Point, time: Double) -> [TouchEvent]
      public func touchMoved(_ id: TouchID, to p: Point, time: Double) -> [TouchEvent]
      public func touchUp(_ id: TouchID, at p: Point, time: Double) -> [TouchEvent]
      public func touchCancelled(_ id: TouchID) -> [TouchEvent]
      public func advance(to time: Double) -> [TouchEvent]     // fires due timers in time order
      public var nextDeadline: Double? { get }                 // nil when no timer is pending
      public var isShowingAlternates: Bool { get }             // ruling R29
      public func cancelAll() -> [TouchEvent]                  // ruling R33: cursorModeEnded if needed, keyUp per touch, no touches or timers left
  }
  ```
- Rules:
  - **Act on touch-down:** shift and `switchPage` keys emit `[.keyDown, .activate]` on touch-down, and backspace's touch-down is handled in Task 6.
  - **Act on lift:** character, space, return, emoji and globe keys emit `.activate` on lift. The `landing` point is the touch-down point.
  - **Long-press options:** they show only for `.character` keys with a non-empty `longPress` list.
    - **Layout (ruling R13):** options are emitted in display order, left to right.
      - If they fit from `key.rect.minX`, they run left to right from there, with the default option leftmost and `selected = 0`.
      - Otherwise they run right to left: the default option takes the cell ending at `key.rect.maxX`, `originX = max(key.rect.maxX - n*alternateWidth, 0)`, the options are reversed, and `selected = n-1`.
    - **Selection:** the cell under the finger, `clamp(Int((x - originX) / alternateWidth), 0, n-1)`. If the cell width is ≤ 0 or the value isn't finite, the default option is used (ruling R17).
    - **One popup at a time (ruling R16):** while any touch is choosing an option, new touches get no long-press.
  - **Fast typing (rollover):** a new touch-down while an earlier touch holds a character key, space or return (ruling R14) that hasn't fired its long-press yet first emits `.activate` for the earlier key, then cancels its timers. That earlier touch is then spent, so its lift emits only `.keyUp`.
  - **Reused touch id (ruling R15):** a touch-down that reuses a still-down id ends the stale touch as if it had lifted.

- [x] **Step 1: Write the failing tests.** Use frames from `KeyboardGeometry.frames` at width 390 and a helper `center(_ label: String) -> Point`.
  ```swift
  @Test func tapCommitsOnLiftAtLandingPoint()   // down a, move to s, up → [.activate(a, landing: center("a")), .keyUp(a)]
  @Test func rolloverCommitsEarlierKeyFirst()   // down a t0, down s t0.05 → [.activate(a,…), .keyDown(s)]; up a → [.keyUp(a)]; up s → [.activate(s,…), .keyUp(s)]
  @Test func longPressShowsAndPicksAlternate()  // down d t0; advance(0.29) → []; advance(0.3) → [.alternatesShown(d, ["₹","$","€"], selected: 0, originX: d.rect.minX)];
                                                 // move +40pt → [.alternateSelected(d, selected: 1)]; up → [.activateAlternate(d, text: "$"), .keyUp(d)]
  @Test func holdWithoutOptionsTypesKey()       // down "5", advance(1.0) → []; up → activate("5")
  @Test func rolloverCancelsLongPress()         // down d t0, down f t0.1 → activate(d); advance(0.5) → []
  @Test func shiftAndPageKeysActOnDown()        // down shift → [.keyDown(shift), .activate(shift,…)]; up → [.keyUp(shift)]
  @Test func longPressDelayIsConfigurable()     // timing.longPress = 0.5; advance(0.3) → []; advance(0.5) → alternatesShown
  @Test func cancelClearsEverything()           // down d, cancel → [.keyUp(d)]; nextDeadline == nil; advance(1) → []
  @Test func suggestionRowTouchesIgnored()      // down at (200, 20) → []; up → []
  @Test func elevenTouchesCommitInOrder()       // 11 downs on distinct keys 10ms apart → activates in down order, no crash
  @Test func framesReplacedMidTouchUseOriginalKey() // down a; frames = symbols-1 frames; up → activate(original a frame)
  ```
- [x] **Step 2: Run them to verify they fail.** Run `swift test --filter TouchTapTests`. Expected: compile errors.
- [x] **Step 3: Implement `TouchProcessor`.** Keep per-touch state in a dictionary keyed by `TouchID`, plus an array that preserves down order. Timers are a stored deadline per touch, and `advance` fires every deadline ≤ time in deadline order. The touch path must not allocate beyond the event array.
- [x] **Step 4: Run the tests.** Run `swift test --filter TouchTapTests`. Expected: PASS.
- [x] **Step 5: Commit.** "Add touch processor with rollover and long-press"

### Task 6: Touch processor (backspace and space-bar cursor)

**Files:**
- Modify: `Sources/KeyboardCore/Touch/TouchProcessor.swift`
- Test: `Tests/KeyboardCoreTests/TouchHoldTests.swift`

**Interfaces:**
- Consumes and produces: the `TouchEvent` cases already declared in Task 5.
- **Backspace:**
  - Touch-down emits `[.keyDown, .deleteBackward(word: false)]`.
  - Repeats start at `0.4` s and come every `0.07` s.
  - From `1.5` s after touch-down, each repeat is `.deleteBackward(word: true)`, every `0.2` s.
  - The first horizontal move of ≥ `20` pt to the left emits one `.deleteRestOfWord` (ruling R18) and stops the repeats. Nothing more happens until lift.
  - When cursor mode begins, a deleting backspace stops (ruling R19).
- **Space:**
  - Holding for `0.33` s with no rollover emits `.cursorModeBegan`.
  - In cursor mode, the horizontal movement since the last emitted step is turned into `.cursorMoved(characters: n)`, where n is `Int(dx / 9)` (rounding towards zero). If the speed over the last move is above `300` pt/s, n is multiplied by `3`.
  - Vertical movement works the same way with `30` pt per line, giving `.cursorMovedLines(n)`. Down is positive.
  - Lifting in cursor mode gives `[.cursorModeEnded, .keyUp(space)]` and types no space.
  - While cursor mode is on, other touches are ignored and return `[]`.

- [x] **Step 1: Write the failing tests**
  ```swift
  @Test func backspaceRepeatsThenDeletesWords() // down t0 → [.keyDown(b), .deleteBackward(word: false)]; advance(0.4) → 1 char delete; advance(0.47) → 1 more;
                                                 // advance(1.5) → contains .deleteBackward(word: true); advance(1.7) → one word delete; up → [.keyUp(b)], nextDeadline nil
  @Test func backspaceSwipeDeletesOneWord()     // down; move −25pt → [.deleteBackward(word: true)]; move −60pt → []; advance(2.0) → []
  @Test func spaceTapTypesSpace()               // down t0, up t0.2 → [.activate(space,…), .keyUp(space)]
  @Test func spaceHoldEntersCursorMode()        // advance(0.33) → [.cursorModeBegan]; move +9 slowly (t+0.1) → [.cursorMoved(characters: 1)];
                                                 // move +30 in 0.05s → [.cursorMoved(characters: 9)]; move −30pt vertically → [.cursorMovedLines(-1)];
                                                 // up → [.cursorModeEnded, .keyUp(space)]
  @Test func otherTouchesIgnoredInCursorMode()  // in cursor mode, down on "a" → []
  @Test func spaceRolloverBeforeHold()          // down space t0, down a t0.1 → [.activate(space,…), .keyDown(a)]; advance(0.5) → []
  @Test func cancelDuringCursorModeEndsIt()     // cursor mode, cancel → [.cursorModeEnded, .keyUp(space)]; nextDeadline nil
  ```
- [x] **Step 2: Run them to verify they fail.** Run `swift test --filter TouchHoldTests`. Expected: FAIL.
- [x] **Step 3: Implement backspace and cursor mode in `TouchProcessor`.**
- [x] **Step 4: Run all package tests.** Run `swift test`. Expected: all PASS.
- [x] **Step 5: Commit.** "Add backspace repeat/swipe and space-bar cursor mode"

### Task 7: Keyboard controller

**Files:**
- Create: `Sources/KeyboardCore/Controller/FieldTraits.swift`, `Controller/KeyboardState.swift`, `Controller/FeedbackSink.swift`, `Controller/KeyboardController.swift`, `Tests/KeyboardCoreTests/RecordingFeedback.swift`
- Test: `Tests/KeyboardCoreTests/ControllerTests.swift`

**Interfaces:**
- Consumes:
  - `LayoutSet`, `BottomVariant` and `PageRef` (Task 2)
  - `KeyboardGeometry` and `KeyboardMetrics` (Task 3)
  - `TextDocument`, `TextRules`, `CursorMath` and `AutoCapMode` (Task 4)
  - `TouchProcessor` and `TouchEvent` (Tasks 5-6)
  - `KeyboardSettings` (Task 8 defines it, so implement Task 8 first, or move its struct here)
- Produces:
  ```swift
  public enum FieldKind: Sendable { case text, email, url, number }
  public enum ReturnKeyKind: Sendable { case standard, go, search, join, next, route, send, done, emergencyCall, `continue` }
  public struct FieldTraits: Equatable, Sendable { public var kind: FieldKind = .text; public var autoCap: AutoCapMode = .sentences; public var returnKey: ReturnKeyKind = .standard; public init(...) }
  public enum ShiftState: Sendable { case off, once, locked }
  public struct AlternatesPopup: Equatable, Sendable { public var keyID: Int; public var options: [String]; public var selected: Int; public var originX: Double }
  public struct KeyboardState: Equatable, Sendable {
      public var pageID: String; public var shift: ShiftState; public var returnKey: ReturnKeyKind
      public var pressedKeyIDs: Set<Int>; public var previewKeyID: Int?     // preview only for .character keys and only if settings.keyPopup
      public var alternates: AlternatesPopup?; public var cursorMode: Bool
  }
  public protocol FeedbackSink: AnyObject { func keyDown(); func cursorTick() }
  @MainActor public final class KeyboardController {
      public init(document: any TextDocument, layouts: LayoutSet, settings: KeyboardSettings, feedback: any FeedbackSink, metrics: KeyboardMetrics = .standard)
      public var settings: KeyboardSettings                    // didSet updates processor timing
      public var needsGlobeKey: Bool                           // didSet inserts/removes the globe key spec from Layouts/index.json "globeKey" (ruling R8) before 😊
      public var onGlobe: (() -> Void)?                        // called on globe activate
      public var onChange: (() -> Void)?                       // called after any state/frames change
      public private(set) var state: KeyboardState
      public private(set) var frames: [KeyFrame]
      public var height: Double { get }
      public func setWidth(_ width: Double)
      public func fieldDidChange(_ traits: FieldTraits)       // re-picks variant/page/return key only when the traits change (ruling R23) and then
                                                               // re-evaluates auto-shift; same traits re-evaluate only if textBefore changed (ruling R34)
      public func documentDidChange()                          // re-evaluates auto-shift only if textBefore differs from the last value seen (ruling R34)
      public func keyboardWillAppear(_ traits: FieldTraits)    // ruling R28: ends every touch (R33), resets page/variant from traits, clears shift history, re-evaluates auto-shift
      public func touchDown(_ id: TouchID, at: Point, time: Double)
      public func touchMoved(_ id: TouchID, to: Point, time: Double)
      public func touchUp(_ id: TouchID, at: Point, time: Double)
      public func touchCancelled(_ id: TouchID)
      public func cancelAllTouches()                           // ruling R33: ends every touch, types nothing; clears highlights, preview, popup, cursor mode; one onChange
      public func key(at p: Point) -> KeyFrame?                // hit-test only, for the keyDown signpost's bottomRow metadata
      public func advance(to time: Double)
      public var nextDeadline: Double? { get }
  }
  ```
- **What each event does:**
  - `keyDown`: calls `feedback.keyDown()` and adds the key to `pressedKeyIDs`.
  - `activate(.character)`: inserts the output, uppercased when shift is `once` or `locked` and the output is a single grapheme (ruling R25). A `once` shift is then used up.
  - `activate(.space)`: if `settings.doubleSpacePeriod` is on, the previous key was also space within `0.5` s, the text before the cursor is unchanged since that space (ruling R26), and `isDoubleSpaceCandidate(before:)` holds, it deletes 1 and inserts `". "`. Otherwise it inserts `" "`.
  - `activate(.returnKey)`: inserts `"\n"`.
  - `activate(.shift)`:
    - From off, it goes to once.
    - Ruling R24 overrides the next two rules: every shift tap records its time, and a tap within `0.3` s of the previous shift tap goes to locked from any state except locked.
    - From once, it goes to locked if the press came within `0.3` s of the shift tap that set it, and otherwise to off.
    - From locked, it goes to off.
  - `activate(.switchPage)`: changes `pageID` and recomputes the frames.
  - `activateAlternate`: inserts the text unchanged and uses up a `once` shift.
  - `deleteBackward(word: false)`: deletes 1 character. `deleteBackward(word: true)` deletes `previousWordLength`, or 1 if that is 0.
  - `deleteRestOfWord`: deletes `TextRules.trailingRunLength(before:)`, and nothing if that is 0 (ruling R18).
  - Popups and frame ids:
    - `alternatesShown` renders `options` exactly as given, in display order.
    - The popup is shown exactly while `TouchProcessor.isShowingAlternates` is true, checked after each batch of events (ruling R29).
    - Replacing frames cancels pending long-presses of held character keys (ruling R30).
    - Never index the current `frames` by an event's `KeyFrame.id` after a page change: pressed-key highlighting matches by id only within the current page.
    - Two fingers on one key keep it highlighted until both lift.
  - `cursorMoved(n)`: calls `moveCursor(by: n)` and `feedback.cursorTick()` |n| times.
  - `cursorMovedLines(n)`: moves by `CursorMath.verticalMove` and calls `cursorTick()` once.
  - `.emoji`: does nothing in M1.
  - After every text change, auto-shift is re-evaluated. Shift becomes `once` when `shouldCapitalize` holds and shift isn't `locked`.
- **Field kinds:**
  - `.email` selects the `.email` bottom row and `.url` the `.url` one.
  - `.number` switches to page `symbols-1` when the field is focused.
  - Every other kind selects letters with the `.standard` bottom row.

- [x] **Step 1: Write the failing tests.** They use `FakeTextDocument`, `RecordingFeedback` (which counts calls) and a `tap(_ label:)` helper (touchDown/touchUp at the key centre, 0.1 s apart, with time advancing).
  ```swift
  @Test func typesLetters()                     // fieldDidChange(autoCap: .none); tap h, i → doc.text == "hi"
  @Test func autoCapitalisesSentences()          // autoCap .sentences, empty doc: tap h, i → "Hi"; then ". " typed via "." + space → next tap "o" gives "Hi. O"
  @Test func shiftOnceAndCapsLock()             // autoCap .none: shift, a, b → "Ab"; shift, shift(within 0.3s), a, b → "AbAB"; shift → off
  @Test func doubleSpaceFullStop()              // "hi" + space + space (0.2s apart) → "hi. "; with settings.doubleSpacePeriod = false → "hi  "
  @Test func doubleSpaceNeedsLetterBefore()     // "hi." + space + space → "hi.  "
  @Test func longPressTypesSymbolAndUsesShift() // autoCap .none: shift; hold d 0.4s, release → "₹", shift == .off
  @Test func pagesSwitch()                      // tap 123 → pageID "symbols-1"; tap 1/2 → "symbols-2"; tap 2/2 → "symbols-1"; tap ABC → "latin-qwerty"
  @Test func fieldVariantsAndReturnKey()        // .email → frames contain "@"; .url → contain "/" and ".com"; .number → pageID "symbols-1"; returnKey .send → state.returnKey == .send; tap return → "\n"
  @Test func wordDeleteRemovesEmojiAsOneUnit()  // doc "hi 👍🏽", backspace swipe → doc.text == "hi "
  @Test func cursorModeMovesAndTicks()          // doc "abc|def": hold space, move +18 slowly → cursor +2, feedback.cursorTicks == 2, state.cursorMode true; lift → cursorMode false, text unchanged
  @Test func globeKeyAppearsWhenNeeded()        // needsGlobeKey = true → bottom row actions start [.switchPage, .globe, .emoji, …]; tap 🌐 → onGlobe called
  @Test func previewOnlyForCharacterKeys()      // keyDown on "a" → previewKeyID == a.id; on shift → nil; settings.keyPopup = false → nil
  @Test func keyDownGivesFeedback()             // one tap → feedback.keyDowns == 1
  ```
- [x] **Step 2: Run them to verify they fail.** Run `swift test --filter ControllerTests`. Expected: FAIL.
- [x] **Step 3: Implement `KeyboardController`.** `height` comes from `metrics.totalHeight(rowCount:)` for the current page.
- [x] **Step 4: Run all package tests.** Run `swift test`. Expected: all PASS.
- [x] **Step 5: Commit.** "Add keyboard controller"

### Task 8: Settings

Implement this before Task 7, or alongside it, because the controller takes `KeyboardSettings`.

**Files:**
- Create: `Sources/KeyboardCore/Settings/KeyboardSettings.swift`, `Settings/SettingsStore.swift`
- Test: `Tests/KeyboardCoreTests/SettingsTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public struct KeyboardSettings: Codable, Equatable, Sendable {
      public var haptics = true, sound = false, keyPopup = true, doubleSpacePeriod = true
      public var longPressDelay = 0.3          // clamped to 0.2...0.6 on load
      public init()
  }
  public struct SettingsStore {
      public init(defaults: UserDefaults)
      public static func appGroup(id: String?) -> SettingsStore?   // nil if id is nil, the App Group container is unavailable (ruling R22), or UserDefaults(suiteName:) fails
      public func load() -> KeyboardSettings                        // missing or corrupt data → defaults
      public func save(_ s: KeyboardSettings)
      public var lastKeyboardOpen: Date? { get nonmutating set }    // heartbeat written by the keyboard, read by the app
  }
  ```
- Settings are stored as JSON under the key `catkeys.settings`. The heartbeat is stored under `catkeys.keyboardOpenedAt`.

- [x] **Step 1: Write the failing tests.** They cover:
  - defaults equal the design values (`haptics` true, `sound` false, `keyPopup` true, `doubleSpacePeriod` true, `longPressDelay` 0.3)
  - a save-then-load round trip
  - garbage `Data` gives the defaults
  - `longPressDelay` 5 loads as 0.6
  - the heartbeat round trip

  Each test uses `UserDefaults(suiteName: "catkeys-test-\(UUID())")!`.
- [x] **Step 2: Run them to verify they fail.** Run `swift test --filter SettingsTests`. Expected: FAIL.
- [x] **Step 3: Implement settings and the store.**
- [x] **Step 4: Run the tests.** Run `swift test --filter SettingsTests`. Expected: PASS.
- [x] **Step 5: Commit.** "Add settings model and store"

### Task 9: Keyboard view and simulator screenshots

**Files:**
- Create: `Sources/KeyboardUI/KeyboardTheme.swift`, `KeyLayer.swift`, `PopupLayers.swift`, `KeyboardView.swift`, `App/KeyboardPreviewView.swift`, `scripts/sim-screenshots.sh`
- Modify: `App/ContentView.swift`, so the launch argument `-catkeysPreview` shows `KeyboardPreviewView` full screen.

**Interfaces:**
- Consumes: `KeyboardController`, `KeyboardState`, `KeyFrame`, `ReturnKeyKind` and `FeedbackSink` (Task 7).
- Produces:
  ```swift
  @MainActor public final class KeyboardView: UIView {
      public init(controller: KeyboardController)
      public var theme: KeyboardTheme                     // .light / .dark; set by the host from trait collection or keyboardAppearance
      public func render()                                // apply controller.state/frames to layers; called from controller.onChange
  }
  public struct KeyboardTheme: Sendable { public static let light: KeyboardTheme; public static let dark: KeyboardTheme; /* background, key, specialKey, label, hint, popup colours */ }
  public enum ReturnKeyLabel { public static func text(for kind: ReturnKeyKind) -> String }  // "return", "Go", "Search", "Join", "Next", "Route", "Send", "Done", "Emergency", "Continue"
  ```
- `KeyboardView` behaviour:
  - **Touches:** `isMultipleTouchEnabled = true`. It forwards `touchesBegan`, `Moved`, `Ended` and `Cancelled` to the controller using `ObjectIdentifier(touch).hashValue`, `touch.location(in: self)` and `touch.timestamp`.
  - **Timers:** while `controller.nextDeadline != nil`, a `CADisplayLink` calls `controller.advance(to: ProcessInfo.processInfo.systemUptime)`. It's invalidated when there's no deadline.
  - **Order:** before forwarding any touch event at time t, call `controller.advance(to: t)`, so a lift just after a deadline sees that deadline fired first.
  - **Stale touches (ruling R33):** it tracks the touch ids it forwarded and not yet ended. `didMoveToWindow` calls `controller.cancelAllTouches()` when the view leaves a window and when it enters one, before the timer restarts. `touchesBegan` first cancels any tracked id missing from `event.allTouches`.
  - **Layers:** one `KeyLayer` (a `CALayer` with label and corner-hint `CATextLayer`s) per frame. Implicit animations are disabled with `CATransaction.setDisableActions(true)`.
  - **Re-rendering:** `render()` rebuilds layers only when the frames change. Otherwise it updates only the pressed and preview states, which keeps per-key work small.
  - **Key preview:** a magnified balloon above the key, clamped inside the view's bounds. The number row's balloon covers the suggestion row.
  - **Long-press popup:** drawn at `originX` with `alternateWidth` (36 pt) cells, and the selected cell is highlighted.
  - **Cursor mode:** all labels and corner hints are hidden.
  - **Suggestion row:** an empty bar 44 pt tall.
  - **Labels:** shift shows ⇧ when off, ⇧ highlighted when once, and ⇪ when locked. Letters show uppercase when shift is on. The return key shows `ReturnKeyLabel.text`.
- **Preview host:** `KeyboardPreviewView` (`UIViewRepresentable`) builds a `KeyboardController` over a `UITextView`-backed `TextDocument` and pins the view to the bottom.
  - Launch arguments: `-catkeysPreviewPage <id>` opens that page, and `-catkeysPreviewHold <label>` runs touchDown at that key's centre and then `advance(to: now + 0.5)` to show its long-press popup.
  - Launch argument `-catkeysPreviewCursor` holds space until cursor mode begins.
- `scripts/sim-screenshots.sh`:
  1. Runs `xcodegen generate` and the Task 1 `xcodebuild` command.
  2. Boots "iPhone 17" (OS 26.4), then `xcrun simctl install` and `xcrun simctl launch`es the app with each argument set.
  3. Saves with `xcrun simctl io booted screenshot build/screenshots/<name>.png`, in both `xcrun simctl ui booted appearance light` and `dark`.
  4. Names: `letters`, `symbols-1`, `symbols-2`, `hold-d`, `hold-period`, `cursor`, each with a `-light` or `-dark` suffix.

- [x] **Step 1: Implement the theme, layers and `KeyboardView`.**
- [x] **Step 2: Implement `KeyboardPreviewView` and the launch arguments.**
- [x] **Step 3: Run `scripts/sim-screenshots.sh`.** Expected: 12 PNGs in `build/screenshots/`.
- [x] **Step 4: Compare the screenshots with design §4.1-4.2 and the approved mockups.**
  - Number row on top; corner hints on the letter keys, matching Task 2; comma and emoji keys.
  - `hold-d` shows `₹ $ €` with ₹ selected, and `hold-period` shows `. ? ! … : /`.
  - In cursor mode the labels are blank.
  - Dark mode is readable.
  - Fix anything off, and attach the PNG paths to the task report.
- [x] **Step 5: Commit.** "Add keyboard view, preview host and screenshot script"

### Task 10: Keyboard extension

**Files:**
- Modify: `Keyboard/KeyboardViewController.swift`
- Create: `Keyboard/ProxyTextDocument.swift`, `Keyboard/DeviceFeedback.swift`

**Interfaces:**
- Consumes:
  - `KeyboardController`, `FieldTraits`, `FieldKind`, `ReturnKeyKind`, `AutoCapMode` and `FeedbackSink` (Task 7)
  - `KeyboardView` and `KeyboardTheme` (Task 9)
  - `SettingsStore` (Task 8)
  - `TextOffsets` (Task 4)
- **`ProxyTextDocument`** wraps `UITextDocumentProxy`:
  - `deleteBackward(count:)` calls `proxy.deleteBackward()` count times.
  - `moveCursor(by:)` calls `proxy.adjustTextPosition(byCharacterOffset: TextOffsets.utf16Offset(graphemes:before:after:))`.
  - It maps `keyboardType` (`.emailAddress` to email; `.URL` and `.webSearch` to url; `.numberPad`, `.decimalPad`, `.asciiCapableNumberPad` and `.numbersAndPunctuation` to number; anything else to text), `autocapitalizationType` and `returnKeyType` into `FieldTraits`.
- **`DeviceFeedback: FeedbackSink`:**
  - `keyDown()`: fires a prepared `UIImpactFeedbackGenerator(style: .light)` when `settings.haptics && hasFullAccess`, and calls `UIDevice.current.playInputClick()` when `settings.sound` is on.
  - `cursorTick()`: uses a `UISelectionFeedbackGenerator` under the same haptics rule.
  - The input view adopts `UIInputViewAudioFeedback` with `enableInputClicksWhenVisible = true`.
- **`KeyboardViewController`:**
  - **`viewDidLoad`:** loads `LayoutSet.bundled()` and settings from `SettingsStore.appGroup(id: Bundle.main.object(forInfoDictionaryKey: "CatkeysAppGroup") as? String)`, falling back to `KeyboardSettings()`. It builds the controller and the `KeyboardView`, sets a height constraint from `controller.height`, wires `onGlobe` to `advanceToNextInputMode()`, and sets `needsGlobeKey = needsInputModeSwitchKey`.
  - **`viewWillAppear`:** reloads settings, writes the `lastKeyboardOpen = Date()` heartbeat, and calls `controller.keyboardWillAppear(traits)` (ruling R28).
  - **`viewDidAppear`:** turns off `delaysTouchesBegan` on every gesture recognizer in `view.window?.gestureRecognizers`. This is design §9's bottom-row workaround.
  - **`textDidChange`:** calls `fieldDidChange` and `documentDidChange`. The theme is dark when `proxy.keyboardAppearance == .dark` or the trait collection is dark.
  - **`didReceiveMemoryWarning`:** no-op for M1.
- **Signposts:** `OSSignposter(subsystem: "catkeys", category: "perf")`. `KeyboardView` doesn't import the extension: it reports through hooks (`onTouchDown`, `measure`, `onFirstKeysDrawn`) that the extension sets.
  - An interval `startup` from `viewDidLoad` to the first `render()` that has frames.
  - An event `keyDown` on every touch-down, with the latency `systemUptime - touch.timestamp` in ms and `bottomRow` (1 if the touched key is on the bottom row, else 0) as metadata. Never the position or the key.
  - An interval `touch` around each batch of touches `KeyboardView` hands to the controller (the touch processor and the controller's whole response), and an interval `render` around each `render()`.
  - An interval `insert` around every `TextDocument.insert` call in `ProxyTextDocument`.

- [x] **Step 1: Implement `ProxyTextDocument` and `DeviceFeedback`.**
- [x] **Step 2: Implement `KeyboardViewController` with the signposts.**
- [x] **Step 3: Build for the simulator.** Use the Task 1 `xcodebuild` command. Expected: `** BUILD SUCCEEDED **` with no Swift 6 concurrency errors.
- [x] **Step 4: Best effort, try the real extension in the simulator.** Install the app and add the keyboard with `xcrun simctl spawn booted defaults write com.apple.Preferences KeyboardsCurrentAndNext -array <bundle id>` or the Settings app. If it shows up, screenshot it inside the app's Try-it field. If it doesn't, say so in the report and leave it to the device check in Task 12.
- [x] **Step 5: Commit.** "Add keyboard extension controller, proxy document and feedback"

### Task 11: Container app

**Files:**
- Create: `App/SetupView.swift`, `App/SettingsView.swift`, `App/TryItView.swift`
- Modify: `App/ContentView.swift` (a `TabView`: Setup, Settings, Try it; keep the `-catkeysPreview` route)

**Interfaces:**
- Consumes: `SettingsStore` and `KeyboardSettings` (Task 8).
- **Setup:**
  - Numbered steps: Settings → General → Keyboard → Keyboards → Add New Keyboard → catkeys; then tap catkeys → Allow Full Access.
  - The Full Access paragraph reads, exactly: "Full Access lets catkeys use haptics and read the settings you choose here. catkeys never connects to the internet: nothing you type leaves your phone."
  - A status line, "Keyboard last opened: <relative time>", from `lastKeyboardOpen`. It shows "Settings can't be shared on this install: the App Group isn't available" when `SettingsStore.appGroup` returns nil, and "Not opened yet, or Full Access is off" when there's no heartbeat (ruling R38: without Full Access the keyboard can't write it).
- **Settings:**
  - Toggles: Haptics, Key click sound, Key popup, Double-space full stop.
  - A long-press delay slider from 0.2 to 0.6 s in 0.05 steps, showing its value in seconds.
  - Every change saves through `SettingsStore`.
- **Try it:** a multi-line `TextField`, plus a note that the catkeys keyboard must be picked with 🌐.

- [x] **Step 1: Implement the three views.**
- [x] **Step 2: Build and screenshot each tab on the simulator,** light and dark, into `build/screenshots/app-*.png`. Expected: the text matches the spec above.
- [x] **Step 3: Commit.** "Add container app setup, settings and try-it screens"

### Task 11a: SideStore install path (ruling R39)

The user installs catkeys through SideStore, as with their other sideloaded app, not from Xcode. SideStore re-signs an unsigned IPA with the user's free Apple ID and refreshes it daily. It also rewrites bundle IDs and renames App Groups. This task makes catkeys work under that path.

**Files:**
- Create: `Packages/CatkeysCore/Sources/KeyboardCore/Settings/AppGroupResolver.swift`, `Tests/KeyboardCoreTests/AppGroupResolverTests.swift`, `scripts/build-ipa.sh`
- Modify: `Packages/CatkeysCore/Sources/KeyboardCore/Settings/SettingsStore.swift`, plus the callers of `appGroup(id:)` in `Keyboard/` and `App/` if their call changes

**Interfaces:**
- Produces:
  ```swift
  public enum AppGroupResolver {
      /// The App Group usable in this process, or nil: the canonical id if its container exists,
      /// otherwise the first group from this bundle's embedded.mobileprovision whose container exists.
      public static func resolve(canonical: String?, bundle: Bundle = .main,
                                 containerExists: (String) -> Bool = { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) != nil }) -> String?
      /// `com.apple.security.application-groups` from a raw .mobileprovision (CMS envelope around an XML plist);
      /// groups containing the canonical id's last component come first.
      public static func groups(fromProvisioningProfile data: Data, canonical: String?) -> [String]
  }
  ```
  `SettingsStore.appGroup(id:)` uses `AppGroupResolver.resolve(canonical: id)`. The rest of its contract is unchanged, including nil when nothing resolves.
- `scripts/build-ipa.sh` writes `build/catkeys.ipa`:
  1. Builds a Release archive for `generic/platform=iOS` with `CODE_SIGNING_ALLOWED=NO`.
  2. Writes entitlements files with the build settings expanded. `$(CATKEYS_APP_GROUP)` must become the real group id, read via `xcodebuild -showBuildSettings`.
  3. Ad-hoc signs the appex first, then the app, each with its entitlements (`codesign -f -s - --entitlements …`).
  4. Zips `Payload/`.
  5. Verifies with `codesign -d --entitlements :-` that both bundles carry the App Group.
- The parsing approach follows the user's own Sahaja app (`Shared/AppGroup.swift`): scan for `<?xml` … `</plist>`, then `PropertyListSerialization`.

- [ ] **Step 1: Write failing tests.**
  - Parsing a synthetic profile blob (junk bytes + XML plist + junk) returns its groups, with the renamed group carrying the canonical name ordered first.
  - Garbage gives `[]`.
  - `resolve` with an injected `containerExists`:
    - prefers the canonical id;
    - falls back to the profile group;
    - returns nil when nothing exists.
- [ ] **Step 2: Implement it, and switch `SettingsStore.appGroup(id:)` over.** Run `swift test`. Expected: all pass.
- [ ] **Step 3: Write `scripts/build-ipa.sh` and run it with `Config/Local.xcconfig`** (`CATKEYS_BUNDLE_PREFIX = com.vivek`). Expected: `build/catkeys.ipa`, with both bundles' entitlements showing `group.com.vivek.catkeys`.
- [ ] **Step 4: Commit.** "SideStore path: resolve renamed App Group; IPA build script"

### Task 12: Device check, measurements and milestone close (with the user)

**Files:**
- Create: `Config/Local.xcconfig` (gitignored; the user's team and bundle prefix)
- Modify: this plan's **Progress** section, and `docs/design.md` §10 if the targets change

- [ ] **Step 1: The user prepares signing.**
  1. Add their Apple ID in Xcode → Settings → Accounts.
  2. Choose a unique `CATKEYS_BUNDLE_PREFIX`, for example `io.github.<handle>`.
  3. Turn on Developer Mode on the iPhone.

  Then Claude writes `Config/Local.xcconfig` with `DEVELOPMENT_TEAM` and `CATKEYS_BUNDLE_PREFIX`. If signing fails because the Apple ID can't provision App Groups, it also sets `CATKEYS_APP_ENTITLEMENTS =` and `CATKEYS_KB_ENTITLEMENTS =` (ruling R36, see `Local.xcconfig.example`) and records that: the app then says the App Group isn't available and the keyboard uses the default settings.
- [ ] **Step 2: Build and install on the device.** Use the Release configuration (ruling R35): Debug inflates time and memory and would mislead the speed and memory checks. Automatic development signing still applies. The simulator screenshot script stays on Debug.
  1. Run `xcodebuild -project Catkeys.xcodeproj -scheme Catkeys -configuration Release -destination 'platform=iOS,name=V’s iPhone' -derivedDataPath build/DerivedData -allowProvisioningUpdates build`.
  2. Install with `xcrun devicectl device install app --device <id> build/DerivedData/Build/Products/Release-iphoneos/Catkeys.app`.

  Expected: the app installs.
- [ ] **Step 3: The user enables the keyboard and Full Access.** Then check the App Group: the app's Setup tab shows "Keyboard last opened: just now" after the keyboard opens. Record whether it works. If it doesn't, file a follow-up task for design §9's in-keyboard settings fallback.
- [ ] **Step 4: Measure the Release build from Step 2.** Use `xcrun xctrace record --device <id> --template 'Logging' --attach CatkeysKeyboard --output "/Volumes/Extreme SSD/catkeys-traces/m1-signposts.trace"` while the user types for 30 s.
  - Read the `keyDown` latency (split by its `bottomRow` metadata), `touch`, `render`, `insert` and `startup` from the trace.
  - Record a second trace with the `Allocations` template and read `phys_footprint`.
  - Compare against design §10: insert ≤ 2 ms, startup ≤ 50 ms, UI memory ≤ 22 MB. Also check whether bottom-row `keyDown` latency is higher than other rows.
- [ ] **Step 5: The user's feel check and the device checks.** All on the Release build from Step 2. Go through both lists and record the user's verdicts and the readings.
  - **Feel:**
    - Fast typing doesn't drop letters.
    - Long-press symbols work.
    - Cursor drag works.
    - Backspace hold and swipe work.
    - Shift and caps lock work.
    - Double-space works.
    - Email and URL fields show their variants.
    - Dark mode works.
    - Haptics work.
    - Typing fast at a sentence start gives one capital, not two (ruling R34).
    - Shift tapped off at a sentence start stays off (ruling R34).
    - Holding space and releasing without moving types no space; the user judges whether that's right.
    - Cursor up and down across typed line breaks works in Notes and in WhatsApp.
    - Backspace deletes 👍🏽 and 🇮🇳 whole in a real app, and a fast cursor drag across emoji lands between characters.
    - Landscape lays out and types correctly.
  - **Device checks:**
    - Memory over about 30 open/close cycles of the keyboard stays flat (Allocations `phys_footprint`), and switching away with 🌐 frees the old keyboard.
    - Hiding the keyboard while holding backspace: when it comes back nothing more is deleted and keys work (ruling R33).
    - The App Group works with Full Access on (Setup shows "Keyboard last opened: …"); with it off, Setup shows "Not opened yet, or Full Access is off".
    - Haptics and the key click work with Full Access. If haptics are silent, try `UIImpactFeedbackGenerator(style:view:)`.
    - Bottom-row `keyDown` latency against the other rows, from the trace's `bottomRow` metadata.
    - The layouts load: the `Bundle.module` resource bundle is in the device build (a missing bundle crashes the keyboard).
    - Colour seams above and below the keyboard: the user judges.

  Optionally, film catkeys against Apple's keyboard in 240 fps slow motion.
- [ ] **Step 6: Wrap up.**
  1. Write the numbers and verdicts into **Progress** below, and delete the traces.
  2. Clear `build/DerivedData`.
  3. Commit "Record M1 measurements".
  4. Merge into `main` with `git checkout main && git merge --no-ff m1-typing-shell`.

---

## Progress

- 2026-10-21: plan written. Building on the simulator starts on branch `m1-typing-shell`, with the device check (Task 12) once the user is back.
- 2026-10-21: Tasks 1-11 done on the simulator, each reviewed clean (commit ranges are base..last):
  - Task 1, scaffold: `23274c0..4a7c8e2`
  - Task 2, layouts: `e112ac0..cc2feb6`
  - Task 3, geometry: `cc2feb6..e7e501e`
  - Task 4, text rules: `ed19085..fb46c0b`
  - Task 5, touch taps and long-press: `e76ddb6..bb69d35`
  - Task 6, backspace and cursor mode: `698d4f9..dd497e8`
  - Task 8, settings (run before Task 7, ruling R1): `e5d23d1..160b24a`
  - Task 7, controller: `71a9a1d..1919868`
  - Task 9, keyboard view: `08ddb66..731582d`
  - Task 10, keyboard extension: `731582d..bfbb8cb`
  - Task 11, container app: `bfbb8cb..0654db6`
- 2026-10-21: final whole-branch review of `23274c0..0654db6` (ruling R32, before Task 12): ready to merge with fixes; 0 Critical, 5 Important, 4 Minor. None of the deferred minors must be fixed before merge.
- 2026-10-21: final-review fix wave, `0654db6..95809e5` plus this plan update: stale-touch reset (R33), host-notice guard (R34), `touch`/`render` signposts and `bottomRow` metadata, Release builds for the device (R35), switchable entitlements (R36), iPhone only and clamped corner radii (R37), Setup status copy (R38). A scoped re-review follows.
- Task 12 (device check, measurements, merge to `main`): pending with the user.

## Rulings

Decisions made while building, one line each. The ledger behind them is local and not in git.

- R1: Task 8 (settings) runs before Task 7 (controller), which consumes `KeyboardSettings`.
- R2: The smoke test uses `CoreInfo.version`; a type named like its module (`KeyboardCore`) breaks module-qualified lookup.
- R3: `KeySpec.cornerHint` is `longPress.first` for character keys; the view draws hints only on rows between the number row and the bottom row.
- R4: Backspace switches to word deletes at exactly 1.5 s after touch-down, then every 0.2 s; character repeats stop before 1.5 s.
- R5: The preview host uses a no-op `FeedbackSink`.
- R6: Process only (how the build was run); no effect on the product.
- R7: The keyboard's Info.plist sets `IsASCIICapable = true`.
- R8: The globe key's spec lives in `Layouts/index.json` as `globeKey`; the controller inserts it.
- R9: Hit-testing picks the row first (bands split at the gap midpoints), then the horizontally nearest key in it.
- R10: `FakeTextDocument` returns nil for an empty side, as iOS does.
- R11: Sentence ends use Unicode `isSentenceTerminal`, not a hard-coded `. ! ?`.
- R12: `TextDocument` (and the fake) is `@MainActor`.
- R13: Long-press options come in display order: rightward from the key's left edge when they fit, else leftward with the default in the cell ending at the key's right edge; the selection is the cell under the finger.
- R14: Return joins rollover.
- R15: A touch-down reusing a still-down `TouchID` ends the stale touch as a lift would.
- R16: One long-press popup at a time: while one shows, other touches get no long-press.
- R17: Alternate-index maths falls back to the default option on non-finite values or a zero cell width.
- R18: The backspace swipe emits `.deleteRestOfWord`, applied with `TextRules.trailingRunLength(before:)`; held-backspace word repeats keep `.deleteBackward(word: true)`.
- R19: Cursor mode starting stops a deleting backspace.
- R20: An apostrophe after a word character joins the word run, even at the end of the text.
- R21: Settings tests use an absolute-path suite in a per-run temporary directory, leaving nothing in `~/Library/Preferences`.
- R22: `SettingsStore.appGroup(id:)` also requires the App Group's container to exist.
- R23: `fieldDidChange` re-picks the page and bottom row only when the traits change.
- R24 (amended): Every shift tap records its time; a tap within 0.3 s of the previous shift tap locks caps from any state but locked; anything else typed or deleted clears that history.
- R25: Shift changes only single-grapheme outputs; ".com" is typed as written.
- R26: Double space also needs the text before the cursor unchanged since the first space.
- R27: Replacing the frames sends a finger choosing an option back to pressed, so it types its own key.
- R28: `keyboardWillAppear(_:)` resets the page and bottom row from the traits, clears the shift history and re-checks capitals; the extension calls it from `viewWillAppear`.
- R29: The controller shows the popup exactly while the processor's `isShowingAlternates` is true.
- R30: Replacing the frames also cancels pending long-presses of held character keys.
- R31: Accept the dark popup colour #828286 and 21 pt single-character labels on the bottom row.
- R32: The final whole-branch review runs before Task 12, which needs the user and the phone.
- R33: Stale touches are reset: `TouchProcessor.cancelAll()`, `KeyboardController.cancelAllTouches()` (also at the start of `keyboardWillAppear`), called by `KeyboardView` on window changes and for touches UIKit no longer reports.
- R34: `documentDidChange` and same-traits `fieldDidChange` do nothing when the text before the cursor is what the controller last saw.
- R35: Device installs and measurements use `-configuration Release`; Debug only for the simulator script.
- R36: Entitlements come from `CATKEYS_APP_ENTITLEMENTS` and `CATKEYS_KB_ENTITLEMENTS`, so `Local.xcconfig` can build without the App Group.
- R37: iPhone only (`TARGETED_DEVICE_FAMILY = 1`), and rounded-rect radii are clamped to min(r, w/2, h/2).
- R38: With no heartbeat, the Setup status reads "Not opened yet, or Full Access is off".

## Deferred to later milestones

Minor review findings left for later, one line each.

- **Task 1:** the `appintentsmetadataprocessor` "Metadata extraction skipped" warnings are toolchain noise; `swift test` builds into `Packages/CatkeysCore/.build` (gitignored), not `build/`.
- **Task 2:**
  - `LayoutSet.bundled()` doesn't check cross-file page refs; add a test that resolves them all.
  - A missing "default" bottom row decodes silently to `[]`.
  - The bottom rows are repeated in each page file with no test against drift.
  - Field-variant tests check that keys are present, not where.
  - No tests for decode failures (unknown action, empty `page:`).
- **Task 3:**
  - `totalHeight` assumes exactly one number row; `rowCount` ≤ 0 gives nonsense.
  - Force-unwraps in tests; variants and ties untested.
  - `KeySpec` accepts fractional widths in (0, 1), which can go negative at tiny units.
- **Task 4:**
  - The fake doesn't merge combining marks or modifiers on insert (needed for Indic scripts).
  - `.sentences` after whitespace containing a newline doesn't capitalise, and a closing quote or bracket after a terminal blocks the capital.
  - One word delete can cross several blank lines plus punctuation.
  - No goal column across repeated vertical moves.
  - Coverage gaps (CRLF, combining marks, `.words` with nil); "1️⃣" counts as a digit for double space.
  - `previousWordLength` builds an array on every word delete; walk back with `String.Index` instead.
  - The sentence-terminal check ignores a trailing variation selector ("‼️").
- **Task 5:**
  - R13's clamp branch and keys wider than 72 pt can leave the default cell away from the finger (unreachable on iPhone portrait).
  - M2: a suggestion-row tap while a letter is held must roll the letter over first.
- **Task 6:**
  - Move the repeat schedule, trackpad maths and popup layout onto phase structs before glide typing adds a phase.
  - `fireTimer`'s `default: break` silently absorbs unhandled phase/action pairs.
  - R20 isn't applied in the punctuation-run scan ("dogs'." → 2).
  - The `deleteRestOfWord` doc overclaims after a trailing "?" or emoji; reword it.
- **Task 7:**
  - `KeyboardState` and `AlternatesPopup` have no public inits.
  - "symbols-1" and ". " are Swift constants; move them to `index.json` with the second layout set.
  - A held emoji or globe key, or a choosing finger, between shift taps doesn't break the double-tap; no test for shift, backspace, shift.
- **Task 9:**
  - R3 is applied by row index rather than a row kind on `KeyFrame`.
  - The display link advances to `systemUptime`, so a lift delivered late within one frame of the long-press deadline can open the popup.
  - No display-link invalidation in `deinit`; the popup cell width is read from a default `TouchTiming()`; small quoting and `awk` SIGPIPE nits in the script; the view's rules can't be unit-tested in the UIKit target.
- **Task 10:** the `startup` interval stays open if the layouts fail to load; `onChange` chaining depends on order (documented); the traits mapping is untested; an empty `ClickingInputView` is kept per appearance (negligible).
- **Task 11:** VoiceOver reads "Long-press delay" twice; step numbers are decorative for VoiceOver; "just now" is hard-coded English; the status row is empty before `onAppear`; the `-catkeysTab` hook ships in release builds.
- **Final review, out of M1 scope:** no modifier-shift or slide-from-shift; 😊 does nothing until M3; no automatic return to letters after a symbol; no `enablesReturnKeyAutomatically`; no VoiceOver for the key grid; suggestion-row taps ignored; no accented letters; `ReturnKeyLabel` and ⇪ live in Swift; exact colours left to the device comparison.
