#!/usr/bin/env bash
# Builds build/catkeys.ipa for SideStore: a Release archive built without signing, ad-hoc signed with
# the App Group entitlements so SideStore knows which group to register (and rename) when it re-signs
# the app with the user's Apple ID. The bundle prefix comes from Config/Local.xcconfig.
# Run from anywhere: ./scripts/build-ipa.sh
set -euo pipefail

cd "$(dirname "$0")/.."

PROJECT="Catkeys.xcodeproj"
SCHEME="Catkeys"
DERIVED_DATA="build/DerivedData"
ARCHIVE="build/Catkeys.xcarchive"
PAYLOAD="build/Payload"
ENTITLEMENTS_DIR="build/ipa-entitlements"
IPA="build/catkeys.ipa"
APP="$PAYLOAD/Catkeys.app"
APPEX="$APP/PlugIns/CatkeysKeyboard.appex"

fail() { echo "build-ipa: $*" >&2; exit 1; }

xcodegen generate

SETTINGS=$(xcodebuild -showBuildSettings -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath "$DERIVED_DATA")
# The value of build setting $1 (the first target's; these are the same for both targets).
setting() { awk -v key="$1" '$1 == key && $2 == "=" { sub(/^[^=]*=[ ]?/, ""); print; exit }' <<<"$SETTINGS"; }

PREFIX=$(setting CATKEYS_BUNDLE_PREFIX)
APP_GROUP=$(setting CATKEYS_APP_GROUP)
APP_ENTITLEMENTS=$(setting CATKEYS_APP_ENTITLEMENTS)
KB_ENTITLEMENTS=$(setting CATKEYS_KB_ENTITLEMENTS)

# Every bundle id costs one of the free Apple ID's few App IDs, so don't spend one on the placeholder.
[[ -n "$PREFIX" && "$PREFIX" != "com.example" ]] ||
  fail "CATKEYS_BUNDLE_PREFIX is '$PREFIX'. Set your own in Config/Local.xcconfig (see Local.xcconfig.example)."
[[ -n "$APP_GROUP" ]] || fail "CATKEYS_APP_GROUP is empty."
[[ -n "$APP_ENTITLEMENTS" && -n "$KB_ENTITLEMENTS" ]] ||
  fail "The entitlements files are unset. SideStore needs the App Group: remove the CATKEYS_*_ENTITLEMENTS overrides from Config/Local.xcconfig."

rm -rf "$ARCHIVE" "$PAYLOAD" "$ENTITLEMENTS_DIR" "$IPA"
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath "$DERIVED_DATA" \
  -archivePath "$ARCHIVE" CODE_SIGNING_ALLOWED=NO -quiet archive

mkdir -p "$PAYLOAD" "$ENTITLEMENTS_DIR"
cp -R "$ARCHIVE/Products/Applications/Catkeys.app" "$PAYLOAD/"

# The ids SideStore registers (with its own suffix) are these, so they must match the prefix.
check_bundle_id() {
  local actual
  actual=$(plutil -extract CFBundleIdentifier raw "$1/Info.plist")
  [[ "$actual" == "$2" ]] || fail "$1 has bundle id '$actual', expected '$2'."
  echo "Bundle id: $2"
}
check_bundle_id "$APP" "$PREFIX.catkeys"
check_bundle_id "$APPEX" "$PREFIX.catkeys.keyboard"

# The entitlements files hold $(CATKEYS_APP_GROUP), which Xcode expands only when it signs.
expand_entitlements() {
  local content
  content=$(<"$1")
  content=${content//'$(CATKEYS_APP_GROUP)'/$APP_GROUP}
  [[ "$content" != *'$('* && "$content" != *'${'* ]] || fail "$1 uses a build setting this script doesn't expand."
  printf '%s\n' "$content" >"$2"
  plutil -lint -s "$2" || fail "$2 isn't a valid property list."
}
expand_entitlements "$KB_ENTITLEMENTS" "$ENTITLEMENTS_DIR/CatkeysKeyboard.entitlements"
expand_entitlements "$APP_ENTITLEMENTS" "$ENTITLEMENTS_DIR/Catkeys.entitlements"

# Inside out: the extension first, then the app that seals it.
codesign -f -s - --entitlements "$ENTITLEMENTS_DIR/CatkeysKeyboard.entitlements" "$APPEX"
codesign -f -s - --entitlements "$ENTITLEMENTS_DIR/Catkeys.entitlements" "$APP"

check_app_group() {
  local signed actual
  signed="$ENTITLEMENTS_DIR/$(basename "$1").signed.plist"
  # The same check as `codesign -d --entitlements :-`, without that form's deprecation warning.
  codesign -d --entitlements - --xml "$1" >"$signed" 2>/dev/null
  actual=$(/usr/libexec/PlistBuddy -c "Print :com.apple.security.application-groups:0" "$signed" 2>/dev/null) ||
    fail "$1 is signed without an App Group."
  [[ "$actual" == "$APP_GROUP" ]] || fail "$1 is signed with App Group '$actual', expected '$APP_GROUP'."
  echo "App Group in $(basename "$1"): $actual"
}
codesign --verify --strict "$APPEX"
codesign --verify --strict "$APP"
check_app_group "$APPEX"
check_app_group "$APP"

(cd build && zip -qry "$(basename "$IPA")" Payload)
echo "$IPA ($(du -h "$IPA" | cut -f1 | tr -d ' '))"
