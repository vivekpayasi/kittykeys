# Themes round 2: dark versions, rounded and faded tops

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** a theme can carry its own dark version, edited in Light and Dark tabs (like Yandex Keyboard), and a theme with
a colour background can round its top corners to match iOS's bar and fade into it.

**Architecture:** today's `ThemeSpec` (one look) becomes `ThemeStyle`; a new `ThemeSpec` is an id, a name, a light
`ThemeStyle` and an optional dark one. The keyboard draws the style for the appearance. Settings drop the separate
dark-mode slot. `KeyboardView` draws a colour background as a layer that can round its top corners and fade its top
band.

**Tech Stack:** Swift 6.2, UIKit / Core Animation, SwiftUI, Swift Testing.

**Spec:** this file's Request and Design; it builds on `docs/plans/2026-10-27-themes.md` (rulings T-R1..T-R15 stand
unless replaced below).

## Request (the user's, 2026-10-27, after trying v0.5.0)

1. "i think we should give the option to choose whether we want to have only one theme palette for both light and dark
   or two. if the user chooses to have separate dark, then we should keep the entire theme options in two tabs - light
   and dark. user can then select whatever options they want to set. this is similar to what yandex keyboard provide
   and like its ux better." The Yandex screenshot shows "Dark theme version" as a switch at the top of Edit theme.
2. "in custom, the ios top bar sticks out weirdly. can we do some kind of gradient so that when user selects custom,
   from top to the start of the keyboard, we have that gradient and then the solid naturally goes down." Then, with a
   Yandex screenshot: "yandex deals with the ios lip by rounding the keyboard edges … give another option to round the
   top corners of the keyboard or not. but the rounding should match the ios rounding of the lips." And: "basically
   two toggles we are providing - for rounding and for fading". The user approved the mockups' other decisions.

## Design

- **R2-1, dark version (user):** each theme has a light look and, optionally, a dark one. The editor's "Dark version"
  switch adds Light and Dark tabs; every option below the tabs belongs to the tab's version, and the live keyboard
  shows it. Turning it on starts the dark version as a copy of the light one and opens the Dark tab; turning it off
  drops it (kept for the visit, so turning it back on restores it).
- **R2-2, Start from… (Claude's call, shown in the mockups):** a menu in each tab copies a ready-made or saved
  theme's look for that appearance into the tab. Replaces picking a separate theme for dark mode.
- **R2-3, no dark-mode slot (Claude's call):** Settings has one Theme row; `darkThemeID` goes. A v0.5.0 user who set
  one rebuilds it once as a dark version (release notes say so). Old settings still load; the key is ignored.
- **R2-4, ready-made themes:** Automatic is one theme with both versions (today's light and dark). The others stay
  single-look; Customise copies one, and a dark version can then be added.
- **R2-5, gallery:** a card for a theme with a dark version is split: light half left, dark half right.
- **R2-6, rounded top (user):** "Round top corners" rounds the background's top corners with iOS's bar's own curve:
  Apple's continuous corner at 26.4 pt, fitted to the user's screenshot (error about 1 px at 3x; a circular corner fits
  worse). A spike on the simulator showed the extension can't read iOS's container shape (`cornerConfiguration` with
  `containerConcentric` gives 0 at every level), so the radius is a constant, `Themes.topCornerRadius`.
- **R2-7, fade (user):** "Fade into iOS's bar" makes the band above the keys go from see-through at the top to the
  background colour exactly where the first row of keys starts, along a smooth curve (alpha 0, 0.15, 0.5, 0.85, 1 at
  even steps). The keys don't move. Both switches can be on.
- **R2-8, defaults (Claude's call):** rounding on, fade off, for every ready-made theme and for themes saved before
  these switches existed. Both switches show only with a colour background, and each version has its own.
- **R2-9, previews:** the app's live keyboard and screenshot preview paint a grey like iOS's bar behind the keyboard
  (light or dark with the app), so rounding and fading show as they will on the phone.
- **R2-10, saved data:** a custom theme is saved as `{"id", "name", "light": {…}, "dark": {…}?}`. Themes saved by
  v0.5.0 (flat fields) load as their light look. A `dark` that isn't a theme look is dropped and the theme loads.

## Global Constraints

As in the first themes plan: iOS 26+; `KeyboardCore` free of UIKit; the keyboard never traps; nothing theme-related per
keystroke beyond comparing two values; `catkeys.`/`kittykeys.` keys unchanged; bundle ids and App Group unchanged;
British spelling.

## Review Focus

- A v0.5.0 user's saved custom themes and settings after updating: themes load, the picked theme still shows.
  (Task 1 `decodesThemesSavedBy050`; Task 2 `settingsFrom050StillLoad`.)
- Dark version on, edited, off, on again within one editor visit: the edits come back; leaving keeps what shows.
  (Manual, Task 4.)
- Rounding and fade on a theme while the emoji panel or search is open: the background stays right. (Task 3
  screenshots.)
- Taps in the rounded corners and the faded band still reach the keyboard (ruling M3-R8). (Task 3: the view keeps its
  touchable fill under the background layer; checked by tapping the band on the simulator.)
- The gallery's split card and a long name. (Manual, Task 4.)

---

### Task 1: ThemeStyle and ThemeSpec with a dark version (KeyboardCore)

**Files:** Modify `Sources/KeyboardCore/Theme/ThemeSpec.swift` (rename to `ThemeStyle.swift` for the look, new
`ThemeSpec.swift` for the theme), `Themes.swift`; Test `Tests/KeyboardCoreTests/ThemeTests.swift`.

**Interfaces (produces):**
- `public struct ThemeStyle: Codable, Hashable, Sendable` — today's `ThemeSpec` without `id`/`name`, plus
  `roundsTopCorners: Bool` (default true) and `fadesTopEdge: Bool` (default false); all derived rules unchanged.
- `public struct ThemeSpec: Codable, Hashable, Sendable, Identifiable` — `id`, `name`, `light: ThemeStyle`,
  `dark: ThemeStyle?`; `func style(isDark: Bool) -> ThemeStyle`.
- `Themes`: `automaticLight`, `automaticDark: ThemeStyle`; `automatic: ThemeSpec`; `presets: [ThemeSpec]`;
  `topCornerRadius: Double = 26.4`; `spec(id:custom:) -> ThemeSpec?`;
  `active(themeID:custom:isDark:) -> ThemeStyle`; `newCustom(from: ThemeSpec, existing:) -> ThemeSpec`.

- [ ] **Step 1: Tests.** Existing tests move to `ThemeStyle` (a `preset(id)` helper returns its light style). New:
  `automaticHasBothVersions`, `activePicksTheVersionForTheAppearance` (custom with a dark version → dark in dark mode,
  light in light mode; without → light both ways; unknown id → Automatic's version), `decodesThemesSavedBy050` (flat
  JSON → light look, no dark), `darkVersionRoundTrips`, `brokenDarkVersionIsDropped` (`"dark": 42` → nil, theme
  loads), `roundingAndFadeDefaults` (missing → round on, fade off; presets round, none fade),
  `newCustomCopiesBothVersions`.
- [ ] **Step 2:** run `swift test` — fails to build.
- [ ] **Step 3:** implement.
- [ ] **Step 4:** `swift test` — all pass.
- [ ] **Step 5:** commit "Themes: a dark version inside each theme; rounding and fade settings".

### Task 2: Settings without the dark-mode slot (KeyboardCore)

**Files:** `Settings/KeyboardSettings.swift`, `Settings/SettingsStore.swift`; Test `SettingsTests.swift`.

- [ ] **Step 1: Tests:** defaults and round trip without `darkThemeID`; `settingsFrom050StillLoad` (JSON with
  `"darkThemeID":"neon"` and `"themeID":"paper"` → themeID paper, other fields kept); `removingAPickedThemeResetsTheSlot`
  now resets only `themeID`.
- [ ] **Step 2:** fails to build. **Step 3:** implement. **Step 4:** pass. **Step 5:** commit.

### Task 3: Drawing (KeyboardUI, extension, preview)

**Files:** `KeyboardTheme.swift` (`init(style:)`, `style`), `KeyLayer.swift`, `KeyboardView.swift` (background
layer), `Keyboard/KeyboardViewController.swift`, `App/KeyboardPreviewView.swift`, `scripts/sim-screenshots.sh`.

- [ ] `KeyboardView` keeps `.touchableClear` as its own fill and draws a colour background in a `CAGradientLayer` at
  the bottom of its layer stack: plain fill when not fading; the fade's stops over `0…firstRowTop` when fading; top
  corners at `Themes.topCornerRadius`, continuous, when rounding (masking only when fading, as a plain fill rounds
  without it). Updated on theme change and on each key rebuild.
- [ ] The extension resolves `Themes.active(themeID:custom:isDark:)`.
- [ ] The preview host paints iOS-bar grey behind the keyboard (R2-9); `-kittykeysPreviewTheme` scenes gain
  `theme-rose-fade` (a launch flag `-kittykeysPreviewFade` turns the fade on for the scene).
- [ ] Verify: build; screenshots (rounded presets, a faded one, emoji panel over a rounded theme, Automatic unchanged);
  real extension with Rose in WhatsApp-like Try it, light and dark; tap the faded band. Commit.

### Task 4: App (gallery, editor, Settings)

**Files:** `App/SettingsView.swift`, `App/ThemeGalleryView.swift`, `App/ThemeSwatch.swift`, `App/ThemeEditorView.swift`.

- [ ] Settings: one Theme row; `SettingsPage.darkThemes` and its screenshot scene go.
- [ ] Gallery: no slot; split card for two versions (R2-5).
- [ ] Swatch draws a `ThemeStyle`, with rounding and fade.
- [ ] Editor: Dark version switch, Light/Dark tabs, Start from… menu, Round top corners and Fade switches (colour
  background only); the live keyboard shows the tab's version.
- [ ] Verify through the UI test harness: turn the dark version on, edit the Dark tab, Start from Neon, switch tabs,
  turn it off and on again; the real keyboard in dark mode shows the dark version. Commit.

### Task 5: Docs, review, merge, release

- [ ] `docs/design.md` §4.4 and §9, README, CLAUDE.md, this plan's Progress.
- [ ] Fresh whole-branch review; fix pass; merge to `main`; release on the user's say-so.

## Progress

- 2026-10-27: design agreed in chat with mockups; plan written.
- 2026-10-27: Tasks 1–4 built on branch `themes-dark` (338 tests). Checked on the iOS 26.4 simulator: screenshots of
  rounded presets, Rose with the fade (light and dark), Neon's emoji panel, Automatic unchanged; the editor through a
  UI test (dark version on, Start from Neon, Light tab with the fade, split card in the gallery); the real keyboard
  switching between the light look (Rose, rounded and faded) and the dark look (Neon) with the phone's appearance.
- 2026-10-27: whole-branch review (fresh opus reviewer): "ready to merge", no critical or important issues; it loaded
  real v0.5.0 themes and settings built from the old code. Fixed: Start from a theme with two looks on a one-look theme
  now brings both (test), and the Settings footer says to customise a ready-made theme first. Deferred minors are in
  the hand-off message. 339 tests.
- 2026-10-28: merged to `main` (--no-ff) and released as v0.6.0 (build 6); the IPA on the v0.6.0 release is
  byte-identical to the local build.
- Device check for the user (v0.6.0):
  - A custom theme made in v0.5.0 is still there and still picked.
  - Rose with Round top corners, then with Fade too, in light and dark mode; compare with iOS's bar above.
  - The emoji panel and emoji search over a rounded, faded theme; tap the search field and near the rounded corners.
  - Customise a theme, turn on Dark version, Start from Neon on the Dark tab; switch the phone between light and dark
    while the keyboard shows.
  - Typing still feels instant with Round and Fade both on.
