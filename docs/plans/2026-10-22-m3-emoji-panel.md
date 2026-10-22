# Milestone 3: Emoji Panel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** the 😊 key opens an emoji panel that matches design §7:

- the same height as the letters
- one scrolling list with Recent first
- a category tab bar with `ABC` and `⌫`
- hold an emoji to pick a skin tone

It is checked on the simulator and then on the user's iPhone, where memory is measured.

**Architecture:**

- **No third-party panel.** ISEmojiView has had no release since February 2023, so catkeys builds the lighter panel the design allows.
- **Emoji data:**
  - A dev-time script turns Emojibase data (MIT, current to Emoji 17) into a compact `emoji.json` bundled in `KeyboardCore`.
  - Pure logic in `KeyboardCore` loads it lazily, when the panel first opens, and keeps Recent and the per-emoji skin-tone choice.
- **Controller:** the existing `KeyboardController` gains a panel mode.
- **View:** `KeyboardUI` gets an `EmojiPanelView` built on a vertical `UICollectionView` with cell reuse, so only visible emoji are rendered.

**Tech Stack:** as in milestone 1. The data script is Python 3 standard library only.

**Spec:** `docs/design.md` §7, plus the approved mockup "Suggestion row and emoji panel" (its description is in design §7). Milestone 1's plan (`docs/plans/2026-10-21-m1-typing-shell.md`) has the conventions, rulings R1–R42 and the install path.

## Global Constraints

- All milestone 1 global constraints still apply. In particular:
  - no network code in the app or the keyboard
  - nothing from `../private`
  - builds only in `build/`
  - Swift 6 with zero warnings
  - commit messages without attribution lines
- **Bundle ids are frozen** (R39). The device install uses `scripts/build-ipa.sh`, then iCloud Drive, then SideStore.
- **Memory:** the whole keyboard, with the panel open and scrolled through every category, stays ≤ 22 MB phys_footprint on the device. Today it is 9–12 MiB without the panel. Emoji data is decoded only when the panel first opens, and it is released on `trimMemory`/memory warnings when the panel is closed.
- **Snappy:** opening the panel and tapping an emoji must not drop a frame. Instruments signposts "emojiPanelOpen" and "emojiInsert" measure it.
- **Language-neutral:** category names shown to the user come from data (`emoji.json`), not Swift literals. SF Symbol names for tabs also live in the data.
- **Third-party notices:** Emojibase (MIT) and Unicode data (Unicode License v3) are credited in `THIRD_PARTY_NOTICES.md`.
- **Emoji version support:** emoji newer than the running iOS can draw show as empty boxes, so they are filtered out. Show Emoji ≤ 16.0 on iOS 26.0–26.3, and ≤ 17.0 on iOS 26.4 and later. The user's phone runs iOS 27.

## Review Focus

1. **Deleting emoji from the panel's `⌫`.** Flags (🇮🇳), ZWJ families and skin-toned emoji are removed whole, as one grapheme. Pinned in Task 3 (`panelDeleteRemovesWholeEmoji`).
2. **A missing or corrupt Recent or skin-tone store.** It loads as empty and never crashes. Pinned in Task 2 (`corruptRecentsLoadEmpty`).
3. **Fast scrolling through every category.** Memory stays bounded (cell reuse, no per-emoji caches). This is measured on the device in Task 5.
4. **Leaving the panel while a finger is down** on an emoji or on `⌫`. No stuck popup and no repeat after closing. Pinned in Task 4 (manual simulator check) and Task 3 (`leavingThePanelCancelsTouches`).
5. **The skin-tone popup at the screen edges.** It stays inside the keyboard view, as in milestone 1's R13. Checked in Task 4 with screenshots of the left-most and right-most columns.

---

## File Structure

```
scripts/make-emoji-data.py                         downloads emojibase-data@17.0.0, writes emoji.json (Task 1)
THIRD_PARTY_NOTICES.md                             Emojibase MIT + Unicode License v3 (Task 1)
Packages/CatkeysCore/Sources/KeyboardCore/
  Emoji/emoji.json                                  generated data, committed (Task 1)
  Emoji/EmojiCatalog.swift                          decode + version filter (Task 2)
  Emoji/EmojiPreferences.swift                      Recent + skin-tone choices over UserDefaults (Task 2)
  Controller/KeyboardController.swift (modify)      panel mode, emoji insert/delete (Task 3)
  Controller/KeyboardState.swift (modify)           `panel` field (Task 3)
Packages/CatkeysCore/Sources/KeyboardUI/
  EmojiPanelView.swift, EmojiCell.swift, EmojiTabBar.swift, SkinTonePopup.swift (Task 4)
  KeyboardView.swift (modify)                       shows the panel in place of the keys (Task 4)
Keyboard/KeyboardViewController.swift (modify)      wiring, signposts, memory warning (Task 4)
Tests/KeyboardCoreTests/EmojiCatalogTests.swift, EmojiPreferencesTests.swift, EmojiControllerTests.swift
```

`Package.swift` must also copy `Emoji/emoji.json` as a resource.

---

### Task 1: Emoji data

**Files:** create `scripts/make-emoji-data.py`, `THIRD_PARTY_NOTICES.md`, `Packages/CatkeysCore/Sources/KeyboardCore/Emoji/emoji.json`. Modify `Packages/CatkeysCore/Package.swift`, adding `.copy("Emoji/emoji.json")`, or copy the `Emoji` folder.

**Output format** (`emoji.json`, UTF-8):

```json
{ "source": "emojibase-data 17.0.0",
  "categories": [ { "id": "smileys-people", "name": "Smileys & People", "icon": "face.smiling",
                    "emoji": [ { "e": "😀", "v": 1.0 }, { "e": "👋", "v": 0.6, "s": ["👋🏻","👋🏼","👋🏽","👋🏾","👋🏿"] } ] } ] }
```

- **Categories,** in Apple's order:
  - `smileys-people`, which is Emojibase groups 0 and 1 merged
  - `animals-nature` (3), `food-drink` (4), `activity` (6), `travel-places` (5), `objects` (7), `symbols` (8), `flags` (9)
- **Tab icons:** `face.smiling`, `pawprint`, `fork.knife`, `soccerball`, `car`, `lightbulb`, `heart`, `flag`.
- **Names:** English display names, held in the data.
- **Left out:** group 2 (components, the skin-tone swatches).
- **Sort order:** emojibase `order`.
- **Skin tones:** `s` is present only for emoji whose `skins` all have a single integer `tone`, listed in tone order 1–5. Emoji with multi-tone skins (tone arrays) get no `s` in M3.
- **`v`** is emojibase `version`.

- [ ] **Step 1:** Write the script.
  - It downloads `https://cdn.jsdelivr.net/npm/emojibase-data@17.0.0/en/data.json` into `build/emoji-src/`, reads it as untrusted data with `json.load` only, and writes the output above.
  - It prints counts per category, the total, and the output size.
  - Use only the standard library, and run it with `python3 -I`.
- [ ] **Step 2: Run it.** Expected: about 1,900 base emoji across 8 categories and an output under 250 KB. Spot-check that 😀, 👋 with its 5 skins, 🇮🇳 and one Emoji 17.0 entry are present.
- [ ] **Step 3: Write `THIRD_PARTY_NOTICES.md`,** with Emojibase's MIT notice (copied from the package's LICENSE) and a Unicode License v3 notice covering the Unicode-derived data.
- [ ] **Step 4: Commit:** "Add emoji data from Emojibase"

### Task 2: Emoji catalog and preferences (KeyboardCore)

**Interfaces:**

```swift
public struct EmojiItem: Equatable, Sendable { public var base: String; public var version: Double; public var skins: [String] }   // skins empty or 5
public struct EmojiCategory: Equatable, Sendable { public var id: String; public var name: String; public var icon: String; public var items: [EmojiItem] }
public enum EmojiCatalog {
    public static func load(maxVersion: Double) throws -> EmojiData   // EmojiData { recentName, categories } (M3-R3); drops items with version > maxVersion
    public static func maxSupportedVersion(osMajor: Int, osMinor: Int) -> Double   // 26.0–26.3 → 16.0; ≥ 26.4 → 17.0; lower → 16.0
}
public final class EmojiPreferences {
    public init(defaults: UserDefaults)
    public var recents: [String] { get }                     // most recent first, max 32, de-duplicated by base emoji
    public func recordUse(_ emoji: String, base: String)     // moves base to front; stores the exact variant shown
    public func preferredVariant(for item: EmojiItem) -> String   // the user's last-picked skin for this base, else base
    public func setPreferredVariant(_ variant: String, for base: String)
}
```

- The keys in `UserDefaults` (the extension's own `.standard`, so no Full Access is needed) are `catkeys.emoji.recents` (`[String]` of variants) and `catkeys.emoji.skins` (`[String: String]`).
- **Decoding** must survive bad data:
  - Missing or corrupt values give empty results.
  - Non-string entries are dropped.

- [ ] **Step 1: Write the failing tests:**
  - `loadsAllCategoriesInOrder`: 8 ids in the Task 1 order, each non-empty, first item of `smileys-people` == "😀".
  - `versionFilterDropsNewer`: `load(maxVersion: 16.0)` has no item with `version > 16.0`, and `load(maxVersion: 17.0)` has strictly more items.
  - `maxSupportedVersion`: (26,0) → 16.0, (26,4) → 17.0, (27,0) → 17.0.
  - `skinsAreFiveOrNone`: every item's `skins.count` is 0 or 5.
  - `recentsMostRecentFirstAndCapped`: after 40 uses, count == 32; re-using one moves it to the front with no duplicate.
  - `preferredVariantRemembered`.
  - `corruptRecentsLoadEmpty`: Data or an Int stored under the keys loads as empty, with no crash.

  Use a temp-folder `UserDefaults` suite, as in milestone 1's `SettingsTests`.
- [ ] **Step 2: Run the tests and see them fail.**
- [ ] **Step 3: Implement.**
  - Decode with `JSONDecoder` once per call.
  - The caller holds the result, and the panel keeps it while it lives.
- [ ] **Step 4: Run the full `swift test`.** Expected: all pass.
- [ ] **Step 5: Commit:** "Add emoji catalog and preferences"

### Task 3: Controller panel mode

**Interfaces** (add to existing types):

```swift
public enum KeyboardPanel: Equatable, Sendable { case keys, emoji }
// KeyboardState
public var panel: KeyboardPanel            // .keys by default
// KeyboardController
public func insertEmoji(_ emoji: String)   // inserts as typed text: uses up a one-shot shift (M3-R6), clears shift-tap history and the double-space record, re-evaluates auto-shift
public func deleteFromPanel()              // deletes 1 grapheme (whole emoji); same bookkeeping as backspace
public func closePanel()                   // back to the page that was showing before; cancels in-flight key touches
```

- **Opening:** `.emoji` activation (today a no-op) cancels in-flight key touches with milestone 1's `cancelAll`, then sets `state.panel = .emoji`.
- **Closing:** `ABC` in the panel calls `closePanel()`, which goes back to the page and shift state as they were.
- **Resets:** `keyboardWillAppear` always returns to `.keys` (as in milestone 1's R28).
- **Recent and skin choices** are the view's job, via `EmojiPreferences`. The controller only edits text.

- [ ] **Step 1: Write the failing tests:**
  - `emojiKeyOpensPanel`
  - `insertEmojiTypesIt`: "hi " + insertEmoji("👋🏽") gives "hi 👋🏽".
  - `panelDeleteRemovesWholeEmoji`: "hi 🇮🇳" gives "hi ", and "👨‍👩‍👧" gives "".
  - `closePanelRestoresPage`: from symbols-1, open the panel, close it, and the page is symbols-1.
  - `keyboardWillAppearClosesPanel`
  - `leavingThePanelCancelsTouches`: hold backspace, tap emoji, and no further deletes come from `advance`.
  - `emojiThenDoubleSpace`: "ok" + emoji + space + space gives no ". ", because the text before the cursor ends with an emoji, not a letter or digit.
- [ ] **Step 2: Run them and see them fail.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run the full `swift test`.**
- [ ] **Step 5: Commit:** "Controller: emoji panel mode"

### Task 4: Emoji panel view and wiring

**Behaviour** (design §7 and the approved mockup):

- **Layout:**
  - The panel replaces the number row and key rows. It is exactly `controller.height` minus the suggestion row.
  - The empty suggestion row stays on top, so the keyboard height never changes when the panel opens.
  - The background is clear, so iOS's backdrop shows through (R42).
- **List:**
  - A vertical `UICollectionView` with 8 columns on a 390 pt width; the column count is derived from the width with about 44 pt cells.
  - Section headers show the category `name` from data in small grey caps.
  - "Recent" comes first and is hidden when empty. The "Recent" title is the one display string not in `emoji.json`, so add it there as `"recentName"`.
  - Each cell draws its emoji with a `UILabel` (system emoji font, about 30 pt).
  - Cells are reused. Don't cache images.
- **Tab bar** (bottom, about 40 pt):
  - `ABC` on the left closes the panel.
  - Then the category icons: SF Symbols from data, plus `clock` for Recent.
  - `⌫` on the right deletes one emoji per tap and repeats while held, using milestone 1's backspace timings (first repeat at 0.4 s, then every 0.07 s).
  - Tapping a tab scrolls to its section. The visible section's tab is highlighted while scrolling.
- **Tap an emoji:** insert `preferences.preferredVariant(for:)`, record its use, and refresh the Recent section. Do the refresh lazily, on the next panel open or the next time Recent scrolls into view, to avoid reloading during taps.
- **Skin tones:**
  - Holding an emoji that has skins for 0.3 s (milestone 1's long-press delay setting) shows a popup above it with the base and its 5 skins.
  - It is laid out like milestone 1's R13: the default sits under the finger and the popup stays inside the view.
  - Slide to choose, then release to insert and remember the choice.
- **Haptics:** the same `FeedbackSink.keyDown()` on taps. Sound follows the settings.
- **Signposts:** "emojiPanelOpen" (from the emoji key's touch-up to the first panel layout) and "emojiInsert".
- **Memory warning** with the panel closed: the view drops the decoded catalog.
- **Version filter:** `EmojiCatalog.load(maxVersion: maxSupportedVersion(...))`, using the running OS version.

- [ ] **Step 1:** Implement `EmojiPanelView`, `EmojiCell`, `EmojiTabBar` and `SkinTonePopup` (all under `#if canImport(UIKit)`), and wire them into `KeyboardView` and the extension.
- [ ] **Step 2: Preview host and screenshots.**
  - Add the launch arguments `-catkeysPreviewEmoji` (opens the panel) and `-catkeysPreviewEmojiHold <base>` (opens the skin popup for that emoji, for example 👋).
  - Add scenes to `scripts/sim-screenshots.sh`: `emoji` and `emoji-hold`, in light and dark.
  - Look at every PNG. Check:
    - the height matches the letters page
    - section headers
    - the tab bar with ABC, the icons and ⌫
    - the skin popup inside the view at the left-most and right-most columns
    - dark mode is readable
- [ ] **Step 3: Real extension in the simulator.** Install an example-prefix build over the selected simulator keyboard, as in Task 12b. Then open the panel, insert an emoji, delete it and close. Save the screenshots as `build/screenshots/extension-emoji-<light|dark>.png`.
- [ ] **Step 4:** Run `swift test`, the simulator build and `scripts/build-ipa.sh`.
- [ ] **Step 5: Commit:** "Add the emoji panel"

### Task 4b: Typing test in the app (M3-R9; the user approved the design in chat on 2026-10-22)

The user wants to measure tap accuracy with numbers, comparing builds and comparing catkeys with Apple's keyboard. The trigger was a regression: R42's fully clear background dropped taps in the gaps between keys, which ruling M3-R8 fixes.

**Files:**
- Create: `Packages/CatkeysCore/Sources/KeyboardCore/TypingTest/TypingMetrics.swift`, `TypingTest/TypingRun.swift`, `TypingTest/sentences.json`, `Tests/KeyboardCoreTests/TypingTestTests.swift`, `App/TypingTestView.swift`
- Modify: `App/ContentView.swift` (a new "Typing test" tab), `Package.swift` (resource)

**Interfaces:**
```swift
public enum TypingMetrics {
    public static func editDistance(_ a: String, _ b: String) -> Int          // Levenshtein over Characters (graphemes)
    public static func wordsPerMinute(characters: Int, seconds: Double) -> Double   // (characters / 5) / minutes; 0 if seconds <= 0
}
public struct TypingSentence: Equatable, Sendable { public var text: String; public var language: String }   // "en" or "hi-Latn"
public enum TypingSentences { public static func bundled() throws -> [TypingSentence] }   // reads TypingTest/sentences.json
public struct TypingRun: Codable, Equatable, Sendable {
    public var date: Date; public var keyboard: String            // "catkeys" | "Apple" | "Other"
    public var targetCharacters: Int; public var errorsLeft: Int; public var corrections: Int; public var seconds: Double
    public var errorRate: Double { get }                          // errorsLeft / targetCharacters
    public var wordsPerMinute: Double { get }
}
public struct TypingRunStore { public init(defaults: UserDefaults); public func load() -> [TypingRun]; public func append(_ run: TypingRun) }   // key catkeys.typingTest.runs; newest first; corrupt data loads as []
```

**Sentences:** about 12 short invented ones in `sentences.json`, half English and half Hinglish (Roman script), each 25–60 characters with ordinary punctuation. Never from `../private`.

**App tab ("Typing test"):**
- **Before a run:**
  - A keyboard picker: catkeys, Apple or Other. It defaults to catkeys when the shared heartbeat is less than 60 s old, and to Apple otherwise.
  - A Start button.
- **A run:** 5 sentences drawn at random from the set.
  - Each shows "Sentence i of 5", the target text, and a text field with `.autocorrectionDisabled(true)`, so Apple's keyboard is compared fairly without autocorrect. Capitalisation stays as normal.
  - **Done** submits the sentence.
  - The timer starts at the first edit of each sentence.
  - `corrections` grows by the number of graphemes removed each time the text gets shorter.
  - `errorsLeft` is `editDistance(target, submitted)`.
- **Summary:** errors left (count and %), corrections and WPM for the run, then a history list of past runs (date, keyboard, the three numbers).
- **Privacy:** typed text is never stored; only the run's numbers are. No network.
- **Copy:** use plain, short labels. Explain the three numbers in one line each under the summary.

- [ ] **Step 1: Write the failing tests:**
  - edit distance: "kitten"/"sitting" = 3; emoji count as one grapheme; empty strings
  - WPM: 50 characters in 60 s = 10.0
  - sentences load: 10–14 sentences, both languages present, every length 25–60
  - run store: round trip, newest first, corrupt data loads as []
  - `errorRate` with zero target characters is 0
- [ ] **Step 2: Run them and see them fail.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run the full `swift test`.**
- [ ] **Step 5: Build the app tab.** Screenshot it in light and dark to `build/screenshots/app-typingtest-*.png` and look at the screenshots.
- [ ] **Step 6: Commit:** "Add a typing test to the app"

### Task 4c: Emoji search, data and logic (M3-R15; the user approved the design in chat on 2026-10-22)

**What the user approved:**
- A "Search emoji" field sits at the top of the emoji panel.
- Tapping it brings back letter keys, with the search text and a strip of results above them. Taps type into the search, not into the app.
- Tapping a result inserts it into the app, and search stays open.
- ✕ clears the query. ABC, or ⌫ on an empty query, goes back to the panel.
- Matching uses English names and tags, by word beginnings. Exact matches come first, and recent emoji get a nudge.
- Hinglish keywords come later, as data only.
- Keyword data loads only when search opens.

**Files:** modify `scripts/make-emoji-data.py`. Create `Packages/CatkeysCore/Sources/KeyboardCore/Emoji/EmojiKeywords/` (generated per-language files such as `en.json`, plus `popular.json`; committed; see M3-R16 and M3-R17), `Emoji/EmojiSearch.swift` and `Tests/KeyboardCoreTests/EmojiSearchTests.swift`. Modify `Controller/KeyboardController.swift`, `Controller/KeyboardState.swift` and `Package.swift`.

**Data:** `emoji-keywords.json` is `{"source": "...", "language": "en", "keywords": {"<base emoji>": ["grinning", "face", ...]}}`.
- Each list is the Emojibase `label` words plus `tags`, lowercased, de-duplicated, with words under 2 letters dropped. The label words come first.
- Keys are the same fully-qualified base strings as `emoji.json`.
- The output is deterministic and should be roughly ≤ 200 KB. Skin variants get no keys of their own; search maps variants to bases through `EmojiIndex`.

**Logic:**
```swift
public struct EmojiSearch {
    public static func load() throws -> EmojiSearch                    // reads the bundled keywords once; the caller holds it
    public func results(for query: String, catalog: EmojiData, recents: [String], limit: Int = 60) -> [EmojiItem]
}
```
- **Words:** the query is lowercased and split on whitespace. Every query word must be a prefix of some keyword of the emoji.
- **Ranking:**
  1. Emoji with a keyword exactly equal to a query word come first.
  2. Then emoji whose label word matches.
  3. Then emoji with only a tag prefix match.
  4. Within each tier, emoji in `recents` come first, in recency order. After that, the catalog order.
- **Filter:** only emoji present in the version-filtered catalog.
- **Empty query:** returns [].

**Controller:**
- `KeyboardPanel` gains `.emojiSearch`, and `KeyboardState` gains `searchQuery: String`.
- `openEmojiSearch()` goes from `.emoji` to `.emojiSearch` and shows the letters page with the `.standard` bottom row.
- **Key taps** edit `searchQuery` instead of the document:
  - Character outputs are appended lowercased.
  - Space appends " ". Repeated spaces collapse, and there is no double-space full stop.
  - ⌫ removes one character. On an empty query it returns to `.emoji`.
  - Return closes search back to `.emoji`.
  - Shift and auto-capitals don't apply.
  - Long-press symbols append their symbol.
  - The 123 page works.
  - The emoji key does nothing.
- `clearEmojiSearch()` empties the query.
- `closeEmojiSearch()` returns to `.emoji`.
- `insertEmoji` still inserts into the document.
- `keyboardWillAppear` resets to `.keys`.
- Cursor mode is off in search: the space hold types a space.

- [ ] **Step 1: Extend the generator.** Run it and check `emoji.json` is byte-identical. Commit the keywords file and the size.
- [ ] **Step 2: Write the failing tests.**
  - search: "lau" → 😂 among the first 3; "red heart" → ❤️ first; "hea" includes ❤️; "zzzz" → []; a recent emoji outranks an equal-tier one; only catalog-filtered emoji come back
  - controller: typing in search doesn't touch the document; ⌫ on empty returns to `.emoji`; inserting from search types into the document; keyboardWillAppear resets; no shift or auto-cap in the query
- [ ] **Step 3: Implement.** Run the full `swift test`.
- [ ] **Step 4: Commit:** "Emoji search: keywords and logic"

### Task 4d: Emoji search, view (M3-R15)

**Layout** (the keyboard height never changes):
- In `.emojiSearch`, the 44 pt suggestion row becomes the search field: a magnifier, the query text with a caret (or the "Search emoji" placeholder), and ✕ when the query isn't empty.
- The number row's band becomes a horizontal results strip of about 36 pt emoji cells, which scrolls sideways. With no query it shows Recent, and with no results it is empty.
- The rest is the normal letter keys from the controller, with the same touch handling as typing.
- In `.emoji`, the panel gains a "Search emoji" field at its top. It sits in the suggestion-row band, so the height doesn't change, and tapping it calls `openEmojiSearch()`.

**Behaviour:**
- Tapping a result inserts it (`preferredVariant` + `recordUse` + feedback) and stays in search.
- Holding a result with skins opens the skin popup, like the panel.
- Placeholder and labels come from data: `emoji.json` gains `"searchPlaceholder": "Search emoji"`.
- The keyword data loads on the first `openEmojiSearch()` and is kept for the process (as in M3-R11). It is dropped on a memory warning while search is closed.

- [ ] **Step 1: Implement.**
- [ ] **Step 2: Screenshots.**
  - Add the preview launch arguments `-catkeysPreviewEmojiSearch <query>`.
  - Add the scenes `emoji-search-empty` and `emoji-search-lau`, in light and dark.
  - Check the real extension: open search, type "lau", tap 😂, ⌫ ×3 then ⌫ again returns to the panel, then ABC.
  - Look at every PNG.
- [ ] **Step 3:** Run `swift test`, the simulator build and `scripts/build-ipa.sh`.
- [ ] **Step 4: Commit:** "Emoji search view"

### Task 5: Device check and close (with the user)

- [ ] **Step 1:** Build the IPA, copy it to iCloud Drive, and have the user install it over the current one in SideStore.
- [ ] **Step 2: Measure.** Instruments runs `--all-processes` while the user opens the panel 10 times, scrolls through every category quickly and inserts emoji with skin tones.
  - The Logging template gives "emojiPanelOpen" and "emojiInsert".
  - The Activity Monitor template gives the keyboard's footprint.
  - Targets:
    - footprint ≤ 22 MB
    - panel open ≤ 50 ms
    - emoji insert ≤ 2 ms of our work
  - Delete the traces afterwards.
- [ ] **Step 3: The user's feel test.** Check:
  - opening is instant
  - scrolling is smooth
  - Recent fills up
  - skin tones are remembered
  - ⌫ removes whole emoji
  - ABC returns to the page you came from
  - newer emoji show as real emoji, not boxes
  - WhatsApp and Notes
  - dark mode
- [ ] **Step 4:** Record the results in Progress and clear `build/DerivedData`. Commit, then merge to `main` with `--no-ff`.

---

## Rulings

- M3-R1: catkeys builds its own panel; ISEmojiView has had no release since February 2023.
- M3-R2: emoji with multi-tone skins get no skin picker in M3.
- M3-R3: `emoji.json` carries `recentName`, and `EmojiCatalog.load` returns `EmojiData`.
- M3-R4: the panel scrolls vertically with section headers, as in the approved mockup.
- M3-R5: process only.
- M3-R6: an emoji uses up a one-shot shift; caps lock stays.
- M3-R7: when 😊 lifts while another key is held, the panel opens and that key is dropped. Nothing else in that touch batch acts under the panel.
- M3-R8: the backgrounds use a near-invisible fill (alpha 0.01) instead of `.clear`. iOS drops touches on fully transparent parts of a keyboard extension; the user confirmed this on the device (taps in the f/g gap typed nothing).
- M3-R9: the app gets a typing test (Task 4b), which the user approved.
- M3-R10: the skin popup pre-selects the variant the cell shows, the remembered tone, and places it under the finger.
- M3-R11: the decoded emoji catalog stays loaded for the keyboard process and is dropped only on a memory warning.
- M3-R12: 0.3 s after the keys first draw, once per process and at utility priority, catkeys draws Recent plus the first category's first 64 emoji into a tiny offscreen bitmap. Tab icons render on the main thread, one per run-loop turn. This avoids a slow first open: 172 ms becomes 35 ms on the simulator.
- M3-R13: the warm-up decodes the catalog, reads its emoji list and drops it, so the panel still decodes on first open. This keeps the plan's memory rule.
- M3-R15: emoji search, approved by the user (Tasks 4c and 4d). The keyboard height stays the same: the search field takes the suggestion-row band and the results strip takes the number-row band. Hinglish keywords come later, as data.
- M3-R16: search ranking.
  - **Tiers:** name word matches exactly, then name word starts with the query, then tag matches exactly, then tag starts with the query.
  - **Within a tier:** recent emoji first, then a small hand-curated popularity list (data), then a shorter matched keyword, then fewer name words, then catalog order.
  - **Keyword data:** one file per language in `Emoji/EmojiKeywords/`, merged on load, so adding Hinglish is data-only. English stopwords are dropped from names.
- M3-R17: refines the M3-R16 tiers.
  - **Tiers:** exact (a name word or tag equals the query word), then name word starts with the query, then tag starts with the query.
  - **Within a tier:** recent, popular, a name match before a tag match, shorter keyword, fewer name words, catalog order.
  - **Stopwords** (merged across languages) never exclude a result; they only raise the emoji that match them. A query of only stopwords uses them as required. A last word that begins a stopword is treated as one while the query still ends in it; after a space, the word counts as finished.
- M3-R18: in search, the bottom-left page key reads `ABC` (label from layout data) and returns to the emoji panel, as the user approved. The 😊 key does the same. From the panel, `ABC` returns to the letters.
- Data: `emoji.json` also carries `recentIcon` (`clock`), so no SF Symbol name is hard-coded in Swift.

## Progress

- 2026-10-22: plan written after milestone 1 closed. The user asked for the emoji panel before the suggestion row.
