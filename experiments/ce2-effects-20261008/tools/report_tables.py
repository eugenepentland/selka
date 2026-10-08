#!/usr/bin/env python3
"""CE2-A report tables: bytes moved per pattern and corpus for CE-X's final (`cex`) and CE2-A's
final, the Lox steps, the target sites, the highlights and the top sites still copying.
Writes analysis/tables.json and prints Markdown. Usage: report_tables.py [FINAL_TAG]"""
import collections, json, pathlib, sys
sys.path.insert(0, str(pathlib.Path(__file__).parent))
import ce
import sites as site_tools

FINAL = sys.argv[1] if len(sys.argv) > 1 else "final"
LOX_STEPS = ["cex", "step2", "step34", "step5", "step6", FINAL]
CORPORA = ["lox", "eda", "parity", "rows"]
ORDER = ["P1", "P2", "P3", "P4", "P5", "P6", "P7", "P8", "P9", "P10", "P11", "P12", "P13", "P14"]


def site_bytes(s):
    return s["extra"] if s["kind"] == "list_push" else s["bytes"]


def dispatches(label):
    """VM dispatches of a Lox VM cell: CE-X's executions of the uniqueness test at vm.my:433,
    once per instruction (the program's own count; CE2-A moved that test)."""
    data = ce.load_counts(ce.raw_dir("cex"), label)
    return sum(s["count"] for s in data["sites"] if s["path"].endswith("vm.my") and s["line"] == 433 and s["kind"] == "unique_test")


def main():
    out = {"final": FINAL, "patterns": {}, "lox_steps": {}, "targets": [], "highlights": {}, "top": {}}
    for tag in ("cex", FINAL):
        pats, _ = site_tools.collect(tag, CORPORA)
        out["patterns"][tag] = {c: dict(v) for c, v in pats.items()}
    for tag in LOX_STEPS:
        if not ce.raw_dir(tag).exists():
            continue
        pats, _ = site_tools.collect(tag, ["lox"])
        out["lox_steps"][tag] = dict(pats["lox"])
    _, before_sites = site_tools.collect("cex", CORPORA)
    _, after_sites = site_tools.collect(FINAL, CORPORA)
    for pat, path, line in site_tools.TARGETS:
        b = sum(v for k, v in before_sites["lox"].items() if k[0] == pat and k[1] == path and k[2] == line)
        a = sum(v for k, v in after_sites["lox"].items() if k[0] == pat and k[1] == path and k[2] == line)
        out["targets"].append({"pattern": pat, "file": path, "line": line, "cex": b, FINAL: a})
    h = out["highlights"]
    n = dispatches("lox-vm-fib-27")
    for tag in ("cex", FINAL):
        fib = ce.by_pattern(ce.load_counts(ce.raw_dir(tag), "lox-vm-fib-27"))
        h[tag] = {"lox_vm_fib27_dispatches": n, "lox_vm_fib27_bytes_per_dispatch": sum(fib.values()) / n,
                  "lox_vm_fib27_bytes": sum(fib.values()), "lox_vm_fib27_by_pattern": dict(fib)}
    everything = collections.Counter()
    for corpus in CORPORA:
        top = []
        for k, v in after_sites[corpus].most_common(10):
            top.append({"pattern": k[0], "file": k[1], "line": k[2], "detail": k[3], "function": k[4], "bytes": v, "cex": before_sites[corpus].get(k, 0)})
        out["top"][corpus] = top
        for k, v in after_sites[corpus].items():
            everything[(corpus,) + k] += v
    out["top"]["all"] = [{"corpus": k[0], "pattern": k[1], "file": k[2], "line": k[3], "detail": k[4], "function": k[5], "bytes": v} for k, v in everything.most_common(10)]
    area = ce.AREA / "analysis"
    area.mkdir(exist_ok=True)
    (area / "tables.json").write_text(json.dumps(out, indent=1) + "\n")
    lines = []
    for corpus in CORPORA:
        b, a = out["patterns"]["cex"].get(corpus, {}), out["patterns"][FINAL].get(corpus, {})
        lines += [f"\n### {corpus}\n", "| pattern | CE-X final | CE2-A final | change |", "|---|---:|---:|---:|"]
        for name in ORDER + ["P2+P4", "all"]:
            if name == "P2+P4":
                x, y = b.get("P2", 0) + b.get("P4", 0), a.get("P2", 0) + a.get("P4", 0)
            elif name == "all":
                x, y = sum(b.values()), sum(a.values())
            else:
                x, y = b.get(name, 0), a.get(name, 0)
            if not x and not y:
                continue
            ch = f"{100 * (y - x) / x:+.1f}%" if x else "new"
            lab = f"**{name}**" if name in ("P2+P4", "all") else name
            lines.append(f"| {lab} | {ce.human(x)} | {ce.human(y)} | {ch} |")
    lines += ["\n### Lox by step\n", "| pattern | " + " | ".join(t for t in out["lox_steps"]) + " |", "|---|" + "---:|" * len(out["lox_steps"])]
    for name in ORDER + ["P2+P4", "all"]:
        vals = []
        for t, d in out["lox_steps"].items():
            vals.append(d.get("P2", 0) + d.get("P4", 0) if name == "P2+P4" else (sum(d.values()) if name == "all" else d.get(name, 0)))
        if any(vals):
            lines.append(f"| {name} | " + " | ".join(ce.human(v) for v in vals) + " |")
    lines += ["\n### targets (Lox)\n", "| site | CE-X final | CE2-A final | change |", "|---|---:|---:|---:|"]
    for t in out["targets"]:
        ch = f"{100 * (t[FINAL] - t['cex']) / t['cex']:+.1f}%" if t["cex"] else ""
        lines.append(f"| {t['pattern']} {t['file']}:{t['line']} | {ce.human(t['cex'])} | {ce.human(t[FINAL])} | {ch} |")
    lines += ["\n### highlights\n"]
    for tag in ("cex", FINAL):
        x = h[tag]
        lines.append(f"- {tag}: Lox VM fib(27) {x['lox_vm_fib27_bytes_per_dispatch']:.1f} bytes per dispatch ({ce.human(x['lox_vm_fib27_bytes'])} over {x['lox_vm_fib27_dispatches']:,} dispatches)")
    lines += ["\n### top 10 sites still copying, all corpora\n", "| # | corpus | site | bytes |", "|---:|---|---|---:|"]
    for i, t in enumerate(out["top"]["all"], 1):
        lines.append(f"| {i} | {t['corpus']} | {t['pattern']} `{t['file']}:{t['line']}` {t['detail']} in `{t['function']}` | {ce.human(t['bytes'])} |")
    print("\n".join(lines))


if __name__ == "__main__":
    main()
