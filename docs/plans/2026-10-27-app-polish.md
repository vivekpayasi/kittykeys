# App polish after milestone 3

The user's requests of 2026-10-27, after milestone 3 shipped as v0.2.0. This file records what was decided and
built; there was no up-front task plan, as each change was small and approved in chat.

## Requests (the user's)

1. Remove the typing test.
2. Try it keeps one field; ideas to make trying better. The user picked a switch between field types and an
   onboarding that ticks features as the user tries them.
3. In web addresses `.com` and `/` squeeze the space bar: put `.com` in the period's hold, with a setting.
4. Let people in other countries reorder the currencies on **d**.
5. A SwiftKey-style keystroke heatmap (later).
6. SwiftKey-style themes (later).
7. Setup: drop the "keyboard last opened" status, and tick each step once it's done.

## Rulings

- P-R1: the typing test goes entirely: its tab, `KeyboardCore/TypingTest`, its tests and screenshot scenes. Its
  saved runs stay in the app's defaults, unread.
- P-R2: web-address fields get `/` in the comma's place and no `.com` key, so the space bar keeps its width. Holding
  `.` there and in email fields offers `.com .in .co.in .org .net`, `.com` first and preselected, in cells 1.6 times
  as wide (`KeySpec.longPressWidth`). Settings › "Show a .com key in web addresses" brings the key back (bottom row
  `url-com`). There's no setting for `/`, which costs no width.
- P-R3: a Currency setting instead of reordering: Automatic (the region's, matched by ISO code) or one picked from the
  layout's list. The chosen currency comes first on **d** (hint and preselected), then the list's order, five in all;
  the 123 page's two currency keys follow. Layout files use `{currency1}`, `{currency2}` and `{currencies}`.
- P-R4: Setup ticks step 1 when iOS's `AppleKeyboards` lists the installed keyboard, and step 2 when it's also
  added and the keyboard has written its heartbeat to the App Group, which needs Full Access. A removed keyboard's
  heartbeat is cleared. "Next: try it out" shows once both are ticked.
- P-R5: Try it switches its one field between Text, Email, Web and Number.
- P-R6: onboarding is learn-by-doing in Try it: five things to try (space-bar cursor, a long-press symbol, the ⌫
  word swipe, a text replacement, an emoji from search), each ticked when the keyboard reports it. The keyboard
  stores only which were done, once each, in the App Group (`kittykeys.triedFeatures`); the tab reads it each second.
  When all are done the list folds away and can be shown again or started over.

## Progress

- 2026-10-27: requests 1, 2 (field types), 3, 4 and 7 built on branch `app-tidy`. A review found the 123 pages still
  had the old web row, domains clipped in 36 pt cells, and settings changes that could skip a re-layout. All were
  fixed, and a re-review approved. Merged to `main` and released as v0.3.0.
- 2026-10-27: onboarding (request 2) built on branch `onboarding`. On the simulator with the real keyboard, the cursor,
  symbol, word-delete and shortcut items ticked live. The emoji-search item is covered by unit tests. A review found
  two problems, both fixed with tests:
  - "Start over" didn't reach a keyboard still showing; it now puts the keyboard away, so it reloads.
  - An emoji from Recent in search counted; now only one found by a typed query does.
  The keyboard's one write per item now waits for the next turn, off the keystroke. Merged to `main` and released as
  v0.4.0.
- Later: the heatmap and themes (requests 5 and 6), each brainstormed first.
- 2026-10-27: on the iPhone with v0.4.0, the user checked everything on the device list and reported "tried them all,
  everything works":
  - Setup's ticks (so `AppleKeyboards` is readable on the phone) and Open Settings;
  - the web-address row and the domain hold;
  - Things to try;
  - the SMS-code switch;
  - text replacements.
