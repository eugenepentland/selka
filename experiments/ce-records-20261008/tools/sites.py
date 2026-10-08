#!/usr/bin/env python3
"""Top record-copy sites of one tag's counts: `sites.py TAG CORPUS [PATTERN...]`."""
import collections, gzip, json, pathlib, sys
sys.path.insert(0, str(pathlib.Path(__file__).parent))
import ce
tag, corpus, *patterns = sys.argv[1:]
directory = ce.VP3 / "raw" if tag == "vp3" else ce.AREA / "raw" / tag
table = collections.Counter()
counts = collections.Counter()
for label in ce.primary_labels():
    if not label.startswith(corpus):
        continue
    data = ce.load_counts(directory, label)
    if data is None:
        continue
    for site in data["sites"]:
        name = ce.pattern(site)
        if name is None or (patterns and name not in patterns):
            continue
        moved = site["extra"] if site["kind"] == "list_push" else site["bytes"]
        key = (name, site["function"], site["path"].split("/")[-1], site["line"], site["detail"])
        table[key] += moved
        counts[key] += site["count"]
for key, moved in table.most_common(25):
    print(f"{ce.human(moved):>10}  {ce.human(counts[key]):>8}x  {key}")
