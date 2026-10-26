# kittykeys

Open-source iOS custom keyboard, SwiftKey-style layout, powered by the anantara engine (`../anantara`). Claude builds this project; the user tests it on their iPhone. Installed by sideloading (SideStore or Xcode with a free Apple ID; possibly a paid developer account later).

## Requirements so far (from the user)

- Glide typing
- English + Hinglish first; more languages later, so nothing hard-codes a language
- Top number row (must-have)
- Symbols on long-press, shown as hints in the corner of keys, like SwiftKey and Yandex on Android (must-have)
- Snappy: typing must feel instant (must-have)
- Long-press the space bar to drag the cursor, like Apple's keyboard (cursor movement only; iOS gives third-party keyboards no way to select text)
- Next-word suggestions
- Emoji suggestions
- Autocorrect must never turn Hinglish words into English (the user keeps autocorrect off everywhere for this reason)

## iOS constraints to design around

- Keyboard extension memory cap is roughly 48-60 MB; exceeding it gets the keyboard killed silently.
- Secure (password) fields always use the system keyboard; no microphone access.
- Sharing data with the container app needs an App Group and "Allow Full Access".
- Free Apple ID: 3 active apps including SideStore, 7-day signing.

## Reuse

- Glide typing: port from FlorisBoard (`StatisticalGlideTypingClassifier`) or AnySoftKeyboard (`GestureTypingDetector`), both Apache-2.0; keep their notices.
- Emoji: ISEmojiView (MIT) for the panel; gemoji or Emojibase (MIT) for keywords.
- KeyboardKit is closed source now; not used.

## Status

Design approved 2026-10-21: `docs/design.md` is the source of truth (`docs/brief.md` is the earlier hand-off). Implementation plans and progress live in `docs/plans/`, one per milestone. Claude may commit on its own at milestones.

Milestone 1 (typing shell) is done and merged to `main` (2026-10-22). It was measured on the user's iPhone; see the plan's Progress section. Next is the emoji panel (milestone 3), moved ahead of the suggestion row at the user's request.

Install path: SideStore, the same as the user's other sideloaded app. `scripts/build-ipa.sh` builds an unsigned IPA from the gitignored `Config/Local.xcconfig`, which holds the user's bundle prefix. Copy `build/kittykeys.ipa` to iCloud Drive, and the user installs it from SideStore → My Apps → +. Never change the bundle ids: the free Apple ID has a weekly App ID quota.

Disk: keep builds in `build/` (gitignored) and clear it between milestones. The external SSD is exFAT, so it can't hold Xcode builds; use it only for large throwaway files such as Instruments traces.
