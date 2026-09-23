#!/usr/bin/env python3
"""remarks.py DIR... — summarize loop-vectorize and LICM remarks in guest code (entry_run and
myl_f_*) of each LTO remarks file: vectorized loops, and missed reasons with counts."""
import collections
import re
import sys

import glob

for directory in sys.argv[1:]:
    name = directory.rstrip("/").split("/")[-1]
    text = open(f"{directory}/rem.yaml").read()
    for unit in sorted(glob.glob(f"{directory}/unit-remarks/*.yaml")):
        text += "\n" + open(unit).read()
    passed = 0
    reasons = collections.Counter()
    licm = collections.Counter()
    for doc in text.split("\n--- ")[1:] if not text.startswith("--- ") else text.split("--- ")[1:]:
        kind = doc.split("\n", 1)[0].strip()
        fn = re.search(r"\nFunction:\s+(\S+)", doc)
        if not fn or not (fn.group(1) == "entry_run" or fn.group(1).startswith("myl_f_")):
            continue
        pass_name = re.search(r"\nPass:\s+(\S+)", doc).group(1)
        remark = re.search(r"\nName:\s+(\S+)", doc).group(1)
        if pass_name == "loop-vectorize":
            if kind == "!Passed":
                passed += 1
            elif kind == "!Analysis":
                reasons[remark] += 1
        elif pass_name == "licm" and kind == "!Missed":
            licm[remark] += 1
    top = ", ".join(f"{r} {c}" for r, c in reasons.most_common(6))
    print(f"{name:16s} vectorized={passed} missed: {top} | licm-missed: {dict(licm)}")
