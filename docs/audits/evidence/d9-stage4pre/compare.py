#!/usr/bin/env python3
"""Compare the two pinned schematic ownership explanations.

Run from any directory: python3 docs/audits/evidence/d9-stage4pre/compare.py
"""

import collections
import gzip
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent


def read(name):
    with gzip.open(HERE / name, "rt", encoding="utf-8") as stream:
        return {item["function"]: item for item in map(json.loads, stream)}


logical = read("schematic-logical-call-source.jsonl.gz")
physical = read("schematic-physical-call-source.jsonl.gz")
assert logical.keys() == physical.keys()
changed = collections.Counter()
sites = []
copy_changes = collections.Counter()
for name in logical:
    old = logical[name]
    new = physical[name]
    assert len(old["transfers"]) == len(new["transfers"])
    for before, after in zip(old["transfers"], new["transfers"]):
        assert (before["pc"], before["kind"]) == (after["pc"], after["kind"])
        if before["class"] != after["class"]:
            changed[(before["kind"], before["class"], after["class"])] += 1
            sites.append({
                "function": name,
                "pc": before["pc"],
                "kind": before["kind"],
                "from": before["class"],
                "to": after["class"],
                "source": after["source"],
            })
    assert len(old.get("copies", [])) == len(new.get("copies", []))
    for before, after in zip(old.get("copies", []), new.get("copies", [])):
        assert (before["pc"], before["site"]) == (after["pc"], after["site"])
        if before["copy"] != after["copy"]:
            copy_changes[(before["site"], before["copy"], after["copy"])] += 1

summary = {
    "functions": len(logical),
    "transfer_changes": [
        {"kind": key[0], "from": key[1], "to": key[2], "sites": count}
        for key, count in sorted(changed.items())
    ],
    "value_copy_changes": [
        {"site": key[0], "from": key[1], "to": key[2], "sites": count}
        for key, count in sorted(copy_changes.items())
    ],
}
print(json.dumps(sites if "--sites" in sys.argv[1:] else summary, indent=2))
