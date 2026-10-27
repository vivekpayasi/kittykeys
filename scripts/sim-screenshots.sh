#!/usr/bin/env bash
# Builds the app, launches it on the iPhone 17 simulator (iOS 26.4) in each scene below (the keyboard
# preview, then each app tab), and saves a screenshot of each, light and dark, to
# build/screenshots/<name>-<light|dark>.png.
# The simulator stays booted afterwards. Run from anywhere: ./scripts/sim-screenshots.sh
set -euo pipefail

cd "$(dirname "$0")/.."

DEVICE_NAME="iPhone 17"
OS_VERSION="26.4"
DERIVED_DATA="build/DerivedData"
APP="$DERIVED_DATA/Build/Products/Debug-iphonesimulator/Kittykeys.app"
OUT="build/screenshots"
# Seconds from launch to screenshot.
SETTLE=2

# Each scene: <name>|<launch arguments>
SCENES=(
  "letters|-kittykeysPreview"
  "symbols-1|-kittykeysPreview -kittykeysPreviewPage symbols-1"
  "symbols-2|-kittykeysPreview -kittykeysPreviewPage symbols-2"
  "hold-d|-kittykeysPreview -kittykeysPreviewHold d"
  "hold-period|-kittykeysPreview -kittykeysPreviewHold ."
  # A web-address field: the row without the .com key, and holding . for the domains in their wider cells.
  "web|-kittykeysPreview -kittykeysPreviewField url"
  "web-hold-period|-kittykeysPreview -kittykeysPreviewField url -kittykeysPreviewHold ."
  "cursor|-kittykeysPreview -kittykeysPreviewCursor"
  "emoji|-kittykeysPreview -kittykeysPreviewEmoji"
  # Skin-tone popups at a middle column (base remembered), and at the left-most and right-most columns (the third skin
  # remembered, so it starts picked though the edge keeps it from the finger). 8 columns at 402 points.
  "emoji-hold|-kittykeysPreview -kittykeysPreviewEmojiHold 👋"
  "emoji-hold-left|-kittykeysPreview -kittykeysPreviewEmojiHold 👉"
  "emoji-hold-right|-kittykeysPreview -kittykeysPreviewEmojiHold 👈"
  # The Symbols section around ❓, where bare symbols such as ➕ ❓ ✅ ❌ must draw as colour emoji.
  "emoji-symbols|-kittykeysPreview -kittykeysPreviewEmojiHold ❓"
  # Emoji search: just opened (Recent in the results), after typing "lau", and holding 👋 among the results for "hand".
  "emoji-search-empty|-kittykeysPreview -kittykeysPreviewEmojiSearch"
  "emoji-search-lau|-kittykeysPreview -kittykeysPreviewEmojiSearch lau"
  "emoji-search-hold|-kittykeysPreview -kittykeysPreviewEmojiSearch hand -kittykeysPreviewEmojiHold 👋"
  # Ready-made themes (docs/plans/2026-10-27-themes.md): the user's Neon with a popup and the emoji panel, and one of
  # each key style and font design.
  "theme-neon|-kittykeysPreview -kittykeysPreviewTheme neon"
  "theme-neon-hold-d|-kittykeysPreview -kittykeysPreviewTheme neon -kittykeysPreviewHold d"
  "theme-neon-emoji|-kittykeysPreview -kittykeysPreviewTheme neon -kittykeysPreviewEmoji"
  "theme-light|-kittykeysPreview -kittykeysPreviewTheme light"
  "theme-dark|-kittykeysPreview -kittykeysPreviewTheme dark"
  "theme-midnight|-kittykeysPreview -kittykeysPreviewTheme midnight"
  "theme-amber|-kittykeysPreview -kittykeysPreviewTheme amber"
  "theme-synthwave|-kittykeysPreview -kittykeysPreviewTheme synthwave"
  "theme-terminal|-kittykeysPreview -kittykeysPreviewTheme terminal"
  "theme-paper|-kittykeysPreview -kittykeysPreviewTheme paper"
  "theme-rose|-kittykeysPreview -kittykeysPreviewTheme rose"
  "app-setup|-kittykeysTab setup"
  "app-settings|-kittykeysTab settings"
  "app-tryit|-kittykeysTab tryit"
  "app-themes|-kittykeysTab settings -kittykeysSettingsPage themes"
  "app-dark-themes|-kittykeysTab settings -kittykeysSettingsPage darkthemes"
)

xcodegen generate
xcodebuild -project Kittykeys.xcodeproj -scheme Kittykeys \
  -destination "platform=iOS Simulator,name=$DEVICE_NAME,OS=$OS_VERSION" \
  -derivedDataPath "$DERIVED_DATA" -quiet build

# The device's id, from the "-- iOS 26.4 --" section, matching the name exactly (not "iPhone 17 Pro").
UDID=$(xcrun simctl list devices available | awk -v section="-- iOS $OS_VERSION --" -v prefix="    $DEVICE_NAME (" '
  $0 == section { inside = 1; next }
  /^--/ { inside = 0 }
  inside && index($0, prefix) == 1 { match($0, /[0-9A-F-]{36}/); print substr($0, RSTART, RLENGTH); exit }
')
if [[ -z "$UDID" ]]; then
  echo "No \"$DEVICE_NAME\" simulator with iOS $OS_VERSION. Create one in Xcode; this script doesn't download runtimes." >&2
  exit 1
fi

BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP/Info.plist")

xcrun simctl bootstatus "$UDID" -b >/dev/null
xcrun simctl install "$UDID" "$APP"
mkdir -p "$OUT"

for appearance in light dark; do
  xcrun simctl ui "$UDID" appearance "$appearance"
  for scene in "${SCENES[@]}"; do
    name=${scene%%|*}
    arguments=${scene#*|}
    xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
    # $arguments is split into separate launch arguments on purpose.
    # shellcheck disable=SC2086
    # India's region whatever the simulator's, so "d" offers ₹ first in every screenshot.
    xcrun simctl launch "$UDID" "$BUNDLE_ID" -AppleLocale en_IN $arguments >/dev/null
    sleep "$SETTLE"
    # simctl chats on stderr even when it works; show what it said only when it fails.
    if ! output=$(xcrun simctl io "$UDID" screenshot "$OUT/$name-$appearance.png" 2>&1); then
      echo "$output" >&2
      exit 1
    fi
    echo "$OUT/$name-$appearance.png"
  done
done
xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
