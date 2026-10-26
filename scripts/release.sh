#!/usr/bin/env bash
# Publishes a release on GitHub, where SideStore picks it up as an update:
#   1. sets the version in project.yml and moves the build number on by one
#   2. builds build/kittykeys.ipa with scripts/build-ipa.sh
#   3. adds it to release/source.json, the SideStore source (scripts/update-source.py)
#   4. commits, tags v<version>, and pushes the branch and the tag together
#   5. creates the GitHub release with the IPA and the source attached
# The notes come from the file given (keep it outside the repo or in build/), or else from the commit subjects since
# the last release. Releases normally come from main. Needs a clean working tree and the gh CLI signed in.
# If a step before the commit fails, project.yml and the source are put back; if one after it fails, the script
# says what is left to run. Run from anywhere:
#   ./scripts/release.sh 0.2.0 [notes.md]
set -euo pipefail

VERSION=${1:-}
# The notes file's path is taken before the cd below, so a relative one works from anywhere.
NOTES_FILE=${2:+$(cd "$(dirname "$2")" && pwd)/$(basename "$2")}

cd "$(dirname "$0")/.."

fail() { echo "release: $*" >&2; exit 1; }

TAG="v$VERSION"
NOTES="build/release-notes.md"
SOURCE="release/source.json"

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "usage: $0 <major.minor.patch> [notes file]"
[[ -z "$NOTES_FILE" || -f "$NOTES_FILE" ]] || fail "no notes file at $NOTES_FILE."
[[ -z "$(git status --porcelain)" ]] || fail "the working tree has changes; commit them first."
BRANCH=$(git branch --show-current)
[[ -n "$BRANCH" ]] || fail "not on a branch."
[[ "$BRANCH" == "main" ]] || echo "release: releasing from $BRANCH, not main."
REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner) || fail "gh can't see this repository's GitHub remote."
! git rev-parse -q --verify "refs/tags/$TAG" >/dev/null || fail "tag $TAG already exists here."
[[ -z "$(git ls-remote --tags origin "refs/tags/$TAG")" ]] || fail "tag $TAG already exists on GitHub."
git push -q --dry-run origin "$BRANCH" || fail "can't push $BRANCH to origin."

mkdir -p build
if [[ -n "$NOTES_FILE" ]]; then
  cp "$NOTES_FILE" "$NOTES"
else
  PREVIOUS=$(git describe --tags --abbrev=0 --match 'v*' 2>/dev/null) ||
    fail "there is no earlier release to list changes from; pass a notes file."
  git log --format='- %s' "$PREVIOUS..HEAD" >"$NOTES"
  [[ -s "$NOTES" ]] || fail "nothing has changed since $PREVIOUS."
fi

# Until the commit, a failure puts project.yml and the source back as they were.
SOURCE_TRACKED=$(git ls-files --error-unmatch "$SOURCE" >/dev/null 2>&1 && echo yes || echo no)
restore() {
  git checkout -q -- project.yml
  if [[ "$SOURCE_TRACKED" == yes ]]; then git checkout -q -- "$SOURCE"; else rm -f "$SOURCE"; fi
  echo "release: failed; project.yml and $SOURCE are back as they were." >&2
}
trap restore ERR

BUILD=$(($(awk '$1 == "CURRENT_PROJECT_VERSION:" { print $2 }' project.yml) + 1))
sed -i '' -E "s/^( +MARKETING_VERSION: ).*/\1$VERSION/; s/^( +CURRENT_PROJECT_VERSION: ).*/\1$BUILD/" project.yml
# Separate lines: set -e and the trap skip a failure in the first half of an && list.
grep -q "MARKETING_VERSION: $VERSION\$" project.yml
grep -q "CURRENT_PROJECT_VERSION: $BUILD\$" project.yml

./scripts/build-ipa.sh
python3 -I scripts/update-source.py --repo "$REPO" --tag "$TAG" --notes "$NOTES"

git add project.yml "$SOURCE"
git commit -q -m "Release $VERSION"
trap - ERR

LEFT="git tag -a $TAG -m 'kittykeys $VERSION'; git push --atomic origin $BRANCH $TAG; \
gh release create $TAG build/kittykeys.ipa $SOURCE --title 'kittykeys $VERSION' --notes-file $NOTES"
git tag -a "$TAG" -m "kittykeys $VERSION" || fail "committed, but tagging failed. Left to run: $LEFT"
LEFT=${LEFT#*; }
git push -q --atomic origin "$BRANCH" "$TAG" || fail "committed and tagged, but the push failed. Left to run: $LEFT"
LEFT=${LEFT#*; }
gh release create "$TAG" build/kittykeys.ipa "$SOURCE" --title "kittykeys $VERSION" --notes-file "$NOTES" ||
  fail "pushed, but creating the GitHub release failed. Left to run: $LEFT"
echo "release: published $TAG. SideStore source: https://github.com/$REPO/releases/latest/download/source.json"
