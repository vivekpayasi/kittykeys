# kittykeys design

Status: draft for the user's approval, 2026-10-21. Builds on `docs/brief.md`.

Each decision is marked by who made it:

- **(user)**: the user decided or approved it in the design conversation.
- **(planning)**: the planning session decided it in the brief.
- **(Claude's call)**: a default chosen by the kittykeys session. The user can overturn any of these.
- **(agreed with anantara)**: settled with the engine session, provisionally until the user approves anantara's design doc.

## 1. Why this exists

The user wants to replace Apple's keyboard for daily use. Their complaints, in their words: Apple's keyboard "is sluggish, keystrokes miss a lot in comparison [to] earlier iOS versions, and predictions are not that good". Gboard and SwiftKey on iOS are neglected and lack features their Android versions have. The user likes SwiftKey's layout most and finds Gboard's tap typing accurate.

So the first job of kittykeys is the typing itself. Every tap must register on the key the user meant and appear instantly, even during fast typing. Everything else comes second. Predictions belong to the anantara project; kittykeys gives them a place to appear.

**What success looks like (user):** the user switches to kittykeys, types on it for a few days, and stops thinking about the keyboard.

## 2. Goals, non-goals, anti-goals

### Goals

- Instant, reliable tap typing: no dropped taps, no swapped letters, no lag. (user)
- Top number row (must-have). (user)
- Symbols on long-press, with the symbol shown in the corner of each key (must-have). (user)
- Space-bar cursor drag, like Apple's. (user)
- A suggestion row, filled by a stand-in predictor until anantara is ready. (user)
- Emoji suggestions in the suggestion row, and an emoji panel. (user)
- Glide typing. (user)
- English and Hinglish first, with nothing in code tied to a language. (user)
- Reuse open source wherever possible: the emoji panel, glide typing, emoji keywords. (user)

### Non-goals (for now)

- Our own prediction models. That's anantara's job. (user)
- Apple-style hidden resizing of key touch areas. It's out unless anantara becomes good at Hinglish and a test shows it helps this user. (user)
- Text selection. iOS gives keyboards no API for it.
- Emoji search inside the keyboard. A search field inside a keyboard is fiddly on iOS, so it can come later. (Claude's call)
- Swipe gestures beyond the backspace swipe. Swipes across the letters will belong to glide typing. (Claude's call)
- Themes beyond light and dark. (Claude's call)
- Publishing on the App Store. (planning)

### Anti-goals: failure even if everything else works

- **A word is changed without the user asking.** kittykeys never auto-replaces a word, in particular never turns a Hinglish word into English. Corrections only ever appear in the suggestion row. (user)
- **Typing feels slower than Apple's keyboard,** or taps get dropped during fast typing. (user)
- **The keyboard gets killed** for using too much memory.
- **Anything typed leaves the phone.** kittykeys makes no network requests. (Claude's call; this is also the promise made to the user when they turn on "Allow Full Access")
- **Private data reaches the repo.** Text from `../private` never goes into code, tests, fixtures, docs or commit messages. (planning, hard rule)

## 3. Constraints

- **Memory:** iOS kills a keyboard extension that uses more than roughly 48-60 MB of RAM, without warning. The limit is on RAM, not on app size: read-only memory-mapped files mostly don't count.
- **Password fields:** iOS always shows its own keyboard in secure (password) fields. The same is true for phone-number pads.
- **SMS codes:** iOS offers a code from Messages only on Apple's keyboard; no API gives it to other keyboards (checked against the iOS 27.1 SDK). In a one-time code field kittykeys switches to the next keyboard once, and stays if the user comes back with 🌐 (`CodeFieldHandOff`; a setting in the app turns it off). (user, 2026-10-25)
- **Microphone:** keyboard extensions have no microphone access. On Face ID iPhones, iOS draws its own 🌐 and 🎙 below every keyboard.
- **Cursor movement:** the cursor can only move by character offsets (`adjustTextPosition`). iOS doesn't tell a keyboard where a long line wraps on screen, and there's no API for selecting text.
- **Drawing area:** a keyboard can't draw outside its own view. Key popups for the top rows must fit inside the keyboard; the suggestion row gives them room.
- **"Allow Full Access":** needed for haptics and for sharing settings with the container app through an App Group.
- **Signing with a free Apple ID:** each signature lasts 7 days, and a free account allows 3 active apps (including SideStore) and 10 App IDs a week. kittykeys uses two App IDs, one for the app and one for the extension. When the signature expires, the keyboard silently stops working until the app is re-signed.
- **Toolchain:** the Xcode project is generated with XcodeGen from `project.yml`. (planning)
  - Xcode 26.4 (Swift 6.3) is installed. Xcode 27 (Swift 6.4, iOS 27 SDK) has been out since September 2026, and the user will update to it. Until then, building against iOS 26 is the fallback. (user)
  - Deployment target: iOS 26.0, so the build runs on the phone whichever Xcode builds it. (Claude's call)
- **Test device:** the user's iPhone 16 on iOS 27, with Face ID and a 60 Hz screen. It's already paired with this Mac. (user)
  - During test sessions it stays on the same Wi-Fi, or is connected by USB-C.
  - kittykeys' builder installs and profiles it directly with `xcrun devicectl` and `xctrace`, and the user judges the feel.
  - Installing on and profiling an iOS 27 phone probably needs Xcode 27.

## 4. Layout

All layouts live in data files, one per page, bundled with the keyboard. Each file lists every key with its label, output, long-press options and width. The corner hint is the first long-press option. Adding a language means adding files, not changing code. (Claude's call, from the user's "nothing hard-codes a language")

### 4.1 Letters page (user approved the mockup)

From top to bottom:

1. **Suggestion row:** three slots.
2. **Number row:** `1 2 3 4 5 6 7 8 9 0`. Always shown. Its keys are slightly shorter than the letter keys so the keyboard doesn't grow too tall.
3. **Letter rows**, with each key's corner symbol after the colon:

```
q:%  w:\  e:|  r:=  t:[  y:]  u:<  i:>  o:{  p:}
  a:@  s:#  d:₹  f:_  g:&  h:-  j:+  k:(  l:)
⇧   z:*  x:"  c:'  v::  b:;  n:!  m:?   ⌫
```

4. **Bottom row:** `[123] [😊] [,] [ space ] [.] [return]`

Details:

- **The symbol map** is Gboard's, with one change: ₹ replaces $ on **d**. Holding **d** offers `₹ $ €`.
- **Holding `.`** offers `. ? ! … : /`.
- **No globe key** on Face ID iPhones (user), because iOS draws one. On iPhones with a home button, where `needsInputModeSwitchKey` is true, a globe key goes left of the emoji key.

### 4.2 Symbols pages (user approved the mockup)

The number row stays on top. Tapping `1/2` or `2/2` switches between the pages, and `ABC` goes back to the letters.

Page 1, everyday symbols:

```
@  #  ₹  $  _  &  -  +  (  )
*  "  '  :  ;  !  ?  /  %  =
[1/2]  <  >  [  ]  {  }  |  ⌫
```

Page 2, less common symbols:

```
~  `  \  ^  •  °  …  §  ¶  ©
€  £  ¥  ¢  ×  ÷  √  π  ∞  ™
[2/2]  ®  ✓  «  »  ¿  ¡  ‰  ⌫
```

The bottom row is the same as on the letters page, with `ABC` in place of `123`.

### 4.3 Field-type variants (user approved)

- **Return key:** its label follows the app's `returnKeyType`, for example Send, Search or Go.
- **Email fields:** the bottom row gains `@`.
- **Web-address fields:** the bottom row gains `/` and `.com`.
- **Number and decimal pads:** kittykeys opens on symbols page 1, where the number row is. (Claude's call)

### 4.4 Size and look

- **Key sizes and colours** stay close to Apple's keyboard. The builder settles exact numbers by comparing the two on the device. (Claude's call)
- **Light and dark:** kittykeys follows the system setting and the app's `keyboardAppearance`. (Claude's call; the user accepted the mockups with placeholder colours)

## 5. Typing behaviour (user approved)

### Touch handling

- **Key areas are fixed.** A tap goes to the key whose area contains it. The gaps between keys belong to the nearest key, so there are no dead spots. Areas never resize based on predictions.
- **Feedback:** a key lights up on touch-down, and a magnified copy of the key pops up above the finger. Letter keys only; the popup can be turned off.
- **When a letter is typed:** on touch-up, so that holding a key can produce its symbol instead.
- **Which point picks the key:** the point where the finger landed, not where it lifted. This is also the `Tap` position sent to anantara.
  - Before glide typing exists, sliding off a key still types the key where the finger landed.
  - There's no Apple-style sliding to a neighbouring key to correct a tap, because glide typing will own slides.
  - (Claude's call)
- **Fast typing (rollover):** when a new finger lands while an earlier finger is still down on a key, the earlier key is typed immediately and its long-press is cancelled. Fast typing never drops or swaps letters. Every touch is tracked separately.
- **Long-press:** after 0.3 seconds, a popup shows the key's options with the corner symbol pre-selected. The user slides to choose and releases to type. The delay is adjustable.

### Keys

- **Shift:** tap to capitalise the next letter; double-tap for caps lock.
- **Automatic capitals** at the start of a sentence, only where the app's `autocapitalizationType` asks for them.
- **Double-tap space:** types a full stop and a space, only right after a letter or digit.
- **Backspace:** holding it repeats, and after about 1.5 seconds it deletes whole words. Swiping left starting on backspace deletes the previous word.

### Haptics and sound

- **Haptics:** a light tap on every key. This needs Full Access; without it, kittykeys goes silent. (user approved; the iOS rule is a constraint)
- **Sound:** off by default. When turned on, kittykeys plays the standard input click, which also follows the iPhone's keyboard-click setting.

### Space-bar cursor (user approved the mockup)

- **Starting it:** hold space for about ⅓ second. The key labels go blank and the whole keyboard acts as a trackpad until the finger lifts.
- **Left and right:** one character per small step, with faster movement covering more characters.
- **Up and down:** these only move across line breaks the user typed. The cursor goes to the same column on the line above or below, read from the text before and after the cursor. Inside one long wrapped paragraph, up and down do nothing (an iOS limit; the user knows).
- **Haptics:** a light tick for each character the cursor passes.
- **No selection** (an iOS limit; the user knows).

## 6. Suggestion row (user approved the mockup)

- **Layout:** three slots, with the best guess in the middle.
  - While a word is being typed, the slots show completions. For example, typing "affor" shows *affordable* in the middle.
  - After a space, they show next-word guesses.
- **Picking a suggestion:** tapping a slot replaces the word being typed and adds a space.
- **Emoji suggestions:** an emoji takes the right-hand slot when the current word matches an emoji keyword.
  - Keyword lists are per language: English from gemoji or Emojibase (both MIT), with Hinglish keywords added later.
  - This logic lives in kittykeys, not in the engine.
- **Corrections (later, from anantara):** the typed word stays in the left slot, in grey and in quotes, and the correction appears in the middle. Nothing changes unless the user taps.
- **Holding a suggestion:** stops that word from being suggested again (`forget`).
- **Before anantara is ready:** a stand-in predictor fills the row. It completes words from a public English word-frequency list and does nothing clever. No private data goes into it.
- **Height:** the row is always present, so the keyboard height never jumps. In milestone 1 it stays empty.

### Autocorrect policy (user)

kittykeys never auto-replaces a word. Corrections appear only as suggestions. There is no autocorrect setting to turn on.

### Accuracy improvements for later (user approved the order)

1. **Tap-position corrections:** anantara gets the position of every tap, so it can suggest *nahi* for "nsho". This is why the interface carries tap positions from day one.
2. **Personal tap habits:** learn where this user tends to land on each key. This doesn't depend on language.
3. **Apple-style resizing:** only if a test shows it helps (see non-goals).

Items 2 and 3 stay only if they measurably improve accuracy.

## 7. Emoji panel (user approved the mockup)

- **Opening and closing:** the 😊 key opens the panel. It has the same height as the letters, and the suggestion row stays above it.
- **Contents:** one scrolling list of every category, with Recent first. A tab bar at the bottom jumps between categories, with `ABC` on the left and `⌫` on the right.
- **Skin tones:** hold an emoji to pick one.
- **Source:** built on ISEmojiView (MIT) if it stays within its memory budget, measured in milestone 3. Otherwise kittykeys builds a lighter version of the same design. Emoji panels are a known cause of keyboards being killed for memory.

## 8. Glide typing (milestone 4)

- **Source:** port AnySoftKeyboard's `GestureTypingDetector` (Java, Apache-2.0, with tests), or FlorisBoard's `StatisticalGlideTypingClassifier` (Kotlin, Apache-2.0), to Swift. Ported files keep their original license notices. (planning; the user asked for maximum reuse)
- **Which one:** AnySoftKeyboard is preferred because its tests can be ported too and used to check the Swift version. FlorisBoard currently ships its classifier switched off. (Claude's call)
- **English only at first (user):** glide ships in M4, before anantara, using only English words. Hinglish words get tapped until anantara is plugged in and glide can use its vocabulary.
- **What a glide types:** lifting the finger types the best guess, and the alternatives appear in the suggestion row. Tapping an alternative swaps it in. A glide never changes any word other than the one it just typed. (Claude's call; every glide keyboard works this way)
- **Where it runs:** a swipe that starts on a letter key and travels beyond it becomes a glide. A plain tap stays a tap. The touch path comes from the same raw touch handling as tapping.
- **Vocabulary:** glide needs words with frequencies. Until anantara provides them, it uses the stand-in's public word list.
- **Who owns what:** kittykeys owns the decoder that turns a swipe path into candidate words. anantara ranks those candidates using the text before them, through an engine call designed with the anantara session when glide work starts.
  - That call may also give kittykeys the vocabulary the decoder needs, because anantara's pack files are private.
  - If kittykeys keeps a word list of its own, it's a read-only memory-mapped file, so it stays out of the 22 MB UI budget.
  - (Claude's call; the engine call itself needs agreement with anantara)

## 9. Architecture

### Targets

| Target | What it is | UI tech |
|---|---|---|
| `Kittykeys` | Container app: setup steps, settings, a field to try the keyboard in | SwiftUI (planning) |
| `KittykeysKeyboard` | Keyboard extension (`UIInputViewController`) | UIKit with raw touch handling (planning) |
| `KeyboardCore` | Local Swift package with all logic that doesn't need UIKit | none |

`KeyboardCore` holds the following. Splitting it out keeps the logic testable with `swift test` on the Mac. (Claude's call)

- Layout files and parsing
- Hit-testing
- The touch state machine: taps, rollover, long-press, cursor mode and backspace repeat
- Shift, auto-capitals and double-space rules
- Text actions behind a small protocol that wraps `UITextDocumentProxy`
- The `Predictor` protocol and the stand-in predictor
- Emoji keyword lookup

### The key grid (planning, refined by Claude)

The key grid is drawn by a single custom view that receives every touch through `touchesBegan`/`Moved`/`Ended`/`Cancelled`, with multiple touches enabled. Keys are lightweight layers with implicit animations off.

There are no `UIButton`s and no gesture recognizers on keys, because both add delay and glide typing needs the raw touch path. SwiftUI isn't used here for the same latency reason.

**Known iOS pitfall (verify in M1):** system edge gestures can delay touches on the bottom row of keyboard extensions. If measurements show the delay, turn off `delaysTouchesBegan` on the window's system gesture recognizers. Other keyboards use this workaround.

### Settings

- **Settings:** haptics, sound, key popup, double-space full stop, long-press delay, and switching to Apple's keyboard in one-time code fields.
- **Storage:** an App Group's shared defaults, written by the app and read by the keyboard.
- **Risk:** it's unconfirmed whether a free Apple ID can use App Groups with a keyboard extension. Verify on the device in M1. If it doesn't work, settings move into the keyboard itself, as a gear in the suggestion row when it's empty. Until then, the defaults in this document apply.

The container app's setup screen explains how to add the keyboard and what Full Access is used for (haptics and settings), and states that nothing leaves the phone.

### Prediction interface (provisionally agreed with anantara)

kittykeys owns this protocol. anantara exposes its own UniFFI-generated Swift API with records that mirror these, and kittykeys writes a thin adapter over it, so anantara never depends on kittykeys.

The anantara session agreed to this version provisionally on 2026-10-21. Final sign-off comes once the user approves anantara's own design doc. Until then, kittykeys builds against the stand-in.

```swift
protocol Predictor: AnyObject {
    // Called once when the keyboard opens. Keys work before it returns.
    // dataDirectory: read-only packs in the keyboard bundle (memory-mapped) plus anantara's manifest.json.
    // personalDirectory: writable, for the personal layer.
    func load(languages: [String], dataDirectory: URL, personalDirectory: URL) throws  // pack IDs from manifest.json
    func setLayout(_ layout: KeyLayout)          // letter-key geometry; on open, rotation, layout change
    func suggest(_ request: SuggestionRequest) -> [Suggestion]
    func learn(word: String, context: String, source: LearnSource)  // a word has settled (rules below)
    func forget(word: String)                    // user held a suggestion: never suggest it again
    func trimMemory()                            // iOS memory warning
    func flush()                                 // keyboard is hiding: persist the personal layer
}

struct SuggestionRequest {
    var context: String       // text before the current word, as much as iOS gives
    var partialWord: String   // "" right after a separator
    var taps: [Tap]           // one per character of partialWord; empty if not typed by taps
    var maxResults: Int       // 3
}
struct Tap { var x: Float; var y: Float }   // points, origin top-left of the key area
struct KeyLayout { var width: Float; var height: Float; var keys: [Key] }
struct Key { var output: String; var x: Float; var y: Float; var width: Float; var height: Float }
struct Suggestion { var text: String; var kind: Kind; var score: Float }
enum Kind { case completion, nextWord, correction }
enum LearnSource { case typed; case suggestion(index: Int) }   // index into the list that was shown
```

- **Threading:** all calls are synchronous and run on one serial background queue, never the main thread. Stale results are dropped.
- **Casing:** the engine returns words in their natural case, and kittykeys applies shift and caps.
- **Ranking:** `score` is internal to the engine and only comparable within one response. kittykeys uses the order only.
- **Languages:** pack IDs and display names come from anantara's `manifest.json` in `dataDirectory`, never from kittykeys code. English and Hinglish will probably ship as one combined pack. Here is the provisional manifest; anantara sends the final one with sign-off, and the stand-in ships a fake one in this format:

  ```json
  { "formatVersion": 1,
    "packs": [ { "id": "en+hi-Latn", "displayName": "English + Hinglish",
                 "languages": ["en", "hi-Latn"], "version": "0.0.0-stub",
                 "directory": "en+hi-Latn" } ] }
  ```

  Rules for reading it:
  - `id` is opaque: pass it to `load(languages:)` exactly as given.
  - `languages` (BCP-47) is used for choosing the layout and for display.
  - `directory` is relative to `dataDirectory`, and its contents are private to the engine.
  - Unknown keys are ignored.
  - A pack whose `formatVersion` is newer than kittykeys supports is skipped.
- **When to call `learn`:** a word is learned only once it has settled, meaning the next word was committed or the keyboard closed. Specifically:
  - If the user backspaces into a just-committed word, it isn't learned.
  - Nothing is learned in URL, email, number-pad, username or one-time-code fields.
  - Tokens made only of digits are skipped.
- **Staged loading:** `load()` returns once the first usable stage (vocabulary and n-grams) is ready. A neural model may finish loading afterwards on an engine-owned thread, and suggestions then improve without kittykeys doing anything.
- **Later:** glide typing will need a new engine call that generates or ranks glide candidates. anantara's pack files are private to the engine, so kittykeys never reads them.

## 10. Speed and memory budgets

These are first targets, to be measured in M1 and then revisited. The keyboard-side numbers are Claude's calls. The engine numbers and the memory split were provisionally agreed with anantara.

| What | Target | How it's measured |
|---|---|---|
| Touch-down to key highlight | Next display frame (≤ 16.7 ms on the iPhone 16's 60 Hz screen) | Instruments signposts, plus 240 fps slow-motion video |
| Touch-up to `insertText` | Same event handler; ≤ 2 ms of our main-thread work per key | Signposts |
| Startup work before keys are visible | ≤ 50 ms | Signposts from controller init to first draw |
| Keystroke to suggestion row updated | ≤ 50 ms, never blocking typing | Signposts |
| `suggest()` on the user's iPhone | p95 ≤ 10 ms | Engine benchmark |
| Engine `load()`, first usable stage | ≤ 150 ms | Signposts |
| kittykeys UI memory, including the emoji panel | ≤ 22 MB | `phys_footprint` in Instruments on the device |
| Engine dirty memory | ≤ 16 MB | Same; clean memory-mapped pages excluded |
| Headroom under a 48 MB ceiling | 10 MB | |

anantara will run a small test to see whether Core ML's runtime, and model weights copied for the GPU or Neural Engine, count as dirty memory. If they do, the split gets revisited before M5.

There's also a side-by-side check: film kittykeys and Apple's keyboard in 240 fps slow motion on the same phone and compare the time from tap to character. The user's own judgment after a few days of typing is the final test.

## 11. Milestones

Every milestone is built with `xcodebuild` and checked with simulator screenshots (`xcrun simctl`) before the user tests it on the phone. Each milestone ends with a short on-device checklist for the user.

1. **Typing shell:**
   - Layouts: the letters page, both symbols pages and the field-type variants.
   - Keys: corner hints and long-press popups, key popups, shift, caps and auto-capitals, backspace repeat and swipe, double-space full stop.
   - Feel: haptics and sound, space-bar cursor, light and dark.
   - The container app, with setup and settings.
   - An empty suggestion row.
   - Checks: the App Group test, the bottom-row delay check, and the first speed and memory measurements.
2. **Suggestion row:** the stand-in predictor, emoji suggestions, and hold-to-forget.
3. **Emoji panel:** ISEmojiView or a lighter build, with recents and skin tones, measured against its memory budget.
4. **Glide typing (English only):** the port from AnySoftKeyboard, with its tests ported too.
5. **anantara integration:** the adapter over anantara's Swift API, then re-measuring memory and speed with the engine session. Glide also gets anantara's vocabulary and ranking here, which brings Hinglish to glide.

## 12. Testing

- **Unit tests in `KeyboardCore`**, run with `swift test`:
  - Layout parsing.
  - Hit-testing, including gaps and edges.
  - Rollover order with overlapping touches.
  - Long-press timing, shift and caps states, auto-capitals and double-space rules.
  - Backspace repeat and switching to whole words.
  - Cursor-mode offsets, including up and down across line breaks.
  - Emoji keyword lookup and the stand-in predictor.
- **The glide port** is checked against ported versions of AnySoftKeyboard's tests.
- **The UI** is checked with simulator screenshots of every page in light and dark.
- **Feel** is judged by the user on the phone.
- **Test data** comes only from public word lists and invented sentences, never from `../private`.

## 13. Left to the builder

- Exact key sizes, gaps, colours, fonts and popup styling, matched to Apple's keyboard on the device.
- Timing details: backspace repeat rate, cursor speed curve, the double-tap window for shift and space.
- The layout file format and code structure.
- Which public word list feeds the stand-in, provided its license allows redistribution.

## 14. Open items and risks

- **Xcode 27:** needed to install on and profile the iOS 27 phone. If it can't be installed, fall back to iOS 26 (user).
- **App Groups with a free Apple ID:** unconfirmed. Test in M1 (section 9 has the fallback).
- **Bottom-row touch delay** from system gestures: test in M1.
- **Emoji panel memory:** test in M3.
- **Prediction interface and memory split:** provisionally agreed with anantara. Final sign-off comes after the user approves anantara's design doc.
- **The 7-day free signing:** the keyboard stops working silently when the signature expires. SideStore's auto-refresh or a paid account later avoids this.
- **Commits:** ask the user once whether kittykeys may commit on its own at each milestone.
