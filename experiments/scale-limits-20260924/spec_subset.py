"""Write SPEC.md as the base plus only the named tags' current bullets.

usage: spec_subset.py BASE CURRENT OUT TAG [TAG...]
A tag present in BASE takes its CURRENT text; a tag new in CURRENT is inserted after
the bullet that precedes it in CURRENT. Everything else keeps BASE's text.
"""
import sys
from pathlib import Path

base_path, current_path, out_path, *tags = sys.argv[1:]
base = Path(base_path).read_text().splitlines()
current = Path(current_path).read_text().splitlines()


def tag_of(line):
    return line[3:].split("]")[0] if line.startswith("- [") else None


current_by_tag = {tag_of(l): l for l in current if tag_of(l)}
previous = {}
last = None
for line in current:
    t = tag_of(line)
    if t:
        previous[t] = last
        last = t
out = [current_by_tag[tag_of(l)] if tag_of(l) in tags else l for l in base]
base_tags = {tag_of(l) for l in base}
for t in tags:
    if t in base_tags:
        continue
    anchor = previous[t]
    index = next(i for i, l in enumerate(out) if tag_of(l) == anchor)
    out.insert(index + 1, current_by_tag[t])
Path(out_path).write_text("\n".join(out) + "\n")
