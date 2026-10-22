#!/usr/bin/env python3
"""Builds the emoji panel's data file from Emojibase (MIT).

Downloads emojibase-data@17.0.0 into build/emoji-src/ (gitignored) and writes
Packages/CatkeysCore/Sources/KeyboardCore/Emoji/emoji.json, which is committed.

The downloaded files are untrusted data: they are only ever parsed with json.load and
every field used is type-checked. Standard library only. Run from anywhere:

    python3 -I scripts/make-emoji-data.py            # reuses files already in build/emoji-src/
    python3 -I scripts/make-emoji-data.py --refresh  # downloads them again

Output (UTF-8, one emoji per line so diffs stay readable, otherwise compact):
    {"source": "emojibase-data 17.0.0", "recentName": "Recent",
     "categories": [{"id", "name", "icon", "emoji": [{"e", "v", "s"?}]}]}
"""

import json
import os
import ssl
import sys
import urllib.request

PACKAGE = "emojibase-data"
VERSION = "17.0.0"
CDN = f"https://cdn.jsdelivr.net/npm/{PACKAGE}@{VERSION}/"
SOURCES = {
    "package.json": CDN + "package.json",
    "LICENSE": CDN + "LICENSE",
    "groups.json": CDN + "meta/groups.json",
    "data.json": CDN + "en/data.json",
}
MAX_DOWNLOAD_BYTES = 32 * 1024 * 1024
# The python.org macOS build ships without CA certificates; the system bundle fills the gap.
SYSTEM_CA_FILE = "/etc/ssl/cert.pem"

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC_DIR = os.path.join(ROOT, "build", "emoji-src")
OUT_PATH = os.path.join(ROOT, "Packages", "CatkeysCore", "Sources", "KeyboardCore", "Emoji", "emoji.json")

RECENT_NAME = "Recent"

# Apple's category order. Each entry: id, display name, SF Symbol for the tab, Emojibase groups.
# Group 2 (component: skin-tone swatches, hair parts) is left out on purpose.
CATEGORIES = [
    ("smileys-people", "Smileys & People", "face.smiling", [0, 1]),
    ("animals-nature", "Animals & Nature", "pawprint", [3]),
    ("food-drink", "Food & Drink", "fork.knife", [4]),
    ("activity", "Activity", "soccerball", [6]),
    ("travel-places", "Travel & Places", "car", [5]),
    ("objects", "Objects", "lightbulb", [7]),
    ("symbols", "Symbols", "heart", [8]),
    ("flags", "Flags", "flag", [9]),
]

# The Emojibase group keys this mapping assumes; checked against meta/groups.json.
EXPECTED_GROUPS = {
    0: "smileys-emotion",
    1: "people-body",
    2: "component",
    3: "animals-nature",
    4: "food-drink",
    5: "travel-places",
    6: "activities",
    7: "objects",
    8: "symbols",
    9: "flags",
}

MAX_EMOJI_CODEPOINTS = 16


def fail(message):
    print(f"make-emoji-data: {message}", file=sys.stderr)
    sys.exit(1)


def tls_context():
    """Certificate verification always stays on."""
    context = ssl.create_default_context()
    if os.path.exists(SYSTEM_CA_FILE):
        context.load_verify_locations(cafile=SYSTEM_CA_FILE)
    return context


def download(name, url, refresh):
    path = os.path.join(SRC_DIR, name)
    if os.path.exists(path) and not refresh:
        return path
    if not url.startswith("https://cdn.jsdelivr.net/"):
        fail(f"refusing to download from {url}")
    print(f"downloading {url}")
    with urllib.request.urlopen(url, timeout=60, context=tls_context()) as response:
        body = response.read(MAX_DOWNLOAD_BYTES + 1)
    if len(body) > MAX_DOWNLOAD_BYTES:
        fail(f"{url} is larger than {MAX_DOWNLOAD_BYTES} bytes")
    tmp = path + ".part"
    with open(tmp, "wb") as f:
        f.write(body)
    os.replace(tmp, path)
    return path


def load_json(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def is_int(value):
    return isinstance(value, int) and not isinstance(value, bool)


def is_number(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def checked_emoji(value, where):
    if not isinstance(value, str) or not value or len(value) > MAX_EMOJI_CODEPOINTS:
        fail(f"bad emoji string in {where}: {value!r}")
    if any(ord(ch) < 0x80 and not ("0" <= ch <= "9" or ch in "#*") for ch in value):
        fail(f"unexpected ASCII in emoji string in {where}: {value!r}")
    return value


def verify_package(path):
    package = load_json(path)
    if not isinstance(package, dict):
        fail("package.json is not an object")
    if package.get("name") != PACKAGE or package.get("version") != VERSION:
        fail(f"expected {PACKAGE} {VERSION}, got {package.get('name')!r} {package.get('version')!r}")
    if package.get("license") != "MIT":
        fail(f"expected an MIT license, got {package.get('license')!r}")


def verify_groups(path):
    meta = load_json(path)
    groups = meta.get("groups") if isinstance(meta, dict) else None
    if not isinstance(groups, dict):
        fail("meta/groups.json has no groups object")
    for number, key in EXPECTED_GROUPS.items():
        if groups.get(str(number)) != key:
            fail(f"group {number} is {groups.get(str(number))!r}, expected {key!r}")


def unicode_form(emoji, presentation, where):
    """Unicode's fully-qualified form (emoji-test.txt), which is what Apple's keyboard inserts.

    Emojibase's `emoji` adds U+FE0F to every character that has a variation sequence, even ones
    that already default to emoji presentation (type 1), e.g. 👍 becomes 👍 + FE0F. Unicode lists
    those bare, as do Emojibase's own skin variants, so the extra selector is dropped. Text-default
    characters (type 0, e.g. ❤️) keep it. Checked against Unicode 17.0 emoji-test.txt: this gives the
    fully-qualified form for every emoji and skin written.
    """
    if presentation not in (0, 1):
        fail(f"bad type {presentation!r} in {where}")
    if presentation == 1 and len(emoji) == 2 and emoji[1] == "️":
        return emoji[0]
    return emoji


def skin_variants(item, where):
    """The 5 single-tone variants in tone order, or [] when any skin is multi-tone (Ruling M3-R2)."""
    skins = item.get("skins")
    if skins is None:
        return []
    if not isinstance(skins, list) or not skins:
        fail(f"bad skins in {where}")
    by_tone = {}
    for skin in skins:
        if not isinstance(skin, dict):
            fail(f"bad skin entry in {where}")
        tone = skin.get("tone")
        if isinstance(tone, list):
            return []
        if not is_int(tone) or not 1 <= tone <= 5 or tone in by_tone:
            fail(f"bad skin tone {tone!r} in {where}")
        by_tone[tone] = checked_emoji(skin.get("emoji"), where)
    if sorted(by_tone) != [1, 2, 3, 4, 5]:
        fail(f"expected tones 1-5 in {where}, got {sorted(by_tone)}")
    return [by_tone[tone] for tone in range(1, 6)]


def build(data):
    if not isinstance(data, list):
        fail("data.json is not a list")
    by_group = {}
    skipped_no_group = 0
    seen = set()
    for index, item in enumerate(data):
        if not isinstance(item, dict):
            fail(f"item {index} is not an object")
        where = f"item {index} ({item.get('hexcode')!r})"
        group = item.get("group")
        if group is None:
            skipped_no_group += 1
            continue
        if not is_int(group) or group not in EXPECTED_GROUPS:
            fail(f"bad group {group!r} in {where}")
        emoji = unicode_form(checked_emoji(item.get("emoji"), where), item.get("type"), where)
        order = item.get("order")
        version = item.get("version")
        if not is_int(order):
            fail(f"bad order {order!r} in {where}")
        if not is_number(version) or not 0 <= version < 100:
            fail(f"bad version {version!r} in {where}")
        entry = {"e": emoji, "v": float(version)}
        skins = skin_variants(item, where)
        if skins:
            entry["s"] = skins
        for variant in [emoji] + skins:
            if variant in seen:
                fail(f"duplicate emoji {variant!r} in {where}")
            seen.add(variant)
        by_group.setdefault(group, []).append((order, entry))

    categories = []
    for cat_id, name, icon, groups in CATEGORIES:
        emoji = []
        for group in groups:
            emoji.extend(entry for _, entry in sorted(by_group.get(group, []), key=lambda pair: pair[0]))
        if not emoji:
            fail(f"category {cat_id} is empty")
        categories.append({"id": cat_id, "name": name, "icon": icon, "emoji": emoji})
    return categories, skipped_no_group, len(by_group.get(2, []))


def dumps(value):
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"))


def render(categories):
    """Compact JSON with one emoji per line; deterministic for the same input."""
    lines = ["{" + dumps("source") + ":" + dumps(f"{PACKAGE} {VERSION}") + ","
             + dumps("recentName") + ":" + dumps(RECENT_NAME) + ","
             + dumps("categories") + ":["]
    for c_index, category in enumerate(categories):
        head = {k: category[k] for k in ("id", "name", "icon")}
        lines.append(dumps(head)[:-1] + "," + dumps("emoji") + ":[")
        items = category["emoji"]
        for i_index, entry in enumerate(items):
            lines.append(dumps(entry) + ("," if i_index < len(items) - 1 else ""))
        lines.append("]}" + ("," if c_index < len(categories) - 1 else ""))
    lines.append("]}")
    return "\n".join(lines) + "\n"


def main():
    refresh = "--refresh" in sys.argv[1:]
    os.makedirs(SRC_DIR, exist_ok=True)
    paths = {name: download(name, url, refresh) for name, url in SOURCES.items()}
    verify_package(paths["package.json"])
    verify_groups(paths["groups.json"])

    categories, skipped_no_group, components = build(load_json(paths["data.json"]))
    text = render(categories)
    expected = {"source": f"{PACKAGE} {VERSION}", "recentName": RECENT_NAME, "categories": categories}
    if json.loads(text) != expected:
        fail("rendered JSON does not round-trip")

    os.makedirs(os.path.dirname(OUT_PATH), exist_ok=True)
    with open(OUT_PATH, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)

    total = 0
    with_skins = 0
    for category in categories:
        count = len(category["emoji"])
        total += count
        with_skins += sum(1 for entry in category["emoji"] if "s" in entry)
        print(f"{category['id']:<16} {count:>5}")
    print(f"{'total':<16} {total:>5}  ({with_skins} with skin tones; "
          f"{components} components and {skipped_no_group} ungrouped left out)")
    print(f"wrote {os.path.relpath(OUT_PATH, ROOT)}: {len(text.encode('utf-8'))} bytes")


if __name__ == "__main__":
    main()
