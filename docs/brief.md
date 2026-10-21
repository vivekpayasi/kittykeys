# catkeys: hand-off brief

Written 2026-10-21 by the planning session (the one that also works on the anantara engine) for the session that builds catkeys. This brief records what's been decided and what's still open. It is not the design doc; writing that is your first job.

## What the user wants

An iOS keyboard that replaces Apple's for daily use. The user makes more typos on Apple's keyboard than on older iOS versions. Gboard and SwiftKey on iOS are neglected and missing features that their Android versions have.

The user's must-haves, in their words:

- Top number row.
- Symbols on long-press, with the symbol shown in the corner of each key (as in SwiftKey and Yandex on Android).
- Snappy: typing must feel instant.

Also wanted:

- Long-press the space bar to drag the cursor, like Apple's keyboard. Limits: third-party keyboards can only move the cursor by characters (`adjustTextPosition`), so moving up and down lines is approximate at best, and there's no API to select text. Tell the user this when designing it.

- Glide typing.
- Next-word suggestions (from anantara).
- Emoji suggestions.
- English + Hinglish first, other languages later. Nothing should hard-code a language.
- SwiftKey is the layout the user likes most.

The user keeps autocorrect off in every keyboard because it turns Hinglish words into English. Proposed but not yet confirmed: corrections only appear in the suggestion bar and never replace a word on their own.

## Already decided

- **Who builds:** you do. The user tests on their iPhone. Bigger chunks are fine here, unlike in anantara.
- **Language:** Swift. The key grid uses UIKit with raw touch handling rather than SwiftUI or UIButton, for latency and because glide typing needs the full touch path. The container app can use SwiftUI. (This is the planning session's call; mention it in the design doc so the user sees it.)
- **Project file:** XcodeGen (`project.yml`). It's installed at /opt/homebrew/bin/xcodegen. Xcode 26.4, Swift 6.3 and iPhone 17 simulators are available.
- **Engine:** the keyboard codes against a Swift protocol for predictions, with a simple stub until anantara is ready. anantara will be consumed as a Swift package from `../anantara`: a Rust core behind a UniFFI-generated Swift API. The keyboard only ever sees Swift; building the Rust side is the engine session's job.
- **License and reuse:** Apache-2.0. See `../CLAUDE.md` and `CLAUDE.md` for what to reuse and the privacy rules.
- **Install:** sideloaded, starting with a free Apple ID through Xcode.

## Open: settle these with the user in the design doc

- The exact long-press symbol for each key, and the layout of the symbols page.
- Key popups, haptics and sound.
- The space-bar cursor: when it starts, its feel, and what happens to the keys while dragging.
- Swipe gestures (for example, swipe on backspace to delete a word).
- The emoji panel and the suggestion bar layout.
- Look and theme, including dark mode.
- How the 48-60 MB memory cap is split between the keyboard UI and the engine. This needs agreement with the engine session. The cap is on RAM, not app size: read-only, memory-mapped files mostly don't count against it, so dictionaries and models on disk can be much bigger. Verify this with Instruments.
- Snappiness budgets: launch time and touch-to-screen latency. Measure them with Instruments rather than guessing.
- Autocorrect policy: confirm the suggestion-only proposal above.

## Suggested milestones

1. A typing shell: full layout with the number row, shift and caps, symbols page, long-press symbols with corner hints, backspace repeat, globe key, haptics and space-bar cursor dragging. Measure snappiness at this point.
2. A suggestion bar with the stub predictor, plus emoji suggestions.
3. The emoji panel.
4. Glide typing, ported from FlorisBoard or AnySoftKeyboard.
5. anantara integration.

Before asking the user to test on the phone, check each milestone on the simulator: build with `xcodebuild`, then take screenshots with `xcrun simctl`.

## What only the user can do

- Approve the design doc.
- Choose the Apple ID or team for signing. That goes in a local `Local.xcconfig`, which is gitignored.
- Install on the iPhone, enable the keyboard and "Allow Full Access" in Settings, and judge how it feels.
- Allow commits. Ask once whether you may commit on your own at milestones.

## Talking to the engine session

- The engine session is currently `ios-keyboard-idea-c0`. Run `ListAgents` to confirm it's running, then use `SendMessage`.
- Message it only for:
  - the prediction interface (propose it and wait for agreement)
  - the memory budget split
  - anything that would change `../anantara`
- Never edit `../anantara` yourself.
- If the engine session isn't running, write the question in `docs/questions-for-engine.md` and tell the user.
