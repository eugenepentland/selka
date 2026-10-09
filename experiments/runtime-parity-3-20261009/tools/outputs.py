#!/usr/bin/env python3
"""FU-PORT output gates for one compiler (no timing; runs off CPUs 2, 3, 10, 11; builds through
scripts/build-slot.sh):
  outputs.py --compiler PATH --tag TAG build   lox-plain and eda-plain (--release), every parity .my
  outputs.py --compiler PATH --tag TAG eda     the 34 EDA golden cases, both output dirs byte-identical
  outputs.py --compiler PATH --tag TAG parity  every parity program's stdout equals its .expected, status 0
Binaries land in .mylang-cache/rp3/outputs/bin/TAG; results in experiments/fu-port-20261009/results/TAG-*.json."""
import argparse, concurrent.futures, hashlib, importlib.util, json, os, pathlib, shutil, subprocess, sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
AREA = pathlib.Path(__file__).resolve().parents[1]
CACHE = ROOT / ".mylang-cache/rp3/outputs"
SLOT = ROOT / "scripts/build-slot.sh"
CPUS = "0,1,4-9,12-19"
LOX_SRC = ROOT / ".mylang-cache/lox/ports/mylang"
EDA = pathlib.Path("/home/epentland/ai/canopy/eda-bench-wt/claude-eda-bench-newcore")  # goldens, read only
EDA_SRC = ROOT / ".mylang-cache/eda-src"


def env():
    e = dict(os.environ)
    e["TMPDIR"] = str(ROOT / ".tmp/rp3")
    e.setdefault("MYLANG_CORE_RUNTIME_CACHE", str(ROOT / ".mylang-cache/runtime-rp3-base"))
    return e


def sha(data):
    return hashlib.sha256(data).hexdigest()


def run(argv, cwd=ROOT, slot=False, timeout=3600):
    full = [str(SLOT), "build", *map(str, argv)] if slot else ["taskset", "-c", CPUS, *map(str, argv)]
    try:
        done = subprocess.run(full, cwd=cwd, env=env(), capture_output=True, timeout=timeout)
        return done.returncode, done.stdout, done.stderr
    except subprocess.TimeoutExpired as expired:
        return "timeout", expired.stdout or b"", expired.stderr or b""


def parity_programs():
    spec = importlib.util.spec_from_file_location("bench_parity", ROOT / "bench/parity/bench_parity.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    programs = []
    for bench in module.discover([]):
        for lang, path, variant in bench["ports"]:
            if lang == "my":
                programs.append((f"{bench['group']}/{path.stem}", path, bench["expected"]))
    return programs


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--compiler", required=True)
    parser.add_argument("--tag", required=True)
    parser.add_argument("what")
    args = parser.parse_args()
    compiler = pathlib.Path(args.compiler).resolve()
    bins = CACHE / "bin" / args.tag
    bins.mkdir(parents=True, exist_ok=True)
    cache = CACHE / "cache" / args.tag

    def build(source, output, cwd):
        status, _, err = run([compiler, "build", source, "-o", output, "--cache-dir", cache, "--release"], cwd=cwd, slot=True)
        if status != 0:
            raise SystemExit(f"build failed: {source}\n{err.decode(errors='replace')[-3000:]}")

    if args.what == "build":
        build(LOX_SRC / "main.my", bins / "lox-plain", LOX_SRC)
        build("src/main.my", bins / "eda-plain", EDA_SRC)
        programs = parity_programs()
        with concurrent.futures.ThreadPoolExecutor(3) as pool:
            list(pool.map(lambda p: build(p[1], bins / f"parity-{p[0].replace('/', '-')}", ROOT), programs))
        print(f"built lox, eda and {len(programs)} parity programs", flush=True)
    elif args.what == "eda":
        cases = json.loads((EDA / "golden/manifest.json").read_text())["cases"]
        out_root = CACHE / "eda-out" / args.tag

        def one(case):
            directory = out_root / case["id"]
            if directory.exists():
                shutil.rmtree(directory)
            directory.mkdir(parents=True)
            status, out, err = run([bins / "eda-plain", "--model", f"golden/cases/{case['id']}/model.sexp", "--project-dir", f"golden/projects/{case['project']}", "--out-dir", directory, *case["flags"]], cwd=EDA, timeout=900)
            produced = {str(p.relative_to(directory)): sha(p.read_bytes()) for p in directory.rglob("*") if p.is_file()}
            expected = {name: meta["sha256"] for name, meta in case["outputs"].items()}
            return case["id"], {"status": status, "golden": produced == expected, "stderr": err.decode(errors="replace")[-1000:]}

        with concurrent.futures.ThreadPoolExecutor(4) as pool:
            results = dict(pool.map(one, cases))
        bad = sorted(k for k, v in results.items() if not v["golden"])
        (AREA / "results" / f"{args.tag}-eda.json").write_text(json.dumps(results, indent=1) + "\n")
        print(f"eda: {len(results)} cases, {len(results) - len(bad)} byte-identical to the goldens, differing: {bad}", flush=True)
        sys.exit(1 if bad else 0)
    elif args.what == "parity":
        programs = parity_programs()

        def one(p):
            name, _, expected = p
            status, out, err = run([bins / f"parity-{name.replace('/', '-')}"], timeout=1800)
            return name, {"status": status, "matches_expected": status == 0 and out == expected, "stdout_sha256": sha(out), "expected_sha256": sha(expected)}

        with concurrent.futures.ThreadPoolExecutor(2) as pool:
            results = dict(pool.map(one, programs))
        bad = sorted(k for k, v in results.items() if not v["matches_expected"])
        (AREA / "results" / f"{args.tag}-parity.json").write_text(json.dumps(results, indent=1) + "\n")
        print(f"parity: {len(results)} programs, {len(results) - len(bad)} equal to .expected, differing: {bad}", flush=True)
        sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
