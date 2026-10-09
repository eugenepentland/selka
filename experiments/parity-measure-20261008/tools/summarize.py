#!/usr/bin/env python3
"""PM-2 tables from the evidence directory: reference ratios (pstat-*.json) and the
counterfactual attribution (cf/*/result.json). usage: summarize.py EVIDENCE_DIR"""
import json, sys
from pathlib import Path

ev = Path(sys.argv[1])

def pstat(name):
    d = json.loads((ev / name).read_text())
    out = {}
    for a in d["arms"]:
        out.setdefault(a["program"], {})[a["arm"]] = a["median"]
    return out

refs = {}
for f in ("pstat-parity.json", "pstat-lox.json", "pstat-eda.json"):
    refs.update(pstat(f))

print("### Reference ratios (perf stat, CPU 8, medians; cycles are user cycles)\n")
print("| program | my Minstr | my Mcyc | IPC | cyc ÷ zig-fast | cyc ÷ zig-safe | cyc ÷ rust | cyc ÷ rust-checked | instr ÷ zig-safe | instr ÷ rust-checked | L1 miss/ki my, zig-safe | LLC miss/ki my, zig-safe |")
print("|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|---|")
def r(m, arm, key):
    a = refs[m].get(arm)
    return f"{refs[m]['my'][key] / a[key]:.2f}" if a else "—"
for prog, arms in refs.items():
    my = arms["my"]
    zs = arms.get("zig-safe")
    l1 = f"{my['L1-dcache-load-misses']/my['instructions']*1000:.2f}, {zs['L1-dcache-load-misses']/zs['instructions']*1000:.2f}" if zs else ""
    llc = f"{my['LLC-load-misses']/my['instructions']*1000:.3f}, {zs['LLC-load-misses']/zs['instructions']*1000:.3f}" if zs else ""
    print(f"| {prog} | {my['instructions']/1e6:.0f} | {my['cycles']/1e6:.0f} | {my['instructions']/my['cycles']:.2f} | {r(prog,'zig-fast','cycles')} | {r(prog,'zig-safe','cycles')} | {r(prog,'rust','cycles')} | {r(prog,'rust-checked','cycles')} | {r(prog,'zig-safe','instructions')} | {r(prog,'rust-checked','instructions')} | {l1} | {llc} |")

# counterfactual results: (directory, case) -> program label
cases = {}
for d in sorted((ev / "cf").iterdir()):
    res = json.loads((d / "result.json").read_text())
    if "variants" in res:
        cases[(d.name, "run")] = res["variants"]
    else:
        for c, v in res["cases"].items():
            cases[(d.name, c)] = v["variants"]

print("\n### Counterfactual attribution (each variant ÷ the unedited rebuild; instr / cycles)\n")
cols = ["bounds", "overflow", "checks", "unique", "norc", "tbaa", "inline", "tail", "overflow+tail", "checks+norc", "checks+tbaa+unique"]
print("| program (cf run) | " + " | ".join(cols) + " |")
print("|---|" + "---|" * len(cols))
for (dname, case), v in cases.items():
    base = v.get("base", v.get("real"))["median"]
    cells = []
    for c in cols:
        x = v.get(c)
        if not x:
            cells.append("")
            continue
        m = x["median"]
        flag = "" if x["output_matches_real"] else " ✗"
        cells.append(f"{m['instructions']/base['instructions']:.2f} / {m['cycles']/base['cycles']:.2f}{flag}")
    label = dname if case == "run" else f"{dname} {case}"
    print(f"| {label} | " + " | ".join(cells) + " |")
print("\n✗: the variant's output differs from the real build (the edit broke the program): not a valid bound.")
