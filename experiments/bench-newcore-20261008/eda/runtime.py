#!/usr/bin/env python3
"""Program runtime of each eda-sch port on the 34 stage-1 golden cases.

usage: runtime.py --repo EDA_BENCH --out results.json [--rounds N] [--cpu C] [--work DIR] NAME=BINARY...

Every case is run exactly as `bench.py equiv` runs it (same argv, cwd = the repo
root). One untimed warm-up round runs first. Then N timed rounds; within a round,
cases go in manifest order and, for each case, every binary runs once, in an order
rotated by round, so each case's samples for all binaries are taken close together.
The harness process pins itself to --cpu, so every child inherits that
affinity; each run is timed from spawn to wait4 (wall), with ru_maxrss, ru_utime and ru_stime from wait4.
Every run's output directory is compared byte for byte with the case's goldens
(outside the timed region); any mismatch or non-zero exit aborts the measurement.

wait4's ru_maxrss of a spawned child includes the launching Python process's
image (Linux carries the pre-exec high-water mark across execve), so it has a
floor of the harness's own RSS (~22 MiB). After the timed rounds, one more
untimed round runs every case under `/usr/bin/time -f %M` (a ~2 MiB launcher)
and records that as the exact peak RSS (`rss_exact_mib`).

Summary per binary: the sum over the 34 cases of each case's median wall, the
peak RSS, the user+sys CPU, and the geometric mean over cases of (median of A / median of B) for
every ordered pair, plus each case's median.
"""

import argparse
import json
import math
import os
import shutil
import statistics
import subprocess
import sys
import time
from pathlib import Path


def run_case(exe, case, golden, out, cpu, rss_file=None):
    if out.exists():
        shutil.rmtree(out)
    wrap = ["/usr/bin/time", "-f", "%M", "-o", str(rss_file)] if rss_file else []
    cmd = [*wrap, exe, "--model", str(golden / "cases" / case["id"] / "model.sexp"),
           "--project-dir", str(golden / "projects" / case["project"]),
           "--out-dir", str(out), *case["flags"]]
    errpath = out.parent / (out.name + ".stderr")
    out.parent.mkdir(parents=True, exist_ok=True)
    with open(errpath, "wb") as errf:
        # The parent is already pinned to `cpu`; the child inherits the affinity.
        t0 = time.perf_counter()
        p = subprocess.Popen(cmd, cwd=golden.parent, stdout=subprocess.DEVNULL, stderr=errf)
        _, status, usage = os.wait4(p.pid, 0)
        wall = time.perf_counter() - t0
    p.returncode = os.waitstatus_to_exitcode(status)
    err = errpath.read_bytes()
    errpath.unlink()
    code = os.waitstatus_to_exitcode(status)
    return {"wall_s": wall, "rss_kb": usage.ru_maxrss, "user_s": usage.ru_utime,
            "sys_s": usage.ru_stime, "code": code, "stderr_tail": err[-400:].decode(errors="replace")}


def verify(case, golden, out):
    expected = golden / "cases" / case["id"] / "expected"
    got = {str(p.relative_to(out)) for p in out.rglob("*") if p.is_file()} if out.exists() else set()
    want = set(case["outputs"])
    problems = [f"missing {n}" for n in sorted(want - got)] + [f"unexpected {n}" for n in sorted(got - want)]
    for n in sorted(want & got):
        if (expected / n).read_bytes() != (out / n).read_bytes():
            problems.append(f"differs {n}")
    return problems


def geomean(xs):
    return math.exp(sum(math.log(x) for x in xs) / len(xs))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--repo", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--rounds", type=int, default=7)
    ap.add_argument("--cpu", type=int, default=10)
    ap.add_argument("--work", required=True, help="scratch directory for the outputs")
    ap.add_argument("binaries", nargs="+", metavar="NAME=BINARY")
    args = ap.parse_args()

    repo = Path(args.repo).resolve()
    golden = repo / "golden"
    cases = json.loads((golden / "manifest.json").read_text())["cases"]
    bins = dict(b.split("=", 1) for b in args.binaries)
    for name, exe in bins.items():
        if not Path(exe).is_file():
            sys.exit(f"{name}: {exe} does not exist")
    names = list(bins)
    work = Path(args.work)
    work.mkdir(parents=True, exist_ok=True)
    os.sched_setaffinity(0, {args.cpu})  # the parent too, so fork/exec land on the same CPU

    samples = {n: {c["id"]: [] for c in cases} for n in names}
    rss = {n: {c["id"]: 0 for c in cases} for n in names}
    cpu_s = {n: {c["id"]: [] for c in cases} for n in names}
    rss_exact = {n: {} for n in names}
    load = {"before": os.getloadavg()}
    t_start = time.time()
    for rnd in range(args.rounds + 1):
        order = names[rnd % len(names):] + names[:rnd % len(names)]
        for c in cases:
            for n in order:
                out = work / n / c["id"]
                r = run_case(bins[n], c, golden, out, args.cpu)
                if r["code"] != 0:
                    sys.exit(f"{n} {c['id']}: exit {r['code']}: {r['stderr_tail']}")
                problems = verify(c, golden, out)
                if problems:
                    sys.exit(f"{n} {c['id']} round {rnd}: output differs from golden: {problems[:5]}")
                if rnd > 0:
                    samples[n][c["id"]].append(round(r["wall_s"], 6))
                    rss[n][c["id"]] = max(rss[n][c["id"]], r["rss_kb"])
                    cpu_s[n][c["id"]].append(r["user_s"] + r["sys_s"])
                shutil.rmtree(out)
        label = "warm-up" if rnd == 0 else f"round {rnd}/{args.rounds}"
        print(f"{label} done, 34 cases x {len(names)} binaries verified; loadavg {os.getloadavg()}", flush=True)
    rss_file = work / "rss.txt"
    for c in cases:
        for n in names:
            out = work / n / c["id"]
            r = run_case(bins[n], c, golden, out, args.cpu, rss_file)
            if r["code"] != 0 or verify(c, golden, out):
                sys.exit(f"{n} {c['id']}: RSS round failed: exit {r['code']} {r['stderr_tail']}")
            rss_exact[n][c["id"]] = int(rss_file.read_text().split()[-1])
            shutil.rmtree(out)
    print("exact-RSS round done (/usr/bin/time -f %M)", flush=True)
    load["after"] = os.getloadavg()

    med = {n: {cid: statistics.median(v) for cid, v in samples[n].items()} for n in names}
    summary = {}
    for n in names:
        summary[n] = {
            "total_of_case_medians_s": round(sum(med[n].values()), 4),
            "total_of_case_minimums_s": round(sum(min(v) for v in samples[n].values()), 4),
            "peak_rss_exact_mib": round(max(rss_exact[n].values()) / 1024, 1),
            "median_case_rss_exact_mib": round(statistics.median(rss_exact[n].values()) / 1024, 1),
            "peak_rss_wait4_mib": round(max(rss[n].values()) / 1024, 1),
            "total_cpu_of_case_medians_s": round(sum(statistics.median(v) for v in cpu_s[n].values()), 4),
            "geomean_ratio_vs": {m: round(geomean([med[n][c["id"]] / med[m][c["id"]] for c in cases]), 4)
                                 for m in names if m != n},
        }
    result = {
        "repo": str(repo), "cpu": args.cpu, "rounds": args.rounds, "warmup_rounds": 1,
        "binaries": bins, "host": os.uname().nodename, "load_avg": load,
        "started": time.strftime("%Y-%m-%dT%H:%M:%S", time.localtime(t_start)),
        "elapsed_s": round(time.time() - t_start, 1),
        "all_outputs_verified": True,
        "summary": summary,
        "per_case": {c["id"]: {n: {"median_s": round(med[n][c["id"]], 6), "samples_s": samples[n][c["id"]],
                                   "cpu_median_s": round(statistics.median(cpu_s[n][c["id"]]), 6),
                                   "rss_exact_mib": round(rss_exact[n][c["id"]] / 1024, 1),
                                   "peak_rss_wait4_mib": round(rss[n][c["id"]] / 1024, 1)} for n in names}
                     for c in cases},
    }
    Path(args.out).parent.mkdir(parents=True, exist_ok=True)
    Path(args.out).write_text(json.dumps(result, indent=1) + "\n")

    print(f"\n{'binary':<12} {'total(med)':>11} {'total(min)':>11} {'peak RSS':>9}  geomean ratio vs ...")
    for n in names:
        s = summary[n]
        ratios = "  ".join(f"{m} {r:.3f}" for m, r in s["geomean_ratio_vs"].items())
        print(f"{n:<12} {s['total_of_case_medians_s']:10.3f}s {s['total_of_case_minimums_s']:10.3f}s "
              f"{s['peak_rss_exact_mib']:6.0f} MiB  {ratios}")
    print(f"wrote {args.out}")


if __name__ == "__main__":
    main()
