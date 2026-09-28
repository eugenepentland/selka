#!/usr/bin/env python3
"""Differential fuzzer: reference counting (the default runtime) against the
tracing collector (`--gc-runtime`).

Each seed generates one random, well-typed program (gen.py or gen2.py), checks
it, runs it once under GC as the baseline and then under every RC mode:

  rc      the default runtime (no flag)
  stats   --rc-runtime=stats, whose MYLANG_RC_COUNTS line must also balance
  rcrel   --release (default RC under LLVM O3 + LTO), every --release-every seeds

and, as a report-only lane, under `--gc-stress` (which selects the collector).
Exit code, stdout and filtered stderr must match the GC baseline. An RC-mode
divergence fails the run (exit 1); a divergence only under `--gc-stress` is a
collector finding, printed and counted but not failing. Diverging programs are
kept under OUT/found/.

usage: run.py [--compiler PATH] [--start N] [--count N] [--jobs N]
              [--gen gen.py|gen2.py|both] [--release-every N] [--out DIR]
              [--no-stress]

The compiler defaults to $MYLANG, else zig-out/bin/mylang. Outputs (work files,
found programs, the build cache, TMPDIR and summary.json) go under OUT, default
experiments/rc-fuzz/out/, which is gitignored.
"""
import argparse
import concurrent.futures
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
GENERATORS = {"gen.py": os.path.join(HERE, "gen.py"), "gen2.py": os.path.join(HERE, "gen2.py")}
BASELINE = ("gc", ["--gc-runtime"])
RC_MODES = [("rc", []), ("stats", ["--rc-runtime=stats"])]
RELEASE_MODE = ("rcrel", ["--release"])
STRESS_MODE = ("stress", ["--gc-stress"])
TIMEOUT = 600


def arguments():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--compiler", default=os.environ.get("MYLANG") or os.path.join(ROOT, "zig-out", "bin", "mylang"))
    parser.add_argument("--start", type=int, default=1)
    parser.add_argument("--count", type=int, default=200)
    parser.add_argument("--jobs", type=int, default=3)
    parser.add_argument("--gen", choices=["gen.py", "gen2.py", "both"], default="both",
                        help="generator; 'both' alternates gen.py (even seeds) and gen2.py (odd seeds)")
    parser.add_argument("--release-every", type=int, default=8, help="add the --release RC mode every N seeds (0: never)")
    parser.add_argument("--out", default=os.path.join(HERE, "out"))
    parser.add_argument("--no-stress", action="store_true", help="skip the report-only --gc-stress lane")
    return parser.parse_args()


class Fuzz:
    def __init__(self, options):
        self.options = options
        self.compiler = os.path.abspath(options.compiler)
        self.out = os.path.abspath(options.out)
        self.work = os.path.join(self.out, "work")
        self.found = os.path.join(self.out, "found")
        self.cache = os.path.join(self.out, "cache")
        tmp = os.path.join(self.out, "tmp")
        for directory in (self.work, self.found, self.cache, tmp):
            os.makedirs(directory, exist_ok=True)
        # The inherited carrier would change the baseline; every mode names its runtime.
        self.env = {k: v for k, v in os.environ.items() if k != "MYLANG_RUNTIME"}
        self.env["TMPDIR"] = tmp

    def generator(self, seed):
        if self.options.gen != "both":
            return GENERATORS[self.options.gen]
        return GENERATORS["gen.py" if seed % 2 == 0 else "gen2.py"]

    def run(self, path, flags):
        try:
            p = subprocess.run([self.compiler, "run", path, "--cache-dir=" + self.cache] + flags,
                               capture_output=True, text=True, env=self.env, timeout=TIMEOUT)
        except subprocess.TimeoutExpired:
            return (-99, "", "timeout", None)
        counts = None
        err = []
        for line in p.stderr.splitlines():
            if line.startswith("MYLANG_RC_COUNTS "):
                counts = json.loads(line[len("MYLANG_RC_COUNTS "):])
            elif "warning[" in line or line.startswith("  ") or not line.strip():
                continue
            else:
                err.append(line)
        return (p.returncode, p.stdout, "\n".join(err), counts)

    @staticmethod
    def balanced(c):
        if c is None:
            return "no counts"
        problems = []
        if c["heap_allocate"] != c["retire"]:
            problems.append(f"alloc {c['heap_allocate']} != retire {c['retire']}")
        if c["heap_allocate"] + c["owner_acquire"] != c["owner_release"]:
            problems.append(f"alloc+acq {c['heap_allocate'] + c['owner_acquire']} != rel {c['owner_release']}")
        if c["hold_acquire"] != c["hold_release"]:
            problems.append(f"hold {c['hold_acquire']} != {c['hold_release']}")
        return "; ".join(problems) or "ok"

    @staticmethod
    def compare(name, res, base):
        problems = []
        if res[0] != base[0]:
            problems.append(f"{name}: exit {res[0]} vs {base[0]}")
        if res[1] != base[1]:
            problems.append(f"{name}: stdout differs")
        if res[2] != base[2]:
            problems.append(f"{name}: stderr differs: {res[2][:200]!r} vs {base[2][:200]!r}")
        return problems

    def one(self, seed):
        path = os.path.join(self.work, f"s{seed}.my")
        generated = subprocess.run([sys.executable, self.generator(seed), str(seed)], capture_output=True, text=True)
        with open(path, "w") as f:
            f.write(generated.stdout)
        chk = subprocess.run([self.compiler, "check", path], capture_output=True, text=True, env=self.env)
        if chk.returncode != 0:
            return seed, "invalid", chk.stderr.splitlines()[:2], []
        base = self.run(path, BASELINE[1])
        modes = list(RC_MODES)
        if self.options.release_every and seed % self.options.release_every == 0:
            modes.append(RELEASE_MODE)
        rc_problems = []
        for name, flags in modes:
            res = self.run(path, flags)
            rc_problems += self.compare(name, res, base)
            if name == "stats":
                verdict = self.balanced(res[3])
                if verdict != "ok":
                    rc_problems.append(f"stats counts: {verdict}")
        stress_problems = [] if self.options.no_stress else self.compare(STRESS_MODE[0], self.run(path, STRESS_MODE[1]), base)
        if rc_problems or stress_problems:
            os.replace(path, os.path.join(self.found, f"s{seed}.my"))
            return seed, "RC-DIFF" if rc_problems else "stress-only", rc_problems, stress_problems
        os.remove(path)
        return seed, "ok", [f"exit {base[0]}"], []


def main():
    options = arguments()
    if not os.access(options.compiler, os.X_OK):
        print(f"rc-fuzz: no compiler at {options.compiler} (pass --compiler or set MYLANG)", file=sys.stderr)
        return 2
    fuzz = Fuzz(options)
    tally = {"ok": 0, "invalid": 0, "stress-only": 0, "RC-DIFF": 0}
    findings = []
    seeds = range(options.start, options.start + options.count)
    with concurrent.futures.ThreadPoolExecutor(options.jobs) as ex:
        for seed, status, info, stress in ex.map(fuzz.one, seeds):
            tally[status] += 1
            print(seed, status, "; ".join(info + stress), flush=True)
            if status in ("RC-DIFF", "stress-only"):
                findings.append({"seed": seed, "status": status, "rc": info, "stress": stress,
                                 "program": os.path.join(fuzz.found, f"s{seed}.my")})
    summary = {"compiler": fuzz.compiler, "start": options.start, "count": options.count, "tally": tally, "findings": findings}
    with open(os.path.join(fuzz.out, "summary.json"), "w") as f:
        json.dump(summary, f, indent=2)
    print("rc-fuzz: {ok} ok, {invalid} invalid, {stress-only} stress-only (report only), {RC-DIFF} RC divergences".format(**tally))
    return 1 if tally["RC-DIFF"] else 0


if __name__ == "__main__":
    sys.exit(main())
