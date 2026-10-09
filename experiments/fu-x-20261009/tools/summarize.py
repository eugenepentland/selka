#!/usr/bin/env python3
"""FU-X Part 3 summaries (from CE2-X's) (coordinator, 2026-10-08; from CE-X's): reads the timing evidence in results/ and
writes results/{lox,eda,parity,rows}-summary.md, printing the aggregates REPORT.md quotes.
"final" is the F/U integration (claude/fu-x: lanes F2 and U1), "base" main 35df839be (~/.cache/mylang/main-35df839b).
usage: summarize.py [EVIDENCE_DIR]"""
import gzip, json, math, statistics, sys
from pathlib import Path

X = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[1]
R = X / "results"


def load(name):
    path = R / name
    opener = gzip.open if name.endswith(".gz") else open
    with opener(path, "rt") as handle:
        return json.load(handle)


def gm(xs):
    return math.exp(sum(map(math.log, xs)) / len(xs))


def lox():
    lines = ["# Lox runtime, final against base (main 35df839be, CPU 10, median of 3 rounds)", "",
             "| cell | final s | base s | final/base | final/Zig | base/Zig | final/Zig-safe | final/Rust | final/Go |",
             "|---|---:|---:|---:|---:|---:|---:|---:|---:|"]
    agg = {}
    for name in ("lox-runtime.json.gz", "lox-six-runtime.json.gz"):
        if not (R / name).exists():
            continue
        samples = load(name)["samples"]
        for cell, arms in sorted(samples.items()):
            m = {a: statistics.median([s["wall"] for s in v if s["wall"] is not None]) for a, v in arms.items()}
            f, z = m["mylang:release"], m["zig:release"]
            b = m.get("mylang-base:release")
            row = [cell, f"{f:.3f}", f"{b:.3f}" if b else "—", f"{f / b:.3f}" if b else "—", f"{f / z:.2f}",
                   f"{b / z:.2f}" if b else "—", f"{f / m['zig:release-safe']:.2f}", f"{f / m['rust:release']:.2f}",
                   f"{f / m['go:release']:.2f}"]
            lines.append("| " + " | ".join(row) + " |")
            group = ("six " if b is None else "") + cell.split("/")[1]
            a = agg.setdefault(group, {"f/z": [], "b/z": [], "f/b": [], "f/zs": [], "f/rust": [], "f/go": []})
            a["f/z"].append(f / z); a["f/zs"].append(f / m["zig:release-safe"])
            a["f/rust"].append(f / m["rust:release"]); a["f/go"].append(f / m["go:release"])
            if b:
                a["b/z"].append(b / z); a["f/b"].append(f / b)
    lines += ["", "| group | cells | final/base | base/Zig | final/Zig | final/Zig-safe | final/Rust | final/Go |",
              "|---|---:|---:|---:|---:|---:|---:|---:|"]
    for group, a in agg.items():
        fb = f"{gm(a['f/b']):.3f}" if a["f/b"] else "—"
        bz = f"{gm(a['b/z']):.2f}" if a["b/z"] else "—"
        lines.append(f"| {group} | {len(a['f/z'])} | {fb} | {bz} | {gm(a['f/z']):.2f} | {gm(a['f/zs']):.2f} | "
                     f"{gm(a['f/rust']):.2f} | {gm(a['f/go']):.2f} |")
    (R / "lox-summary.md").write_text("\n".join(lines) + "\n")
    print("\n".join(lines[-(len(agg) + 2):]))


def eda():
    r = load("eda-runtime.json.gz")
    rows = []
    for name, c in r["per_case"].items():
        f, b, z = (c[k]["median_s"] for k in ("mylang-final", "mylang-base", "zig-fast"))
        rows.append((f / b, name, f, b, z))
    rows.sort()
    lines = ["# EDA runtime, final against base (main 35df839be, CPU 10, median of 10 rounds)", "",
             f"All outputs verified: {r['all_outputs_verified']}. Sorted by final/base.", "",
             "| design | final ms | base ms | Zig ms | final/base | final/Zig | base/Zig |", "|---|---:|---:|---:|---:|---:|---:|"]
    lines += [f"| {n} | {f * 1e3:.1f} | {b * 1e3:.1f} | {z * 1e3:.1f} | {x:.3f} | {f / z:.2f} | {b / z:.2f} |" for x, n, f, b, z in rows]
    s = r["summary"]
    lines += ["", "| binary | geomean vs zig-fast | zig-safe | rust | go | peak RSS MiB |", "|---|---:|---:|---:|---:|---:|"]
    for b in ("mylang-base", "mylang-final"):
        g = s[b]["geomean_ratio_vs"]
        lines.append(f"| {b} | {g['zig-fast']:.3f} | {g['zig-safe']:.3f} | {g['rust']:.3f} | {g['go']:.3f} | {s[b]['peak_rss_exact_mib']} |")
    (R / "eda-summary.md").write_text("\n".join(lines) + "\n")
    print(f"eda final/base geomean {gm([x[0] for x in rows]):.3f}; max {rows[-1][1]} {rows[-1][0]:.3f}; "
          f"final vs zig-fast {s['mylang-final']['geomean_ratio_vs']['zig-fast']:.3f}, base {s['mylang-base']['geomean_ratio_vs']['zig-fast']:.3f}")


def parity():
    f, b = load("parity-final.json.gz"), load("parity-base.json.gz")
    rows = []
    for name, e in f["benchmarks"].items():
        for arm, fa in e["arms"].items():
            ba = b["benchmarks"].get(name, {}).get("arms", {}).get(arm)
            if not (arm == "my" or arm.startswith("my-")) or not ba or not fa.get("ratio_wall") or not ba.get("ratio_wall"):
                continue
            fr, br = fa["ratio_wall"]["median"], ba["ratio_wall"]["median"]
            rows.append((fr / br, name, arm, br, fr, fa["wall_median"] / ba["wall_median"],
                         ba["ratio_wall"]["lo"], ba["ratio_wall"]["hi"], fa["ratio_wall"]["lo"], fa["ratio_wall"]["hi"]))
    rows.sort()
    lines = ["# Parity, final against base (main 35df839be, CPU 10, 9 rounds, 2 warm-ups; same session)", "",
             "final/base is the ratio of each run's my/zig-fast ratio; wall is the ratio of raw medians.", "",
             "| program | arm | base/Zig (95% CI) | final/Zig (95% CI) | final/base | wall final/base |", "|---|---|---:|---:|---:|---:|"]
    lines += [f"| {n} | {a} | {br:.2f} ({bl:.2f}–{bh:.2f}) | {fr:.2f} ({fl:.2f}–{fh:.2f}) | {x:.3f} | {w:.3f} |"
              for x, n, a, br, fr, w, bl, bh, fl, fh in rows]
    my = [r for r in rows if r[2] == "my"]
    lines += ["", f"my arm, {len(my)} programs: geomean base/Zig {gm([r[3] for r in my]):.3f}, final/Zig "
              f"{gm([r[4] for r in my]):.3f}, final/base {gm([r[0] for r in my]):.3f}; all {len(rows)} arms final/base {gm([r[0] for r in rows]):.3f}"]
    (R / "parity-summary.md").write_text("\n".join(lines) + "\n")
    print(lines[-1])


def rows46():
    batches = [load(f"all46-{n}.json.gz") for n in (1, 2, 3)]
    keys = [(name, size) for name, row in batches[0]["rows"].items() for size in row["sizes"]]
    out = []
    for name, size in keys:
        v = [r["rows"][name]["sizes"][size]["new_over_old"] for r in batches]
        z = statistics.median([r["rows"][name]["sizes"][size]["new_over_zig"] for r in batches])
        out.append((statistics.median(v), name, size, v, z))
    out.sort()
    lines = ["# 46 rows, final (new) against base (old) (main 35df839be, CPU 10, cycles, 3 batches of 7 interleaved rounds)", "",
             f"Batches valid: {[r['valid'] for r in batches]}. Sorted by the median of the three batches.", "",
             "| row | size | batch 1 | batch 2 | batch 3 | median | final/Zig-safe |", "|---|---:|---:|---:|---:|---:|---:|"]
    lines += [f"| {n} | {s} | {v[0]:.3f} | {v[1]:.3f} | {v[2]:.3f} | {m:.3f} | {z:.3f} |" for m, n, s, v, z in out]
    worst = out[-1]
    single = [(n, s, v) for m, n, s, v, z in out if max(v) > 1.03]
    lines += ["", f"median-of-3 geomean {gm([o[0] for o in out]):.4f}; worst median {worst[1]}/{worst[2]} {worst[0]:.3f}; "
              f"medians above 1.03: {[(n, s) for m, n, s, v, z in out if m > 1.03]}; single batches above 1.03: "
              f"{[(n, s, [round(x, 3) for x in v]) for n, s, v in single]}"]
    (R / "rows-summary.md").write_text("\n".join(lines) + "\n")
    print(lines[-1])


if __name__ == "__main__":
    lox(); eda(); parity(); rows46()
