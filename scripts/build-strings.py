#!/usr/bin/env python3
# allow-python: builds a JSON string catalog from a table, which no CLI one-liner does.
"""Builds Koprik/Resources/Localizable.xcstrings from scripts/translations.tsv.

Each line of the table is: English key <TAB> Uzbek <TAB> Russian.
The English text is the key used in the Swift source. Keys missing from the
table stay in English at run time.

Usage: python3 scripts/build-strings.py [keys.txt]
With a key list (one English string per line), reports keys that have no
translation and translations whose key no longer exists.
"""
import json
import pathlib
import sys

root = pathlib.Path(__file__).resolve().parent.parent
table = root / "scripts" / "translations.tsv"
catalog = root / "Koprik" / "Resources" / "Localizable.xcstrings"

strings = {}
for number, line in enumerate(table.read_text(encoding="utf-8").splitlines(), start=1):
    if not line.strip():
        continue
    parts = line.split("\t")
    if len(parts) != 3:
        sys.exit(f"{table.name}:{number}: expected 3 tab-separated columns, found {len(parts)}")
    key, uzbek, russian = parts
    strings[key] = {
        "localizations": {
            "uz": {"stringUnit": {"state": "translated", "value": uzbek}},
            "ru": {"stringUnit": {"state": "translated", "value": russian}},
        }
    }

document = {"sourceLanguage": "en", "strings": dict(sorted(strings.items())), "version": "1.0"}
catalog.write_text(json.dumps(document, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(f"wrote {len(strings)} strings to {catalog.relative_to(root)}")

if len(sys.argv) > 1:
    keys = {line for line in pathlib.Path(sys.argv[1]).read_text(encoding="utf-8").splitlines() if line}
    for key in sorted(keys - strings.keys()):
        print(f"untranslated: {key}")
    for key in sorted(strings.keys() - keys):
        print(f"unused: {key}")
