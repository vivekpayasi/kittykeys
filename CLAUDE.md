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

Milestone 1 (typing shell) is done and merged to `main` (2026-10-22). It was measured on the user's iPhone; see the plan's Progress section. Milestone 3 (emoji panel, moved ahead of the suggestion row at the user's request) and the user's later requests (SMS codes, text replacements, the rename) were merged to `main` on 2026-10-27 and released as v0.2.0. Its device check and measurement (Task 5) are still to do, on `main`. Later polish (web-address row, currency, setup ticks, Try it and its onboarding) is in `docs/plans/2026-10-27-app-polish.md`, released as v0.3.0 and v0.4.0. The heatmap and themes come later, each brainstormed first.

The project was called catkeys until 2026-10-26 (M3-R24). Old plans keep the old names. The bundle ids, the App Group and saved defaults keys still say catkeys, on purpose.

Releases: public repo `vivekpayasi/kittykeys` on GitHub. `scripts/release.sh <version>` bumps the version, builds the IPA, updates the SideStore source `release/source.json`, tags, pushes, and creates the GitHub release; the user gets it as an update in SideStore, from the source `https://github.com/vivekpayasi/kittykeys/releases/latest/download/source.json`. Commits use the author email `iamvivek7411@gmail.com` (set in this repo's git config). `scripts/build-ipa.sh` alone builds the ad-hoc signed `build/kittykeys.ipa` for a quick test build through iCloud Drive and SideStore → My Apps → +. Both read the gitignored `Config/Local.xcconfig`, which keeps the user's install on its old bundle id (`KITTYKEYS_BUNDLE_ID`). Never change the bundle ids: the free Apple ID has a weekly App ID quota.

Disk: keep builds in `build/` (gitignored) and clear it between milestones. The external SSD is exFAT, so it can't hold Xcode builds; use it only for large throwaway files such as Instruments traces.
