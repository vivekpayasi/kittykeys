#!/usr/bin/env python3
"""Builds the emoji panel's data files from Emojibase (MIT).

Downloads emojibase-data@17.0.0 into build/emoji-src/ (gitignored) and writes, under
Packages/CatkeysCore/Sources/KeyboardCore/Emoji/, these committed files: emoji.json (the panel's emoji),
EmojiKeywords/en.json (the English search words for each of them) and EmojiKeywords/popular.json (catkeys'
hand-curated choice of commonly used emoji, informed by Unicode's published emoji frequency ranking, which search
ranks first among equal matches). The keyboard reads every
file in EmojiKeywords/, so another language's words (Hinglish next) can be added there as data alone.

The downloaded files are untrusted data: they are only ever parsed with json.load and
every field used is type-checked. Standard library only. Run from anywhere:

    python3 -I scripts/make-emoji-data.py            # reuses files already in build/emoji-src/
    python3 -I scripts/make-emoji-data.py --refresh  # downloads them again

Output (UTF-8, one emoji per line so diffs stay readable, otherwise compact):
    emoji.json:
    {"source": "emojibase-data 17.0.0", "recentName": "Recent", "recentIcon": "clock",
     "categories": [{"id", "name", "icon", "emoji": [{"e", "v", "s"?}]}]}
    EmojiKeywords/en.json, keyed by the same base strings as emoji.json, in the same order:
    {"source": "emojibase-data 17.0.0", "language": "en", "stopwords": [...],
     "keywords": {"<base emoji>": [[label words], [tag words not among the label words]]}}
    EmojiKeywords/popular.json, most used first:
    {"source": "catkeys' hand-curated choice of ...", "popular": ["<base emoji>", ...]}
"""

import json
import os
import ssl
import sys
import unicodedata
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
OUT_DIR = os.path.join(ROOT, "Packages", "CatkeysCore", "Sources", "KeyboardCore", "Emoji")
OUT_PATH = os.path.join(OUT_DIR, "emoji.json")
KEYWORDS_DIR = os.path.join(OUT_DIR, "EmojiKeywords")
KEYWORDS_PATH = os.path.join(KEYWORDS_DIR, "en.json")
POPULAR_PATH = os.path.join(KEYWORDS_DIR, "popular.json")

# The language of Emojibase's en/data.json labels and tags. Other languages (Hinglish first) come later as more data.
KEYWORDS_LANGUAGE = "en"
# Shorter words, such as the "a" in "a+" or the "t" in "T-Rex", match nearly everything as a prefix, so they are left out.
MIN_KEYWORD_LENGTH = 2
# English words that carry no meaning of their own in a name such as "face with tears of joy". They are left out of
# the label words, so they never make a name match (a tag that holds one keeps it), and en.json lists them so that
# search treats them as optional in a query: they exclude nothing and only lift the emoji that match them.
EN_STOPWORDS = {"with", "of", "on", "the", "a", "an", "and", "in", "at", "for", "to", "from", "by"}

# Commonly used emoji, most used first: catkeys' hand-curated choice of commonly used emoji, informed by Unicode's
# published emoji frequency ranking (not a copy of it). Search ranks them first among otherwise equal matches. Each is matched to emoji.json ignoring U+FE0F and skin tones, so this list is written without
# variation selectors (nothing invisible), and popular.json gets emoji.json's own spelling.
POPULAR = (
    "😂 ❤ 🤣 👍 😭 🙏 😘 🥰 😍 😊 🎉 😁 💕 🥺 😅 🔥 ☺ 🤦 🤷 🙄 "
    "😆 🤗 😉 🤔 👏 🙂 😳 🥳 😎 👌 😔 💪 ✨ 👀 😋 😏 😢 💯 🌹 💙 "
    "😀 💜 😇 😜 😡 😱 🙌 🎂 👋 💔"
).split()
POPULAR_SOURCE = ("catkeys' hand-curated choice of commonly used emoji, "
                  "informed by Unicode's published emoji frequency ranking")

# How many single-character emoji lose a redundant U+FE0F in `unicode_form` for emojibase-data 17.0.0. A different
# count means the source changed: check the result against Unicode's emoji-test.txt again before updating it.
EXPECTED_NORMALISED = 152

# The Recent section: its display name and the SF Symbol for its tab.
RECENT_NAME = "Recent"
RECENT_ICON = "clock"

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
    characters (type 0, e.g. U+2764 red heart) keep it. Checked against Unicode 17.0 emoji-test.txt: this gives
    the fully-qualified form for every emoji and skin written.
    """
    if presentation not in (0, 1):
        fail(f"bad type {presentation!r} in {where}")
    if presentation == 1 and len(emoji) == 2 and emoji[1] == "\ufe0f":
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


# Characters that join the parts of one word, as in "T-Rex", "o’clock" and "U.S.". Any other character that isn't part
# of a word, such as a space, colon, en dash or quotation mark, only separates words.
JOINERS = "-\u2010'\u2019."


def is_word_character(ch):
    """Letters, digits and combining marks, in any script. Marks count so that scripts written with them, such as
    Devanagari, stay whole."""
    return unicodedata.category(ch)[0] in "LNM"


def runs(text, keep):
    """The longest stretches of `text` whose every character `keep` accepts, in order."""
    found = []
    current = ""
    for ch in text:
        if keep(ch):
            current += ch
        elif current:
            found.append(current)
            current = ""
    if current:
        found.append(current)
    return found


def plain_latin(word):
    """The word without its accents when that leaves plain ASCII, as "crepe" for "crêpe"; else None."""
    decomposed = unicodedata.normalize("NFKD", word)
    plain = "".join(ch for ch in decomposed if not unicodedata.combining(ch))
    return plain if plain.isascii() and plain != word else None


def search_words(text):
    """The search words in `text`, lowercased and NFC: the stretches of word characters.

    A word made of parts with joiners between them also gives its joined form ("t-rex" gives "rex" and "trex",
    "o’clock" gives "clock" and "oclock"), and an accented Latin word its plain form ("curaçao" gives "curacao"), since
    the keys type neither joiners nor accents easily. Words shorter than MIN_KEYWORD_LENGTH are left out.
    The order is the text's; repeats stay for the caller to drop.
    """
    text = unicodedata.normalize("NFC", text.lower())
    words = []
    for chunk in runs(text, lambda ch: is_word_character(ch) or ch in JOINERS):
        parts = runs(chunk, is_word_character)
        for form in parts + (["".join(parts)] if len(parts) > 1 else []):
            words.append(form)
            plain = plain_latin(form)
            if plain:
                words.append(plain)
    return [word for word in words if len(word) >= MIN_KEYWORD_LENGTH]


def keywords(item, where):
    """The emoji's search words: its label's words other than stopwords, then its tags' words that those lack, each
    without repeats."""
    label = item.get("label")
    tags = item.get("tags", [])
    if not isinstance(label, str) or not label.strip():
        fail(f"bad label {label!r} in {where}")
    if not isinstance(tags, list) or not all(isinstance(tag, str) for tag in tags):
        fail(f"bad tags in {where}")
    label_words = list(dict.fromkeys(word for word in search_words(label) if word not in EN_STOPWORDS))
    if not label_words:
        fail(f"label {label!r} gives no search words in {where}")
    taken = set(label_words)
    tag_words = list(dict.fromkeys(word for tag in tags for word in search_words(tag) if word not in taken))
    return [label_words, tag_words]


def build(data):
    if not isinstance(data, list):
        fail("data.json is not a list")
    by_group = {}
    skipped_no_group = 0
    normalised = 0
    seen = set()
    words_by_emoji = {}
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
        raw = checked_emoji(item.get("emoji"), where)
        emoji = unicode_form(raw, item.get("type"), where)
        if emoji != raw:
            normalised += 1
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
        words_by_emoji[emoji] = keywords(item, where)
        by_group.setdefault(group, []).append((order, entry))

    categories = []
    for cat_id, name, icon, groups in CATEGORIES:
        emoji = []
        for group in groups:
            emoji.extend(entry for _, entry in sorted(by_group.get(group, []), key=lambda pair: pair[0]))
        if not emoji:
            fail(f"category {cat_id} is empty")
        categories.append({"id": cat_id, "name": name, "icon": icon, "emoji": emoji})
    if normalised != EXPECTED_NORMALISED:
        fail(f"{normalised} emoji lost a redundant U+FE0F, expected {EXPECTED_NORMALISED}; check against emoji-test.txt")
    search = {entry["e"]: words_by_emoji[entry["e"]] for category in categories for entry in category["emoji"]}
    return categories, search, skipped_no_group, len(by_group.get(2, [])), normalised


def dumps(value):
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"))


def render(categories):
    """Compact JSON with one emoji per line; deterministic for the same input."""
    lines = ["{" + dumps("source") + ":" + dumps(f"{PACKAGE} {VERSION}") + ","
             + dumps("recentName") + ":" + dumps(RECENT_NAME) + ","
             + dumps("recentIcon") + ":" + dumps(RECENT_ICON) + ","
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


def render_keywords(search):
    """Compact JSON with one emoji per line, in the panel's order; deterministic for the same input."""
    lines = ["{" + dumps("source") + ":" + dumps(f"{PACKAGE} {VERSION}") + ","
             + dumps("language") + ":" + dumps(KEYWORDS_LANGUAGE) + ","
             + dumps("stopwords") + ":" + dumps(sorted(EN_STOPWORDS)) + ","
             + dumps("keywords") + ":{"]
    items = list(search.items())
    for index, (emoji, words) in enumerate(items):
        lines.append(dumps(emoji) + ":" + dumps(words) + ("," if index < len(items) - 1 else ""))
    lines.append("}}")
    return "\n".join(lines) + "\n"


def base_key(emoji):
    """The base emoji a spelling stands for: U+FE0F and the skin-tone modifiers removed, as EmojiPreferences.key."""
    key = "".join(ch for ch in emoji if ch != "\ufe0f" and not 0x1F3FB <= ord(ch) <= 0x1F3FF)
    return key or emoji


def popular_emoji(categories):
    """POPULAR in emoji.json's spelling. Fails unless each entry is exactly one of its emoji, listed once."""
    by_key = {}
    for category in categories:
        for entry in category["emoji"]:
            by_key.setdefault(base_key(entry["e"]), []).append(entry["e"])
    found = []
    for emoji in POPULAR:
        matches = by_key.get(base_key(emoji), [])
        if len(matches) != 1:
            fail(f"popular emoji {emoji!r} matches {len(matches)} emoji in emoji.json, expected 1")
        if matches[0] in found:
            fail(f"popular emoji {emoji!r} is listed twice")
        found.append(matches[0])
    return found


def render_popular(popular):
    """Compact JSON with one emoji per line, most used first."""
    lines = ["{" + dumps("source") + ":" + dumps(POPULAR_SOURCE) + "," + dumps("popular") + ":["]
    for index, emoji in enumerate(popular):
        lines.append(dumps(emoji) + ("," if index < len(popular) - 1 else ""))
    lines.append("]}")
    return "\n".join(lines) + "\n"


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)


def main():
    refresh = "--refresh" in sys.argv[1:]
    os.makedirs(SRC_DIR, exist_ok=True)
    paths = {name: download(name, url, refresh) for name, url in SOURCES.items()}
    verify_package(paths["package.json"])
    verify_groups(paths["groups.json"])

    categories, search, skipped_no_group, components, normalised = build(load_json(paths["data.json"]))
    text = render(categories)
    expected = {"source": f"{PACKAGE} {VERSION}", "recentName": RECENT_NAME, "recentIcon": RECENT_ICON,
                "categories": categories}
    if json.loads(text) != expected:
        fail("rendered JSON does not round-trip")
    keywords_text = render_keywords(search)
    expected_keywords = {"source": f"{PACKAGE} {VERSION}", "language": KEYWORDS_LANGUAGE,
                         "stopwords": sorted(EN_STOPWORDS), "keywords": search}
    if json.loads(keywords_text) != expected_keywords:
        fail("rendered keywords JSON does not round-trip")
    popular = popular_emoji(categories)
    popular_text = render_popular(popular)
    if json.loads(popular_text) != {"source": POPULAR_SOURCE, "popular": popular}:
        fail("rendered popular JSON does not round-trip")

    write(OUT_PATH, text)
    write(KEYWORDS_PATH, keywords_text)
    write(POPULAR_PATH, popular_text)

    total = 0
    with_skins = 0
    for category in categories:
        count = len(category["emoji"])
        total += count
        with_skins += sum(1 for entry in category["emoji"] if "s" in entry)
        print(f"{category['id']:<16} {count:>5}")
    print(f"{'total':<16} {total:>5}  ({with_skins} with skin tones; "
          f"{components} components and {skipped_no_group} ungrouped left out)")
    print(f"{normalised} emoji lost a redundant U+FE0F (fully-qualified form)")
    print(f"wrote {os.path.relpath(OUT_PATH, ROOT)}: {len(text.encode('utf-8'))} bytes")
    label_words = sum(len(words[0]) for words in search.values())
    tag_words = sum(len(words[1]) for words in search.values())
    distinct = len({word for words in search.values() for part in words for word in part})
    print(f"keywords: {len(search)} emoji, {label_words} label words and {tag_words} tag words, {distinct} distinct")
    print(f"wrote {os.path.relpath(KEYWORDS_PATH, ROOT)}: {len(keywords_text.encode('utf-8'))} bytes")
    print(f"wrote {os.path.relpath(POPULAR_PATH, ROOT)}: {len(popular)} emoji, "
          f"{len(popular_text.encode('utf-8'))} bytes")


if __name__ == "__main__":
    main()
