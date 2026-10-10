#!/usr/bin/env python3
"""Lane U1 (copied from lane F1): Lox and EDA gates and measurements (adapted from CE2-X's ce.py and PM's arms).

  lane.py build --compiler M --tag T        lox and eda, plain and counting (--release)
  lane.py check --tag T                     Lox and EDA cells: counting on/off identical,
                                            EDA outputs equal to the 34 goldens
  lane.py measure --tags A,B --out J [--rounds N]
                                            interleaved perf stat (CPU 6) of PM's 6 Lox cells plus the VM step loop
                                            and 2 EDA designs for each tag's plain binaries
Builds go through scripts/build-slot.sh; runs stay off CPUs 2, 3, 10, 11.
"""
import argparse, concurrent.futures, hashlib, json, os, random, shutil, statistics, subprocess, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SLOT = ROOT / "scripts/build-slot.sh"
CPUS = "0,1,4-9,12-19"
LOX = ROOT / ".mylang-cache/lox"
LOX_SRC = LOX / "ports/mylang"
EDA = Path("/home/epentland/ai/canopy/eda-bench-wt/claude-eda-bench-newcore")
EDA_SRC = ROOT / ".mylang-cache/eda-src"
WORK = ROOT / ".tmp/u1/lane"
SCRIPTS = ROOT / ".tmp/u1/lox-scripts"
LOX_CELLS = [("vm", "step.10000000"), ("vm", "fib.34"), ("vm", "string_equality.100000"), ("vm", "invocation.1500000"), ("vm", "method_call.500000"),
             ("tree", "invocation.150000"), ("tree", "equality.300000")]
EDA_CELLS = ["rds3+flat", "labstation"]


def env():
    e = dict(os.environ)
    e["TMPDIR"] = str(ROOT / ".tmp/tmp")
    e["MYLANG_CORE_RUNTIME_CACHE"] = str(ROOT / ".mylang-cache/core-runtime")
    return e


def run(argv, cwd=ROOT, extra=None, slot=False, timeout=3600):
    full = [str(SLOT), "build", *map(str, argv)] if slot else ["taskset", "-c", CPUS, *map(str, argv)]
    e = env(); e.update(extra or {})
    done = subprocess.run(full, cwd=cwd, env=e, capture_output=True, timeout=timeout)
    return done.returncode, done.stdout, done.stderr


def bins(tag):
    return WORK / "bin" / tag


def build(a):
    out = bins(a.tag); out.mkdir(parents=True, exist_ok=True)
    cache = WORK / "cache" / a.tag
    jobs = []
    for kind, counting in (("plain", False), ("count", True)):
        jobs.append(("lox-" + kind, LOX_SRC / "main.my", LOX_SRC, counting))
        jobs.append(("eda-" + kind, "src/main.my", EDA_SRC, counting))
    def one(job):
        label, source, cwd, counting = job
        argv = [Path(a.compiler).resolve(), "build", source, "-o", out / label, "--cache-dir", cache, "--release"] + (["--counters"] if counting else [])
        status, _, err = run(argv, cwd=cwd, slot=True)
        return label, status, err.decode(errors="replace")[-2000:]
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        for label, status, err in pool.map(one, jobs):
            print(f"build {a.tag} {label}: {status}" + ("" if status == 0 else "\n" + err), flush=True)


def eda_args(case, outdir):
    return ["--model", f"golden/cases/{case['id']}/model.sexp", "--project-dir", f"golden/projects/{case['project']}", "--out-dir", str(outdir), *case["flags"]]


def tree_digest(directory):
    return {str(p.relative_to(directory)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(directory.rglob("*")) if p.is_file()}


def check(a):
    b = bins(a.tag)
    results = {"lox": {}, "eda": {}}
    for engine, script in LOX_CELLS:
        path = SCRIPTS / f"{script}.lox"
        counts = WORK / "counts" / a.tag / f"lox-{engine}-{script}.json"; counts.parent.mkdir(parents=True, exist_ok=True)
        sc, oc, ec = run([b / "lox-count", f"--engine={engine}", path], extra={"MYLANG_COUNTERS": str(counts)})
        sp, op, ep = run([b / "lox-plain", f"--engine={engine}", path])
        results["lox"][f"{engine}/{script}"] = {"same": (sc, oc, ec) == (sp, op, ep), "status": sp, "stdout_sha256": hashlib.sha256(op).hexdigest()}
    cases = json.loads((EDA / "golden/manifest.json").read_text())["cases"]
    def one(case):
        outs = {}
        for kind in ("plain", "count"):
            d = WORK / "eda-out" / a.tag / kind / case["id"]
            if d.exists(): shutil.rmtree(d)
            d.mkdir(parents=True)
            extra = {"MYLANG_COUNTERS": str(WORK / "counts" / a.tag / f"eda-{case['id']}.json")} if kind == "count" else None
            status, out, err = run([b / f"eda-{kind}", *eda_args(case, d)], cwd=EDA, extra=extra, timeout=900)
            outs[kind] = (status, out, err, tree_digest(d))
        expected = {name: meta["sha256"] for name, meta in case["outputs"].items()}
        return case["id"], {"same": outs["plain"] == outs["count"], "golden": outs["plain"][3] == expected and outs["count"][3] == expected, "status": outs["plain"][0]}
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        for cid, r in pool.map(one, cases):
            results["eda"][cid] = r
    lox_ok = all(r["same"] and r["status"] == 0 for r in results["lox"].values())
    eda_same = sum(r["same"] for r in results["eda"].values()); eda_golden = sum(r["golden"] for r in results["eda"].values())
    print(f"lox cells counting on/off identical: {sum(r['same'] for r in results['lox'].values())}/{len(results['lox'])} (all exit 0: {lox_ok})")
    print(f"eda: counting on/off identical {eda_same}/{len(cases)}; golden {eda_golden}/{len(cases)}")
    out = Path(a.out) if a.out else None
    if out: out.write_text(json.dumps(results, indent=1, sort_keys=True))
    return 0 if lox_ok and eda_same == len(cases) and eda_golden == len(cases) else 1


def stat(argv, cwd, cpu):
    events = "cpu_core/instructions/u,cpu_core/cycles/u"
    p = subprocess.run(["taskset", "-c", str(cpu), "perf", "stat", "-x,", "-e", events, "--", *map(str, argv)], cwd=cwd,
                       stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True, timeout=900)
    row = {"status": p.returncode}
    for line in p.stderr.splitlines():
        f = line.split(",")
        if len(f) > 2 and f[2].startswith("cpu_core/"):
            try: row[f[2][9:].rsplit("/", 1)[0]] = int(f[0])
            except ValueError: pass
    return row


def measure(a):
    tags = a.tags.split(",")
    cases = {c["id"]: c for c in json.loads((EDA / "golden/manifest.json").read_text())["cases"]}
    cells = [(f"lox {e}/{s}", lambda tag, e=e, s=s: ([bins(tag) / "lox-plain", f"--engine={e}", SCRIPTS / f"{s}.lox"], ROOT)) for e, s in LOX_CELLS]
    def eda_cell(cid):
        def argv(tag):
            d = WORK / "eda-measure" / tag / cid
            if d.exists(): shutil.rmtree(d)
            d.mkdir(parents=True)
            return [bins(tag) / "eda-plain", *eda_args(cases[cid], d)], EDA
        return (f"eda {cid}", argv)
    cells += [eda_cell(c) for c in EDA_CELLS]
    rng = random.Random(20261009)
    result = {}
    for name, make in cells:
        samples = {t: [] for t in tags}
        for _ in range(a.rounds):
            order = list(tags); rng.shuffle(order)
            for t in order:
                argv, cwd = make(t)
                samples[t].append(stat(argv, cwd, a.cpu))
        med = {t: {e: statistics.median([s[e] for s in samples[t]]) for e in ("instructions", "cycles")} for t in tags}
        result[name] = {"median": med, "samples": samples}
        first = tags[0]
        print(f"{name}: " + " | ".join(f"{t} {med[t]['instructions']/1e6:.0f}Mi {med[t]['cycles']/1e6:.0f}Mc i/{first} {med[t]['instructions']/med[first]['instructions']:.3f} c/{first} {med[t]['cycles']/med[first]['cycles']:.3f}" for t in tags), flush=True)
    Path(a.out).write_text(json.dumps(result, indent=1))


def main():
    p = argparse.ArgumentParser()
    s = p.add_subparsers(dest="cmd", required=True)
    b = s.add_parser("build"); b.add_argument("--compiler", required=True); b.add_argument("--tag", required=True)
    c = s.add_parser("check"); c.add_argument("--tag", required=True); c.add_argument("--out")
    m = s.add_parser("measure"); m.add_argument("--tags", required=True); m.add_argument("--out", required=True)
    m.add_argument("--rounds", type=int, default=5); m.add_argument("--cpu", type=int, default=6)
    a = p.parse_args()
    if a.cmd == "measure" and a.cpu in (2, 3, 10, 11): raise SystemExit("reserved CPU")
    sys.exit({"build": build, "check": check, "measure": measure}[a.cmd](a) or 0)


if __name__ == "__main__":
    main()
