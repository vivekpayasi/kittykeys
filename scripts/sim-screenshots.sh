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
APP="$DERIVED_DATA/Build/Products/Debug-iphonesimulator/Catkeys.app"
OUT="build/screenshots"
# Seconds from launch to screenshot.
SETTLE=2

# Each scene: <name>|<launch arguments>
SCENES=(
  "letters|-catkeysPreview"
  "symbols-1|-catkeysPreview -catkeysPreviewPage symbols-1"
  "symbols-2|-catkeysPreview -catkeysPreviewPage symbols-2"
  "hold-d|-catkeysPreview -catkeysPreviewHold d"
  "hold-period|-catkeysPreview -catkeysPreviewHold ."
  "cursor|-catkeysPreview -catkeysPreviewCursor"
  "app-setup|-catkeysTab setup"
  "app-settings|-catkeysTab settings"
  "app-tryit|-catkeysTab tryit"
)

xcodegen generate
xcodebuild -project Catkeys.xcodeproj -scheme Catkeys \
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
    xcrun simctl launch "$UDID" "$BUNDLE_ID" $arguments >/dev/null
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
