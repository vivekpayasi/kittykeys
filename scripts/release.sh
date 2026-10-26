#!/usr/bin/env bash
# Publishes a release on GitHub, where SideStore picks it up as an update:
#   1. sets the version in project.yml and moves the build number on by one
#   2. builds build/kittykeys.ipa with scripts/build-ipa.sh
#   3. adds it to release/source.json, the SideStore source (scripts/update-source.py)
#   4. commits, tags v<version>, pushes the branch and the tag
#   5. creates the GitHub release with the IPA and the source attached
# The notes come from the file given, or else from the commit subjects since the last release.
# Needs a clean working tree and the gh CLI signed in. Run from anywhere:
#   ./scripts/release.sh 0.2.0 [notes.md]
set -euo pipefail

cd "$(dirname "$0")/.."

fail() { echo "release: $*" >&2; exit 1; }

VERSION=${1:-}
NOTES_FILE=${2:-}
TAG="v$VERSION"
NOTES="build/release-notes.md"

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "usage: $0 <major.minor.patch> [notes file]"
[[ -z "$(git status --porcelain)" ]] || fail "the working tree has changes; commit them first."
! git rev-parse -q --verify "refs/tags/$TAG" >/dev/null || fail "tag $TAG already exists."
REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner) || fail "gh can't see this repository's GitHub remote."
BRANCH=$(git branch --show-current)
[[ -n "$BRANCH" ]] || fail "not on a branch."

mkdir -p build
if [[ -n "$NOTES_FILE" ]]; then
  cp "$NOTES_FILE" "$NOTES"
else
  PREVIOUS=$(git describe --tags --abbrev=0 --match 'v*' 2>/dev/null) ||
    fail "there is no earlier release to list changes from; pass a notes file."
  git log --format='- %s' "$PREVIOUS..HEAD" >"$NOTES"
  [[ -s "$NOTES" ]] || fail "nothing has changed since $PREVIOUS."
fi

BUILD=$(($(awk '$1 == "CURRENT_PROJECT_VERSION:" { print $2 }' project.yml) + 1))
sed -i '' -E "s/^( +MARKETING_VERSION: ).*/\1$VERSION/; s/^( +CURRENT_PROJECT_VERSION: ).*/\1$BUILD/" project.yml
grep -q "MARKETING_VERSION: $VERSION\$" project.yml && grep -q "CURRENT_PROJECT_VERSION: $BUILD\$" project.yml ||
  fail "couldn't set the version in project.yml."

./scripts/build-ipa.sh
python3 -I scripts/update-source.py --repo "$REPO" --tag "$TAG" --notes "$NOTES"

git add project.yml release/source.json
git commit -q -m "Release $VERSION"
git tag -a "$TAG" -m "kittykeys $VERSION"
git push -q origin "$BRANCH" "$TAG"
gh release create "$TAG" build/kittykeys.ipa release/source.json --title "kittykeys $VERSION" --notes-file "$NOTES"
echo "release: published $TAG. SideStore source: https://github.com/$REPO/releases/latest/download/source.json"
