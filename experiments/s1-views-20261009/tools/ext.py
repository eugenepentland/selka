#!/usr/bin/env python3
"""Lane S1's Lox and EDA harness (after CE2-X's ce.py and PM's prof cells).

  ext.py build TAG COMPILER        lox and eda, plain and counting (--counters), --release
  ext.py goldens TAG               the 34 EDA golden cases, plain and counting, byte for byte
  ext.py lox-counting TAG          the 6 PM Lox cells: plain and counting print the same
  ext.py arms OUT.json TAG...      pstat arms: 6 Lox cells and 2 EDA designs per tag

Binaries go to .mylang-cache/s1/bin/TAG; runs are pinned off CPUs 2, 3, 10 and 11.
"""
import concurrent.futures, hashlib, json, os, pathlib, shutil, subprocess, sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
CACHE = ROOT / ".mylang-cache/s1"
SLOT = ROOT / "scripts/build-slot.sh"
CPUS = "0,1,4,5,7,8,9,12-19"
LOX_SRC = ROOT / ".mylang-cache/lox/ports/mylang"
EDA_SRC = ROOT / ".mylang-cache/eda-src"
EDA = pathlib.Path("/home/epentland/ai/canopy/eda-bench-wt/claude-eda-bench-newcore")
SCRIPTS = ROOT / ".tmp/lox-scripts"
LOX_CELLS = {
    "vm/fib": ("vm", "fib.34.lox"),
    "vm/string_equality": ("vm", "string_equality.100000.lox"),
    "vm/invocation": ("vm", "invocation.1500000.lox"),
    "vm/method_call": ("vm", "method_call.500000.lox"),
    "tree/invocation": ("tree", "invocation.150000.lox"),
    "tree/equality": ("tree", "equality.300000.lox"),
}
EDA_DESIGNS = ("rds3+flat", "labstation")


def env():
    e = dict(os.environ)
    e["TMPDIR"] = str(ROOT / ".tmp/tmp")
    return e


def build(tag, compiler):
    out = CACHE / "bin" / tag
    out.mkdir(parents=True, exist_ok=True)
    jobs = []
    for name, src, cwd in (("lox", "main.my", LOX_SRC), ("eda", "src/main.my", EDA_SRC)):
        for kind, flags in (("plain", []), ("count", ["--counters"])):
            argv = [str(SLOT), "build", compiler, "build", src, "-o", str(out / f"{name}-{kind}"), "--cache-dir", str(CACHE / "cache" / tag), "--release", *flags]
            jobs.append((f"{name}-{kind}", argv, cwd))
    with concurrent.futures.ThreadPoolExecutor(2) as pool:
        for label, done in zip([j[0] for j in jobs], pool.map(lambda j: subprocess.run(j[1], cwd=j[2], env=env(), capture_output=True, text=True), jobs)):
            print(label, done.returncode, done.stderr[-1500:] if done.returncode else "")
            if done.returncode:
                sys.exit(1)


def eda_args(case, out_dir):
    return ["--model", f"golden/cases/{case['id']}/model.sexp", "--project-dir", f"golden/projects/{case['project']}", "--out-dir", str(out_dir), *case["flags"]]


def goldens(tag):
    cases = json.loads((EDA / "golden/manifest.json").read_text())["cases"]
    bins = CACHE / "bin" / tag
    work = CACHE / "eda-out" / tag

    def one(case):
        result = {}
        for kind in ("plain", "count"):
            d = work / kind / case["id"]
            if d.exists():
                shutil.rmtree(d)
            d.mkdir(parents=True)
            e = env()
            e["MYLANG_COUNTERS"] = str(work / f"{case['id']}.counters.json")
            done = subprocess.run(["taskset", "-c", CPUS, str(bins / f"eda-{kind}"), *eda_args(case, d)], cwd=EDA, env=e, capture_output=True)
            produced = {str(p.relative_to(d)): hashlib.sha256(p.read_bytes()).hexdigest() for p in d.rglob("*") if p.is_file()}
            expected = {n: m["sha256"] for n, m in case["outputs"].items()}
            result[kind] = (done.returncode, produced == expected, done.stdout, done.stderr)
        same = result["plain"][2:] == result["count"][2:] and result["plain"][0] == result["count"][0]
        return case["id"], result["plain"][0] == 0 and result["plain"][1] and result["count"][1] and same

    with concurrent.futures.ThreadPoolExecutor(4) as pool:
        verdicts = dict(pool.map(one, cases))
    bad = [k for k, ok in verdicts.items() if not ok]
    print(f"eda goldens {tag}: {len(verdicts) - len(bad)}/{len(verdicts)} identical (plain and counting)", "FAILED: " + ",".join(bad) if bad else "")
    shutil.rmtree(work, ignore_errors=True)
    return 1 if bad else 0


def lox_counting(tag):
    bins = CACHE / "bin" / tag
    bad = []
    for cell, (engine, script) in LOX_CELLS.items():
        outs = []
        for kind in ("plain", "count"):
            e = env()
            e["MYLANG_COUNTERS"] = str(CACHE / f"lox-{tag}.counters.json")
            done = subprocess.run(["taskset", "-c", CPUS, str(bins / f"lox-{kind}"), f"--engine={engine}", str(SCRIPTS / script)], env=e, capture_output=True)
            outs.append((done.returncode, done.stdout, done.stderr))
        ok = outs[0] == outs[1] and outs[0][0] == 0
        print(cell, "same" if ok else "DIFFERENT", outs[0][1][-60:])
        if not ok:
            bad.append(cell)
    return 1 if bad else 0


def arms(out, tags):
    cases = {c["id"]: c for c in json.loads((EDA / "golden/manifest.json").read_text())["cases"]}
    result = []
    for tag in tags:
        bins = CACHE / "bin" / tag
        for cell, (engine, script) in LOX_CELLS.items():
            result.append({"program": "lox " + cell, "arm": tag, "argv": [str(bins / "lox-plain"), f"--engine={engine}", str(SCRIPTS / script)]})
        for design in EDA_DESIGNS:
            d = CACHE / "eda-pstat" / tag / design
            d.mkdir(parents=True, exist_ok=True)
            result.append({"program": "eda " + design, "arm": tag, "argv": [str(bins / "eda-plain"), *eda_args(cases[design], d)], "cwd": str(EDA)})
    pathlib.Path(out).write_text(json.dumps(result, indent=1))


def main():
    command, rest = sys.argv[1], sys.argv[2:]
    if command == "build":
        build(rest[0], rest[1])
    elif command == "goldens":
        sys.exit(goldens(rest[0]))
    elif command == "lox-counting":
        sys.exit(lox_counting(rest[0]))
    elif command == "arms":
        arms(rest[0], rest[1:])
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
