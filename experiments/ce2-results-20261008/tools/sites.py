#!/usr/bin/env python3
"""Per-site bytes moved (VP3's patterns, ce.py) summed over the primary cells of each corpus.

  sites.py TAG [--against TAG] [--corpus lox|eda|parity|rows] [--top N] [--match SUBSTR]
"""
import argparse, collections, pathlib, sys
sys.path.insert(0, str(pathlib.Path(__file__).parent))
import ce


def site_totals(tag):
    out = collections.defaultdict(collections.Counter)
    for label in ce.primary_labels():
        data = ce.load_counts(ce.raw_dir(tag), label)
        if data is None:
            continue
        corpus = {"row": "rows"}.get(ce.corpus_of(label), ce.corpus_of(label))
        for s in data["sites"]:
            p = ce.pattern(s)
            if p is None:
                continue
            moved = s["extra"] if s["kind"] == "list_push" else s["bytes"]
            if moved:
                key = (p, pathlib.Path(s["path"]).name, s["line"], s["detail"], s["function"])
                out[corpus][key] += moved
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("tag")
    ap.add_argument("--against")
    ap.add_argument("--corpus")
    ap.add_argument("--top", type=int, default=25)
    ap.add_argument("--match")
    a = ap.parse_args()
    after = site_totals(a.tag)
    before = site_totals(a.against) if a.against else None
    for corpus in ("lox", "eda", "parity", "rows"):
        if a.corpus and corpus != a.corpus:
            continue
        keys = set(after[corpus]) | (set(before[corpus]) if before else set())
        rows = []
        for k in keys:
            if a.match and a.match not in " ".join(map(str, k)):
                continue
            x = after[corpus].get(k, 0)
            b = before[corpus].get(k, 0) if before else 0
            rows.append((max(x, b), k, b, x))
        rows.sort(reverse=True)
        print(f"== {corpus}: total after {ce.human(sum(after[corpus].values()))}" + (f" before {ce.human(sum(before[corpus].values()))}" if before else ""))
        for _, k, b, x in rows[: a.top]:
            p, f, line, detail, fn = k
            ch = f"{100 * (x - b) / b:+.1f}%" if b else "new"
            print(f"  {p:4} {f}:{line} {detail:18} {fn:40} " + (f"{ce.human(b):>10} -> " if before else "") + f"{ce.human(x):>10}" + (f"  {ch}" if before else ""))


if __name__ == "__main__":
    main()
