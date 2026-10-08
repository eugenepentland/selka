#!/usr/bin/env python3
"""CE2-B tables: bytes moved per pattern and corpus (CE-X final `cex` against a tag), the target
sites, the highlights and the top sites still copying, as Markdown and JSON.

  report_tables.py TAG [--json OUT]
"""
import argparse, collections, json, pathlib, sys
sys.path.insert(0, str(pathlib.Path(__file__).parent))
import ce
import sites as sitemod

PATTERNS = ["P1", "P2", "P7", "P8", "P3", "P4", "P5", "P6", "P9", "P13", "P14", "P10", "P11", "P12"]
TARGETS = [
    ("lox", "P7", "vm.my", 264), ("lox", "P7", "vm.my", 268), ("lox", "P7", "interpreter.my", 668),
    ("eda", "P7", "sexpr_tokenizer.my", None), ("eda", "P7", "sexpr_parser.my", None),
    ("lox", "P3", "heap.my", 361), ("lox", "P3", "heap.my", 362),
    ("rows", "P1", "row_record_pass.my", 48), ("eda", "P6", "sexpr_parser.my", 225),
    ("lox", "P9", "table.my", 84),
]


def pct(b, a):
    return f"{100 * (a - b) / b:+.1f}%" if b else ("new" if a else "")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("tag")
    ap.add_argument("--json")
    a = ap.parse_args()
    before, _ = ce.totals(ce.raw_dir("cex"))
    after, _ = ce.totals(ce.raw_dir(a.tag))
    out = {"tag": a.tag, "corpora": {}, "targets": [], "top": {}, "highlights": {}}
    print(f"## Bytes moved per pattern: CE-X final -> {a.tag}\n")
    for corpus in ("lox", "eda", "parity", "rows"):
        print(f"**{corpus}**\n\n| pattern | CE-X final | {a.tag} | change |\n|---|---:|---:|---:|")
        rows = {}
        for p in PATTERNS:
            b, x = before[corpus].get(p, 0), after[corpus].get(p, 0)
            if not b and not x:
                continue
            rows[p] = [b, x]
            print(f"| {p} | {ce.human(b)} | {ce.human(x)} | {pct(b, x)} |")
        tb, ta = sum(before[corpus].values()), sum(after[corpus].values())
        print(f"| **all** | {ce.human(tb)} | {ce.human(ta)} | {pct(tb, ta)} |\n")
        out["corpora"][corpus] = {"patterns": rows, "total": [tb, ta]}
    sb, sa = sitemod.site_totals("cex"), sitemod.site_totals(a.tag)
    print("## Target sites\n\n| corpus | pattern | site | CE-X final | after | change |\n|---|---|---|---:|---:|---:|")
    for corpus, p, f, line in TARGETS:
        b = sum(v for k, v in sb[corpus].items() if k[0] == p and k[1] == f and (line is None or k[2] == line))
        x = sum(v for k, v in sa[corpus].items() if k[0] == p and k[1] == f and (line is None or k[2] == line))
        where = f"{f}:{line}" if line else f"{f} (all)"
        print(f"| {corpus} | {p} | `{where}` | {ce.human(b)} | {ce.human(x)} | {pct(b, x)} |")
        out["targets"].append({"corpus": corpus, "pattern": p, "site": where, "before": b, "after": x})
    # highlights
    flat_b = sum(ce.by_pattern(ce.load_counts(ce.raw_dir("cex"), "eda-rds3+flat")).values())
    flat_a = sum(ce.by_pattern(ce.load_counts(ce.raw_dir(a.tag), "eda-rds3+flat")).values())
    rp_b = sum(ce.by_pattern(ce.load_counts(ce.raw_dir("cex"), "row-record_pass")).values())
    rp_a = sum(ce.by_pattern(ce.load_counts(ce.raw_dir(a.tag), "row-record_pass")).values())
    def fn_bytes(tree, corpus, pred):
        return sum(v for k, v in tree[corpus].items() if pred(k[4]))
    hl = {
        "eda_total": [sum(before["eda"].values()), sum(after["eda"].values())],
        "eda_rds3_flat": [flat_b, flat_a],
        "rows_record_pass": [rp_b, rp_a],
        "lox_read_string": [fn_bytes(sb, "lox", lambda n: n == "vm::read_string"), fn_bytes(sa, "lox", lambda n: n == "vm::read_string")],
        "lox_read_constant": [fn_bytes(sb, "lox", lambda n: n == "vm::read_constant"), fn_bytes(sa, "lox", lambda n: n == "vm::read_constant")],
    }
    sexpr = collections.defaultdict(lambda: [0, 0])
    for k, v in sb["eda"].items():
        if k[4].startswith("sexpr_"):
            sexpr[k[4]][0] += v
    for k, v in sa["eda"].items():
        if k[4].startswith("sexpr_"):
            sexpr[k[4]][1] += v
    hl["eda_sexpr_functions"] = dict(sorted(sexpr.items(), key=lambda kv: -kv[1][0]))
    out["highlights"] = hl
    print("\n## Highlights\n\n| | CE-X final | after | change |\n|---|---:|---:|---:|")
    for name in ("eda_total", "eda_rds3_flat", "rows_record_pass", "lox_read_string", "lox_read_constant"):
        b, x = hl[name]
        print(f"| {name} | {ce.human(b)} | {ce.human(x)} | {pct(b, x)} |")
    print("\n**EDA `sexpr_*` functions (all patterns, site bytes)**\n\n| function | CE-X final | after |\n|---|---:|---:|")
    for name, (b, x) in hl["eda_sexpr_functions"].items():
        print(f"| `{name}` | {ce.human(b)} | {ce.human(x)} |")
    print("\n## Top 10 sites still copying (all corpora)\n\n| # | corpus | pattern | site | detail | function | bytes |\n|---:|---|---|---|---|---|---:|")
    allsites = [(v, c, k) for c in sa for k, v in sa[c].items()]
    allsites.sort(reverse=True)
    out["top"] = []
    for i, (v, c, k) in enumerate(allsites[:10], 1):
        print(f"| {i} | {c} | {k[0]} | `{k[1]}:{k[2]}` | {k[3]} | `{k[4]}` | {ce.human(v)} |")
        out["top"].append({"corpus": c, "pattern": k[0], "file": k[1], "line": k[2], "detail": k[3], "function": k[4], "bytes": v})
    if a.json:
        pathlib.Path(a.json).write_text(json.dumps(out, indent=1) + "\n")


if __name__ == "__main__":
    main()
