#!/usr/bin/env python3
"""Builds the keyboard's emoji index from Unicode data and Typr's own alias list.

    build.py SOURCES_DIR OUTPUT

SOURCES_DIR holds, downloaded beforehand (this script never uses the network):
- emoji-test.txt, Unicode emoji 15.1
  https://www.unicode.org/Public/emoji/15.1/emoji-test.txt
- annotations-de.xml, annotations-en.xml, annotationsDerived-de.xml, annotationsDerived-en.xml,
  CLDR release-47 common/annotations/<lang>.xml and common/annotationsDerived/<lang>.xml
  https://github.com/unicode-org/cldr/tree/release-47

Output lines (tab-separated):
  E  emoji  category          the panel's catalog, in emoji-test.txt order
  W  word   entry,entry,...   folded word to at most three entries, best first, sorted by UTF-8

A word lists an emoji only when it is strong enough for the suggestion bar: an alias from
aliases.txt, the emoji's one-word German or English name, or a one-word keyword that names at
most three emoji. Words share EmojiIndex.fold's folding.
"""

import hashlib
import pathlib
import sys
import unicodedata
import xml.etree.ElementTree as ET

HERE = pathlib.Path(__file__).resolve().parent
SHA256 = {
    "emoji-test.txt": "d876ee249aa28eaa76cfa6dfaa702847a8d13b062aa488d465d0395ee8137ed9",
    "annotations-de.xml": "a36c3d4e0d21457035b4950ad325b678ec9116ca97ac71813eb18d82d696b895",
    "annotations-en.xml": "b33e2e88ed2fb8c438c1efa9747b9d845e8d7d74ef0c32342a805c0f46fdd7ec",
    "annotationsDerived-de.xml": "d66c8252841ce9f78221738c36ea76661b19306fd7289ccabcb99fdd5f14c42a",
    "annotationsDerived-en.xml": "4f93a6780bcf83f85bf727af80ca18525b290910c378da169d5cb2ce938d765d",
}
CATEGORIES = {
    "Smileys & Emotion": 0,
    "People & Body": 0,
    "Animals & Nature": 1,
    "Food & Drink": 2,
    "Activities": 3,
    "Travel & Places": 4,
    "Objects": 5,
    "Symbols": 6,
    "Flags": 7,
}
SKIN_TONES = set(range(0x1F3FB, 0x1F400))
MAX_HITS = 3
STOPWORDS = set("""
und oder mit der die das den dem des ein eine einer eines für von zu im in am an auf aus bei nach
the and with for from into onto off out over
""".split())


def fold(text):
    """NFD, combining marks dropped, lowercased, curly apostrophes straightened."""
    text = unicodedata.normalize("NFD", text.replace("\u2019", "'"))
    return "".join(c for c in text if not unicodedata.combining(c)).lower()


def words(text):
    out, word = [], ""
    for c in fold(text):
        if c.isalnum():
            word += c
        else:
            if word:
                out.append(word)
            word = ""
    if word:
        out.append(word)
    return out


def catalog(path):
    entries, group = [], None
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.startswith("# group:"):
            group = line.split(":", 1)[1].strip()
            continue
        if not line or line.startswith("#") or "; fully-qualified" not in line:
            continue
        if group not in CATEGORIES:
            continue
        points = [int(p, 16) for p in line.split(";")[0].split()]
        if SKIN_TONES & set(points):
            continue
        entries.append(("".join(map(chr, points)), CATEGORIES[group]))
    return entries


def annotations(paths):
    """CLDR key (emoji without FE0F) to (names, keywords)."""
    out = {}
    for path in paths:
        for node in ET.parse(path).getroot().iter("annotation"):
            key, text = node.get("cp"), node.text or ""
            names, keywords = out.setdefault(key, ([], []))
            if node.get("type") == "tts":
                # Flags read "Flagge: Deutschland"; the country is the name.
                names.append(text.split(": ", 1)[1] if ": " in text else text)
            else:
                keywords.extend(part.strip() for part in text.split("|"))
    return out


def aliases(path):
    out = []
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.split("#", 1)[0].strip()
        if line:
            word, *emoji = line.split()
            out.append((fold(word), emoji))
    return out


def build(sources, alias_path):
    entries = catalog(sources / "emoji-test.txt")
    index = {emoji: i for i, (emoji, _) in enumerate(entries)}
    notes = annotations([sources / f"{kind}-{lang}.xml"
                         for kind in ("annotations", "annotationsDerived") for lang in ("de", "en")])

    # word -> {entry: rank}; lower ranks first.
    ranked = {}

    def add(word, entry, rank):
        if len(word) < 2 or word in STOPWORDS:
            return
        hits = ranked.setdefault(word, {})
        hits[entry] = min(rank, hits.get(entry, rank))

    for position, (word, emoji) in enumerate(aliases(alias_path)):
        for order, item in enumerate(emoji):
            if item not in index:
                raise SystemExit(f"alias {word}: {item} is not in the catalog")
            add(word, index[item], position * 0.0001 + order * 0.00001)

    keyword_hits = {}
    for entry, (emoji, _) in enumerate(entries):
        names, keywords = notes.get(emoji.replace("\ufe0f", ""), ([], []))
        for name in names:
            parts = words(name)
            if len(parts) == 1:
                add(parts[0], entry, 1)
        for keyword in keywords:
            parts = words(keyword)
            if len(parts) == 1 and len(parts[0]) >= 3:
                keyword_hits.setdefault(parts[0], set()).add(entry)
    for word, hits in keyword_hits.items():
        if len(hits) <= MAX_HITS:
            for entry in hits:
                add(word, entry, 2)

    lines = [
        "# Generated by ios/tools/emoji/build.py; do not edit.",
        "# Unicode emoji-test.txt 15.1 and CLDR 47 annotations de/en (Unicode License v3,",
        "# LICENSE-Unicode.txt), and Typr's own aliases (ios/tools/emoji/aliases.txt).",
    ]
    lines += [f"E\t{emoji}\t{category}" for emoji, category in entries]
    for word in sorted(ranked, key=lambda w: w.encode("utf-8")):
        best = sorted(ranked[word].items(), key=lambda item: (item[1], item[0]))[:MAX_HITS]
        lines.append(f"W\t{word}\t" + ",".join(str(entry) for entry, _ in best))
    return "\n".join(lines) + "\n"


def main():
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    sources = pathlib.Path(sys.argv[1])
    for name, digest in SHA256.items():
        actual = hashlib.sha256((sources / name).read_bytes()).hexdigest()
        if actual != digest:
            raise SystemExit(f"{name}: SHA-256 {actual}, expected {digest}")
    pathlib.Path(sys.argv[2]).write_text(build(sources, HERE / "aliases.txt"), encoding="utf-8")


if __name__ == "__main__":
    main()
