#!/usr/bin/env python3
"""Counting builds of the exit programs: overflow/bounds check counts per source line.

usage: checks.py --mylang M --work DIR [--out JSON] PROGRAM.my...
Builds each program with `--release --counters`, runs it on CPUs outside the
timing set, and prints the check-kind sites (count per line) plus the program's
stdout digest, so counting-on output can be compared with counting-off output.
"""
import argparse, hashlib, json, os, subprocess, sys
from pathlib import Path

KINDS = ("overflow_check", "bounds_check", "division_check", "shift_check", "other_check")


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--mylang", required=True)
    p.add_argument("--work", required=True)
    p.add_argument("--out")
    p.add_argument("--cpus", default="0,1,4-9,12-19")
    p.add_argument("programs", nargs="+")
    a = p.parse_args()
    work = Path(a.work).resolve(); work.mkdir(parents=True, exist_ok=True)
    result = {}
    for program in a.programs:
        prog = Path(program).resolve()
        name = prog.stem
        exe = work / f"{name}.counted"
        plain = work / f"{name}.plain"
        cache = work / "cache"
        subprocess.run([a.mylang, "build", str(prog), "-o", str(exe), "--release", "--counters", "--cache-dir", str(cache)], check=True, stdout=subprocess.DEVNULL)
        subprocess.run([a.mylang, "build", str(prog), "-o", str(plain), "--release", "--cache-dir", str(cache)], check=True, stdout=subprocess.DEVNULL)
        counts = work / f"{name}.json"
        env = dict(os.environ, MYLANG_COUNTERS=str(counts))
        on = subprocess.run(["taskset", "-c", a.cpus, str(exe)], cwd=prog.parent, env=env, stdout=subprocess.PIPE, check=False)
        off = subprocess.run(["taskset", "-c", a.cpus, str(plain)], cwd=prog.parent, stdout=subprocess.PIPE, check=False)
        doc = json.loads(counts.read_text())
        sites = {}
        for s in doc["sites"]:
            if s["kind"] in KINDS:
                key = f'{s["kind"]}@{Path(s["path"]).name}:{s["line"]}'
                sites[key] = sites.get(key, 0) + s["count"]
        same = on.stdout == off.stdout and on.returncode == off.returncode
        result[name] = {"sites": sites, "kinds": {k: doc["kinds"].get(k, {}).get("count", 0) for k in KINDS},
                        "stdout_sha256": hashlib.sha256(off.stdout).hexdigest(), "counting_matches": same}
        print(f"## {name}: counting on/off identical: {same}")
        for k, v in sorted(sites.items()):
            print(f"  {k}: {v}")
    if a.out:
        Path(a.out).write_text(json.dumps(result, indent=1, sort_keys=True))


if __name__ == "__main__":
    main()
