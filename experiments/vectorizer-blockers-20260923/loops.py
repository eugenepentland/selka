#!/usr/bin/env python3
"""loops.py FILE.ll FUNCREGEX [PATTERN] — print the innermost natural loops of a function.

Each loop is printed with its blocks and instructions (metadata stripped); with
PATTERN only loops containing a line matching it are printed.  A one-line
summary per loop counts calls, loads, stores, conditional branches and exits.
"""
import re
import sys

sys.path.insert(0, str(__import__("pathlib").Path(__file__).resolve().parents[1] / "llvm-backend"))
from llvm_emit import Dominators  # noqa: E402

path, fpat = sys.argv[1], re.compile(sys.argv[2])
pattern = re.compile(sys.argv[3]) if len(sys.argv) > 3 else None
body, on = [], False
for line in open(path):
    if line.startswith("define"):
        on = bool(fpat.search(line))
        if on:
            body = [line]
            continue
    if on:
        body.append(line)
        if line.startswith("}"):
            break

blocks, order, cur = {}, [], None
for line in body[1:]:
    m = re.match(r"^([\w.$-]+):", line)
    if m:
        cur = m.group(1)
        blocks[cur] = []
        order.append(cur)
        continue
    if line.startswith("}"):
        break
    if cur is None:
        cur = "entry"
        blocks[cur] = []
        order.append(cur)
    if not line.strip():
        continue
    s = re.sub(r", !(dbg|alias\.scope|noalias|tbaa|llvm\.loop|range|nonnull|noundef) ![0-9]+", "", line.rstrip())
    blocks[cur].append(s)

edges = {}
for b in order:
    joined = " ".join(blocks[b])
    at = max(joined.rfind(" br "), joined.rfind(" switch "))
    edges[b] = re.findall(r"label %([\w.$-]+)", joined[at:]) if at >= 0 else []
dom = Dominators(order[0], edges)
preds = {b: [] for b in order}
for b in order:
    for s in edges[b]:
        preds.setdefault(s, []).append(b)
loops = {}
for b in order:
    for s in edges[b]:
        if dom.dominates(s, b):
            body_set, work = {s, b}, [b]
            while work:
                x = work.pop()
                for p in preds.get(x, []):
                    if p not in body_set and x != s:
                        body_set.add(p)
                        work.append(p)
            loops.setdefault(s, set()).update(body_set)
inner = {h: bs for h, bs in loops.items()
         if not any(h2 != h and h2 in bs for h2 in loops)}
for h, bs in sorted(inner.items(), key=lambda kv: order.index(kv[0])):
    text = [l for b in order if b in bs for l in [b + ":"] + blocks[b]]
    if pattern and not any(pattern.search(l) for l in text):
        continue
    calls = sum(1 for l in text if re.search(r"\bcall\b", l) and "@llvm." not in l)
    intr = sum(1 for l in text if "call" in l and "@llvm." in l)
    loads = sum(1 for l in text if " load " in l)
    stores = sum(1 for l in text if l.strip().startswith("store"))
    cbr = sum(1 for l in text if re.search(r"br i1", l))
    exits = sorted({s for b in bs for s in edges[b] if s not in bs})
    print(f"=== loop {h}: {len(bs)} blocks, {len(text)} lines, calls={calls} intrinsics={intr} "
          f"loads={loads} stores={stores} condbr={cbr} exits={exits}")
    if "-q" not in sys.argv:
        print("\n".join(text))
