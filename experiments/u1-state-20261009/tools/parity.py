#!/usr/bin/env python3
"""Lane F1's parity tool: build every parity program, check `.expected`, measure arms.

  parity.py build --mylang M --out DIR [--filter S]...
      Builds every `bench/parity/{lib,micro,suite}/*.my` (`--release`) into DIR,
      runs each once off the timing CPUs and compares stdout with its stem's
      `.expected` (a variant `<name>_<v>.my` uses `<name>.expected`). Writes
      DIR/build.json with the verdicts. Exit 1 if any output differs.
  parity.py measure --arm LABEL=DIR... [--ref zig-safe] --out OUT.json [--rounds N] [--cpu 8] [--filter S]...
      Interleaved, shuffled `perf stat` (user instructions and cycles) of the
      same program across arms (plus PM's reference binaries), pinned to one CPU.
      Prints medians and each arm's ratio to the first arm and to the reference.
"""
from __future__ import annotations

import argparse, hashlib, json, random, statistics, subprocess, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
PARITY = ROOT / "bench" / "parity"
REFS = Path("/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.tmp/pm/parity/work/bin")
OFF_TIMING = "0,1,4-9,12-19"
EVENTS = ["instructions", "cycles"]


def programs(filters):
    out = []
    for group in ("lib", "micro", "suite"):
        d = PARITY / group
        stems = {e.stem for e in d.glob("*.expected")}
        for src in sorted(d.glob("*.my")):
            stem = src.stem
            base = stem if stem in stems else next((s for s in sorted(stems, key=len, reverse=True) if stem.startswith(s + "_")), None)
            if base is None:
                continue
            if filters and not any(f in f"{group}/{stem}" for f in filters):
                continue
            out.append({"group": group, "name": stem, "src": src, "expected": d / f"{base}.expected", "base": base})
    return out


def build(a):
    out = Path(a.out).resolve(); out.mkdir(parents=True, exist_ok=True)
    verdicts = {}
    bad = 0
    for p in programs(a.filter):
        exe = out / p["name"]
        b = subprocess.run(["taskset", "-c", OFF_TIMING, a.mylang, "build", str(p["src"]), "-o", str(exe), "--release", "--cache-dir", str(out / "cache")],
                           capture_output=True, text=True)
        if b.returncode != 0:
            verdicts[p["name"]] = {"built": False, "log": b.stderr[-2000:]}
            bad += 1
            print(f"BUILD FAIL {p['name']}: {b.stderr[-400:]}")
            continue
        r = subprocess.run(["taskset", "-c", OFF_TIMING, str(exe)], cwd=p["src"].parent, capture_output=True, timeout=600)
        ok = r.returncode == 0 and r.stdout == p["expected"].read_bytes()
        verdicts[p["name"]] = {"built": True, "status": r.returncode, "matches_expected": ok, "stdout_sha256": hashlib.sha256(r.stdout).hexdigest()}
        bad += 0 if ok else 1
        print(f"{'ok  ' if ok else 'DIFF'} {p['group']}/{p['name']}")
    (out / "build.json").write_text(json.dumps(verdicts, indent=1, sort_keys=True))
    print(f"{len(verdicts) - bad}/{len(verdicts)} match .expected")
    return 1 if bad else 0


def stat(argv, cwd, cpu):
    events = ",".join(f"cpu_core/{e}/u" for e in EVENTS)
    proc = subprocess.run(["taskset", "-c", str(cpu), "perf", "stat", "-x,", "-e", events, "--", *argv], cwd=cwd,
                          stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True, timeout=900)
    row = {"status": proc.returncode}
    for line in proc.stderr.splitlines():
        f = line.split(",")
        if len(f) > 2 and f[2].startswith("cpu_core/"):
            try:
                row[f[2][9:].rsplit("/", 1)[0]] = int(f[0])
            except ValueError:
                pass
    return row


def measure(a):
    if a.cpu in (2, 3, 10, 11):
        raise SystemExit("CPUs 2, 3, 10 and 11 are reserved")
    arms = [x.split("=", 1) for x in a.arm]
    rng = random.Random(a.seed)
    result = {"cpu": a.cpu, "rounds": a.rounds, "programs": {}}
    for p in programs(a.filter):
        runs = [(label, [str(Path(d).resolve() / p["name"])]) for label, d in arms]
        for ref in a.ref:
            exe = REFS / f"{p['name']}.{ref}"
            if exe.exists():
                runs.append((ref, [str(exe)]))
        if not all(Path(r[1][0]).exists() for r in runs[:len(arms)]):
            continue
        samples = {label: [] for label, _ in runs}
        for _ in range(a.rounds):
            order = list(runs); rng.shuffle(order)
            for label, argv in order:
                samples[label].append(stat(argv, p["src"].parent, a.cpu))
        med = {label: {e: statistics.median([s[e] for s in rows if e in s]) for e in EVENTS} for label, rows in samples.items()}
        result["programs"][p["name"]] = {"median": med, "samples": samples}
        first = arms[0][0]
        cells = []
        for label, _ in runs:
            m = med[label]
            cells.append(f"{label} {m['instructions']/1e6:.0f}Mi {m['cycles']/1e6:.0f}Mc i/{first} {m['instructions']/med[first]['instructions']:.3f} c/{first} {m['cycles']/med[first]['cycles']:.3f}")
        line = f"{p['name']}: " + " | ".join(cells)
        for ref in a.ref:
            if ref in med:
                line += " | " + " ".join(f"{label}/{ref} c {med[label]['cycles']/med[ref]['cycles']:.3f}" for label, _ in arms)
        print(line, flush=True)
    Path(a.out).write_text(json.dumps(result, indent=1))


def main():
    p = argparse.ArgumentParser()
    sub = p.add_subparsers(dest="cmd", required=True)
    b = sub.add_parser("build"); b.add_argument("--mylang", required=True); b.add_argument("--out", required=True); b.add_argument("--filter", action="append", default=[])
    m = sub.add_parser("measure"); m.add_argument("--arm", action="append", required=True); m.add_argument("--ref", action="append", default=[])
    m.add_argument("--out", required=True); m.add_argument("--rounds", type=int, default=5); m.add_argument("--cpu", type=int, default=8)
    m.add_argument("--seed", type=int, default=20261009); m.add_argument("--filter", action="append", default=[])
    a = p.parse_args()
    sys.exit(build(a) if a.cmd == "build" else measure(a))


if __name__ == "__main__":
    main()
