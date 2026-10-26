#!/usr/bin/env python3
"""Adds a release to release/source.json, the SideStore (AltStore-format) source that lists kittykeys' releases.

SideStore users add the source once, by its URL, and see each new release as an update. The URL is the copy attached
to the latest GitHub release: https://github.com/<owner>/<repo>/releases/latest/download/source.json

Reads what it lists from the build scripts/build-ipa.sh just made, so the source matches the IPA:
    - the bundle id, version, build and minimum iOS from build/Payload/Kittykeys.app/Info.plist
    - the entitlements from the signed entitlements build-ipa.sh saved in build/ipa-entitlements/; SideStore refuses
      an app whose entitlements the source doesn't list
    - the privacy usage descriptions (NS...UsageDescription) from the app's Info.plist
    - the size of build/kittykeys.ipa

Each release goes first in "versions", and the older top-level fields (version, downloadURL, ...) that some SideStore
versions read are set to it too. Standard library only. Run by scripts/release.sh:
    python3 -I scripts/update-source.py --repo <owner>/<repo> --tag v0.2.0 --notes build/release-notes.md
"""
import argparse
import datetime
import glob
import json
import os
import plistlib
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE_PATH = os.path.join(ROOT, "release", "source.json")
APP_PATH = os.path.join(ROOT, "build", "Payload", "Kittykeys.app")
IPA_PATH = os.path.join(ROOT, "build", "kittykeys.ipa")
ENTITLEMENTS_GLOB = os.path.join(ROOT, "build", "ipa-entitlements", "*.signed.plist")
ICON_PATH = "App/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
# Entitlements every signed app has; sources needn't list them.
IMPLICIT_ENTITLEMENTS = {"application-identifier", "com.apple.developer.team-identifier"}

DESCRIPTION = (
    "An open-source iPhone keyboard for English and Hinglish: a number row, symbols on long-press with hints on the "
    "keys, space-bar cursor control, an emoji panel with search, and no autocorrect, so Hinglish words stay as typed. "
    "Nothing you type leaves your phone."
)


def fail(message):
    sys.exit(f"update-source: {message}")


def read_plist(path):
    try:
        with open(path, "rb") as f:
            return plistlib.load(f)
    except (OSError, plistlib.InvalidFileException) as error:
        fail(f"can't read {path}: {error}")


def entitlements():
    """The entitlement keys of the app and its keyboard, as signed, without the implicit ones."""
    paths = glob.glob(ENTITLEMENTS_GLOB)
    if not paths:
        fail(f"no signed entitlements in {os.path.dirname(ENTITLEMENTS_GLOB)}; run scripts/build-ipa.sh first")
    keys = set()
    for path in paths:
        keys.update(read_plist(path).keys())
    return sorted(keys - IMPLICIT_ENTITLEMENTS)


def new_source(repo, bundle_id, icon_url):
    owner = repo.split("/")[0]
    return {
        "name": "kittykeys",
        "identifier": f"io.github.{owner.lower()}.kittykeys",
        "subtitle": "An open-source keyboard for English and Hinglish",
        "sourceURL": f"https://github.com/{repo}/releases/latest/download/source.json",
        "website": f"https://github.com/{repo}",
        "iconURL": icon_url,
        "apps": [{
            "name": "kittykeys",
            "bundleIdentifier": bundle_id,
            "developerName": owner,
            "subtitle": "An open-source keyboard for English and Hinglish",
            "localizedDescription": DESCRIPTION,
            "iconURL": icon_url,
            "category": "utilities",
            "versions": [],
        }],
        "news": [],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--repo", required=True, help="the GitHub repository, as owner/name")
    parser.add_argument("--tag", required=True, help="the release's tag, such as v0.2.0")
    parser.add_argument("--notes", required=True, help="a file with the release notes")
    args = parser.parse_args()

    info = read_plist(os.path.join(APP_PATH, "Info.plist"))
    bundle_id = info.get("CFBundleIdentifier")
    version = info.get("CFBundleShortVersionString")
    build = info.get("CFBundleVersion")
    min_os = info.get("MinimumOSVersion")
    if not all(isinstance(value, str) and value for value in (bundle_id, version, build, min_os)):
        fail("the app's Info.plist lacks its bundle id, version, build or minimum iOS")
    if args.tag != f"v{version}":
        fail(f"the tag {args.tag} doesn't match the app's version {version}")
    try:
        with open(args.notes, encoding="utf-8") as f:
            notes = f.read().strip()
        size = os.path.getsize(IPA_PATH)
    except OSError as error:
        fail(str(error))

    icon_url = f"https://raw.githubusercontent.com/{args.repo}/{args.tag}/{ICON_PATH}"
    if os.path.exists(SOURCE_PATH):
        with open(SOURCE_PATH, encoding="utf-8") as f:
            source = json.load(f)
    else:
        source = new_source(args.repo, bundle_id, icon_url)
    app = source["apps"][0]
    if app["bundleIdentifier"] != bundle_id:
        fail(f"the source lists {app['bundleIdentifier']}, but the IPA is {bundle_id}")
    if any(entry["version"] == version for entry in app["versions"]):
        fail(f"version {version} is already in the source")

    date = datetime.date.today().isoformat()
    download_url = f"https://github.com/{args.repo}/releases/download/{args.tag}/{os.path.basename(IPA_PATH)}"
    release = {
        "version": version,
        "buildVersion": build,
        "date": date,
        "localizedDescription": notes,
        "downloadURL": download_url,
        "size": size,
        "minOSVersion": min_os,
    }
    app["versions"].insert(0, release)
    app["appPermissions"] = {
        "entitlements": entitlements(),
        "privacy": {key: value for key, value in info.items() if key.startswith("NS") and key.endswith("UsageDescription")},
    }
    app["iconURL"] = source["iconURL"] = icon_url
    # The older fields, for SideStore versions that read only the latest release.
    app.update(version=version, versionDate=date, versionDescription=notes, downloadURL=download_url, size=size)

    os.makedirs(os.path.dirname(SOURCE_PATH), exist_ok=True)
    with open(SOURCE_PATH, "w", encoding="utf-8") as f:
        json.dump(source, f, ensure_ascii=False, indent=2)
        f.write("\n")
    print(f"update-source: added {version} ({build}) to {os.path.relpath(SOURCE_PATH, ROOT)}")


if __name__ == "__main__":
    main()
