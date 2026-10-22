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
public func insertEmoji(_ emoji: String)   // inserts as typed text: clears shift-tap history and the double-space record, re-evaluates auto-shift
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

## Progress

- 2026-10-22: plan written after milestone 1 closed. The user asked for the emoji panel before the suggestion row.
