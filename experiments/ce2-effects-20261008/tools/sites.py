#!/usr/bin/env python3
"""CE2-A site report: per-pattern bytes moved per corpus for TAG against the CE-X final (`cex`),
the CE2-A target sites, and the top sites still copying.

  sites.py TAG [--against cex] [--corpora lox,eda,parity,rows] [--top 10]"""
import argparse, collections, json, pathlib, sys
sys.path.insert(0, str(pathlib.Path(__file__).parent))
import ce

TARGETS = [("P4", "vm.my", 433), ("P4", "vm.my", 534), ("P2", "vm.my", 254), ("P2", "interpreter.my", 667),
           ("P2", "heap.my", 106), ("P4", "vm.my", 135), ("P4", "heap.my", 124), ("P4", "heap.my", 210)]


def site_bytes(s):
    return s["extra"] if s["kind"] == "list_push" else s["bytes"]


def collect(tag, corpora):
    pats = collections.defaultdict(collections.Counter)
    sites = collections.defaultdict(collections.Counter)
    for label in ce.primary_labels():
        corpus = {"row": "rows"}.get(ce.corpus_of(label), ce.corpus_of(label))
        if corpus not in corpora:
            continue
        data = ce.load_counts(ce.raw_dir(tag), label)
        if data is None:
            continue
        pats[corpus].update(ce.by_pattern(data))
        for s in data["sites"]:
            name = ce.pattern(s)
            if name is None or not site_bytes(s):
                continue
            sites[corpus][(name, s["path"].split("/")[-1], s["line"], s["detail"], s["function"])] += site_bytes(s)
    return pats, sites


def main():
    p = argparse.ArgumentParser()
    p.add_argument("tag")
    p.add_argument("--against", default="cex")
    p.add_argument("--corpora", default="lox,eda,parity,rows")
    p.add_argument("--top", type=int, default=10)
    p.add_argument("--json")
    a = p.parse_args()
    corpora = a.corpora.split(",")
    after, after_sites = collect(a.tag, corpora)
    before, before_sites = collect(a.against, corpora)
    out = {"tag": a.tag, "against": a.against, "patterns": {}, "targets": [], "top": {}}
    for corpus in corpora:
        if corpus not in after:
            continue
        print(f"\n{corpus}: | pattern | {a.against} | {a.tag} | change |")
        names = sorted(set(after[corpus]) | set(before[corpus]), key=lambda n: (len(n), n))
        rows = {}
        for name in names + ["P2+P4", "all"]:
            if name == "P2+P4":
                b = before[corpus]["P2"] + before[corpus]["P4"]
                x = after[corpus]["P2"] + after[corpus]["P4"]
            elif name == "all":
                b, x = sum(before[corpus].values()), sum(after[corpus].values())
            else:
                b, x = before[corpus][name], after[corpus][name]
            rows[name] = [b, x]
            ch = f"{100 * (x - b) / b:+.1f}%" if b else ("new" if x else "")
            flag = "  <-- UP" if x > b and name not in ("all",) else ""
            print(f"| {name} | {ce.human(b)} | {ce.human(x)} | {ch} |{flag}")
        out["patterns"][corpus] = rows
    if "lox" in corpora:
        print("\ntargets (lox, all functions):")
        for pat, path, line in TARGETS:
            b = sum(v for k, v in before_sites["lox"].items() if k[0] == pat and k[1] == path and k[2] == line)
            x = sum(v for k, v in after_sites["lox"].items() if k[0] == pat and k[1] == path and k[2] == line)
            ch = f"{100 * (x - b) / b:+.1f}%" if b else ""
            print(f"  {pat} {path}:{line}  {ce.human(b)} -> {ce.human(x)} {ch}")
            out["targets"].append({"pattern": pat, "file": path, "line": line, "before": b, "after": x})
    for corpus in corpora:
        if corpus not in after_sites:
            continue
        print(f"\ntop {a.top} sites still copying ({corpus}):")
        top = []
        for k, v in after_sites[corpus].most_common(a.top):
            b = before_sites[corpus].get(k, 0)
            print(f"  {ce.human(v):>10}  (was {ce.human(b):>10})  {k[0]} {k[1]}:{k[2]} {k[3]} in {k[4]}")
            top.append({"pattern": k[0], "file": k[1], "line": k[2], "detail": k[3], "function": k[4], "bytes": v, "before": b})
        out["top"][corpus] = top
    if a.json:
        pathlib.Path(a.json).write_text(json.dumps(out, indent=1) + "\n")


if __name__ == "__main__":
    main()
