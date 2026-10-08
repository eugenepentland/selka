#!/usr/bin/env python3
"""VP3 harness: build ordinary and counting (`--counters`) binaries, run them, compare
outputs, keep the counters JSON (gzipped) and one log per command.

Subcommands:
  prepare            copy the Lox and EDA sources into the cache, record their identity
  build  GROUP       build GROUP's ordinary and counting binaries (lox, eda, parity, rows)
  run    GROUP       run GROUP's cells: counting run (counts) and ordinary run (output check)
  identity           46 rows x {debug, release}: base vs new compiler, LLVM and executable SHA-256

Builds go through scripts/build-slot.sh. Runs are pinned off the timing CPUs 2, 3, 10, 11.
Everything heavy lives under .mylang-cache/vp3; evidence under experiments/vk-vp3-20261008.
"""
import argparse, concurrent.futures, gzip, hashlib, importlib.util, json, os, pathlib, shutil, subprocess, sys, time

ROOT = pathlib.Path(__file__).resolve().parents[3]
AREA = pathlib.Path(__file__).resolve().parents[1]
CACHE = ROOT / ".mylang-cache/vp3"
RF = ROOT / ".mylang-cache/vp3-rf/bin/mylang"          # ReleaseFast compiler of this branch
NEW = ROOT / "zig-out/bin/mylang"                      # Debug compiler of this branch
BASE = ROOT / ".mylang-cache/vp3-base/bin/mylang"      # Debug compiler of deefad751 (before VP3)
SLOT = ROOT / "scripts/build-slot.sh"
CPUS = "0,1,4-9,12-19"
ECORES = "12-19"
LOX_SRC = pathlib.Path("/home/epentland/ai/canopy/mylang-worktrees/codex-s4-lox-value-semantics/benchmarks/lox/ports/mylang")
LOX_SCRIPTS = pathlib.Path("/home/epentland/ai/canopy/mylang-worktrees/claude-bench-newcore/.mylang-cache/bench/lox/bench")
EDA = pathlib.Path("/home/epentland/ai/canopy/eda-bench-wt/claude-eda-bench-newcore")
LOX_TIMED = ["closures", "equality", "fib", "invocation", "method_call", "properties", "string_equality", "strings", "zoo", "zoo_batch"]
LOX_EXTRA = ["instantiation", "binary_trees"]
PARITY = {"nbody": ("suite/nbody", 5_000_000, "steps"), "str_build": ("micro/str_build", 16_000_000, "appends"),
          "matmul": ("suite/matmul", 500 ** 3, "multiply-adds"), "knucleotide": ("suite/knucleotide", 1_000_000, "sequence bytes")}


def env():
    e = dict(os.environ)
    e["TMPDIR"] = str(ROOT / ".tmp")
    e["MYLANG_CORE_RUNTIME_CACHE"] = str(ROOT / ".mylang-cache/core-runtime")
    return e


def digest(path):
    return hashlib.sha256(pathlib.Path(path).read_bytes()).hexdigest()


def log(label, argv, cwd=ROOT, extra_env=None, slot=False, timeout=3600, keep_stdout=False, cpus=CPUS):
    """Run one command and keep its receipt: commands/<label>.json (+ .stderr when non-empty)."""
    directory = AREA / "commands"
    directory.mkdir(parents=True, exist_ok=True)
    full = [str(SLOT), "build", *map(str, argv)] if slot else ["taskset", "-c", cpus, *map(str, argv)]
    e = env()
    e.update(extra_env or {})
    started = time.monotonic()
    try:
        done = subprocess.run(full, cwd=cwd, env=e, capture_output=True, timeout=timeout)
        status, out, err = done.returncode, done.stdout, done.stderr
    except subprocess.TimeoutExpired as expired:
        status, out, err = "timeout", expired.stdout or b"", expired.stderr or b""
    seconds = time.monotonic() - started
    record = {"label": label, "command": full, "cwd": str(cwd), "env": extra_env or {}, "seconds": round(seconds, 3), "status": status,
              "stdout_sha256": hashlib.sha256(out).hexdigest(), "stdout_bytes": len(out), "stderr_sha256": hashlib.sha256(err).hexdigest(), "stderr_bytes": len(err)}
    if len(out) <= 4096 or keep_stdout:
        record["stdout"] = out.decode(errors="replace")[:20000]
    (directory / f"{label}.json").write_text(json.dumps(record, indent=1) + "\n")
    if err:
        (directory / f"{label}.stderr").write_bytes(err[-20000:])
    return record, out, err


def build(label, source, output, cwd, counting, release=True, compiler=RF, cache=None, links=()):
    argv = [compiler, "build", source, "-o", output, "--cache-dir", cache or (CACHE / "cache")]
    if release:
        argv.append("--release")
    if counting:
        argv.append("--counters")
    for link in links:
        argv += ["--link", link]
    record, _, err = log(label, argv, cwd=cwd, slot=True)
    if record["status"] != 0:
        raise SystemExit(f"build failed: {label}\n{err.decode(errors='replace')[-3000:]}")
    return record


def keep_counts(path, name):
    """Gzip one counters document into raw/<name>.json.gz and return it parsed."""
    data = pathlib.Path(path).read_bytes()
    raw = AREA / "raw"
    raw.mkdir(exist_ok=True)
    with gzip.open(raw / f"{name}.json.gz", "wb", compresslevel=9) as f:
        f.write(data)
    return json.loads(data)


# ---- sources -------------------------------------------------------------------------

def prepare():
    for name, source in (("lox", LOX_SRC), ("eda", EDA / "mylang")):
        target = CACHE / "src" / name
        if target.exists():
            shutil.rmtree(target)
        shutil.copytree(source, target, ignore=shutil.ignore_patterns(".mylang-cache", ".cache", "pilot", "probes"))
    identity = {
        "lox": {"path": str(LOX_SRC), "commit": subprocess.check_output(["git", "-C", str(LOX_SRC), "rev-parse", "HEAD"], text=True).strip(),
                "files": {p.name: digest(p) for p in sorted((CACHE / "src/lox").glob("*.my"))}},
        "eda": {"path": str(EDA), "commit": subprocess.check_output(["git", "-C", str(EDA), "rev-parse", "HEAD"], text=True).strip(),
                "src_files": len(list((CACHE / "src/eda/src").glob("*.my")))},
        "lox_scripts": {p.name: digest(p) for p in sorted((LOX_SCRIPTS / "scripts").glob("*.lox"))},
        "compiler_rf": {"path": str(RF), "sha256": digest(RF)},
        "branch_head": subprocess.check_output(["git", "-C", str(ROOT), "rev-parse", "HEAD"], text=True).strip(),
    }
    (AREA / "inputs.json").write_text(json.dumps(identity, indent=1) + "\n")


# ---- programs ------------------------------------------------------------------------

def bins():
    directory = CACHE / "bin"
    directory.mkdir(parents=True, exist_ok=True)
    return directory


def build_group(group):
    out = bins()
    if group == "lox":
        for counting in (False, True):
            build(f"build-lox-{'count' if counting else 'plain'}", CACHE / "src/lox/main.my", out / f"lox-{'count' if counting else 'plain'}", CACHE / "src/lox", counting)
    elif group == "eda":
        for counting in (False, True):
            build(f"build-eda-{'count' if counting else 'plain'}", "src/main.my", out / f"eda-{'count' if counting else 'plain'}", CACHE / "src/eda", counting)
    elif group == "parity":
        for name, (path, _, _) in PARITY.items():
            for counting in (False, True):
                build(f"build-parity-{name}-{'count' if counting else 'plain'}", ROOT / f"bench/parity/{path}.my", out / f"parity-{name}-{'count' if counting else 'plain'}", ROOT, counting)
    elif group == "rows":
        clock = ROOT / "benchmarks/runtime/ports/native_clock.c"
        for name, path in row_sources().items():
            for counting in (False, True):
                build(f"build-row-{name}-{'count' if counting else 'plain'}", path, out / f"row-{name}-{'count' if counting else 'plain'}", ROOT, counting, links=(clock,))


def row_registry():
    path = ROOT / "experiments/new-core-s4-20261006/integration/measure_all46.py"
    spec = importlib.util.spec_from_file_location("vp3_rows", path)
    registry = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(registry)
    assert len(registry.rows.UNITS) == 46
    return registry.rows


def row_sources():
    rows = row_registry()
    return {name: ROOT / "test/core" / (rows.stem(name) + ".my") for name in rows.UNITS}


def counted_run(label, binary_count, binary_plain, args, cwd, timeout, compare_outputs=None, normalize=lambda out: out):
    """The counting run (its counts kept) and the ordinary run; outputs must agree."""
    counts_path = CACHE / "counts" / f"{label}.json"
    counts_path.parent.mkdir(parents=True, exist_ok=True)
    counts_path.unlink(missing_ok=True)
    record_c, out_c, err_c = log(f"run-{label}-count", [binary_count, *args(True)], cwd=cwd, extra_env={"MYLANG_COUNTERS": str(counts_path)}, timeout=timeout)
    perf_path = CACHE / "perf" / f"{label}.csv"
    perf_path.parent.mkdir(parents=True, exist_ok=True)
    perf = ["perf", "stat", "-x,", "-e", "instructions:u", "-o", perf_path, "--"]
    # The instruction count comes from one core type: the E-cores 12-19 (cpu_atom), never the timing CPUs.
    record_p, out_p, err_p = log(f"run-{label}-plain", [*perf, binary_plain, *args(False)], cwd=cwd, timeout=timeout, cpus=ECORES)
    same = record_c["status"] == record_p["status"] and normalize(out_c) == normalize(out_p) and err_c == err_p
    detail = {}
    if compare_outputs:
        detail = compare_outputs()
        same = same and detail.get("same", True)
    counts = keep_counts(counts_path, label) if counts_path.exists() else None
    return {"label": label, "status": record_c["status"], "plain_status": record_p["status"], "same_output": same, "instructions": instructions(perf_path),
            "seconds_count": record_c["seconds"], "seconds_plain": record_p["seconds"], "outputs": detail, "counts": counts is not None}


def instructions(path):
    """User-space instructions retired by the ordinary run (`perf stat`, hybrid PMUs summed)."""
    total = 0
    for line in pathlib.Path(path).read_text().splitlines():
        fields = line.split(",")
        if len(fields) > 2 and "instructions" in fields[2] and fields[0].strip().isdigit():
            total += int(fields[0])
    return total


def lox_sizes():
    return json.loads((LOX_SCRIPTS / "sizes.json").read_text())


def lox_script(name, n):
    text = (LOX_SCRIPTS / "scripts" / f"{name}.lox").read_text()
    first, rest = text.split("\n", 1)
    assert first.startswith("var N = "), first
    directory = CACHE / "lox-scripts"
    directory.mkdir(parents=True, exist_ok=True)
    path = directory / f"{name}-{n}.lox"
    path.write_text(f"var N = {n};\n{rest}")
    return path


def run_lox(cells):
    out = bins()
    results = {}
    jobs = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        for engine, name, n in cells:
            script = lox_script(name, n)
            label = f"lox-{engine}-{name}-{n}"
            args = lambda counting, engine=engine, script=script: [f"--engine={engine}", script]
            jobs.append((label, engine, name, n, pool.submit(counted_run, label, out / "lox-count", out / "lox-plain", args, CACHE, 1800)))
        for label, engine, name, n, job in jobs:
            result = job.result()
            result.update(engine=engine, script=name, n=n)
            results[label] = result
            print(json.dumps({k: result[k] for k in ("label", "status", "same_output", "seconds_count", "seconds_plain")}), flush=True)
    return results


def eda_cases():
    return json.loads((EDA / "golden/manifest.json").read_text())["cases"]


def run_eda():
    out = bins()
    results = {}
    outputs = CACHE / "eda-out"

    def one(case):
        label = f"eda-{case['id']}"
        def args(counting):
            directory = outputs / ("count" if counting else "plain") / case["id"]
            if directory.exists():
                shutil.rmtree(directory)
            directory.mkdir(parents=True)
            return ["--model", f"golden/cases/{case['id']}/model.sexp", "--project-dir", f"golden/projects/{case['project']}", "--out-dir", directory, *case["flags"]]
        def compare():
            mismatched = []
            for kind in ("count", "plain"):
                directory = outputs / kind / case["id"]
                produced = {str(p.relative_to(directory)): digest(p) for p in directory.rglob("*") if p.is_file()}
                expected = {name: meta["sha256"] for name, meta in case["outputs"].items()}
                if produced != expected:
                    mismatched.append(kind)
            return {"same": not mismatched, "golden_mismatch": mismatched}
        result = counted_run(label, out / "eda-count", out / "eda-plain", args, EDA, 600, compare)
        result.update(case=case["id"], flags=case["flags"], model_bytes=case["model_bytes"])
        return label, result

    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        for label, result in pool.map(one, eda_cases()):
            results[label] = result
            print(json.dumps({k: result[k] for k in ("label", "status", "same_output", "seconds_count", "seconds_plain")}), flush=True)
    return results


def run_parity():
    out = bins()
    results = {}
    for name, (path, units, unit_name) in PARITY.items():
        expected = (ROOT / f"bench/parity/{path}.expected").read_bytes()
        label = f"parity-{name}"
        result = counted_run(label, out / f"parity-{name}-count", out / f"parity-{name}-plain", lambda counting: [], CACHE, 1800)
        plain = json.loads((AREA / "commands" / f"run-{label}-plain.json").read_text())
        result.update(program=name, units=units, unit=unit_name, matches_expected=plain["stdout_sha256"] == hashlib.sha256(expected).hexdigest())
        results[label] = result
        print(json.dumps({k: result[k] for k in ("label", "status", "same_output", "matches_expected", "seconds_count")}), flush=True)
    return results


def run_rows(divisor):
    rows = row_registry()
    out = bins()
    results = {}

    def one(name):
        suite, unit, big, small = rows.UNITS[name]
        iterations = max(1, big // divisor)
        size = 4096
        label = f"row-{name}"
        # A row prints `checksum elapsed`; only the checksum is the program's answer.
        result = counted_run(label, out / f"row-{name}-count", out / f"row-{name}-plain", lambda counting: [str(size), str(iterations), "7"], CACHE, 900,
                             normalize=lambda text: text.split()[:1])
        result.update(row=name, unit=unit, size=size, iterations=iterations, work=size * iterations if unit == "element" else iterations)
        return label, result

    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        for label, result in pool.map(one, list(rows.UNITS)):
            results[label] = result
            print(json.dumps({k: result[k] for k in ("label", "status", "same_output", "seconds_count")}), flush=True)
    return results


def first_output_line_differs(record_c, record_p):
    return record_c.get("stdout") != record_p.get("stdout")


# ---- byte identity with counting off -------------------------------------------------

def identity():
    """Base (deefad751) vs this branch, both Debug compilers, counting off: LLVM text and
    executable SHA-256 per row and mode. Each compiler gets its own runtime and unit store,
    so each compiles its own runtime object."""
    clock = ROOT / "benchmarks/runtime/ports/native_clock.c"
    results = {}
    work = CACHE / "identity"

    def one(item):
        name, path, mode = item
        hashes = {}
        for which, compiler in (("base", BASE), ("new", NEW)):
            directory = work / which / f"{name}-{mode}"
            directory.mkdir(parents=True, exist_ok=True)
            argv = [compiler, "build", path, "-o", directory / "exe", "--emit-llvm", directory / "unit.ll", "--cache-dir", directory / "cache", "--link", clock]
            if mode == "release":
                argv.append("--release")
            label = f"identity-{name}-{mode}-{which}"
            record, _, err = log(label, argv, extra_env={"MYLANG_CORE_RUNTIME_CACHE": str(work / which / "runtime-store")})
            if record["status"] != 0:
                raise SystemExit(f"identity build failed: {label}: {err.decode(errors='replace')[-2000:]}")
            hashes[which] = {"llvm": digest(directory / "unit.ll"), "exe": digest(directory / "exe")}
        return f"{name}-{mode}", {"row": name, "mode": mode, **hashes, "llvm_equal": hashes["base"]["llvm"] == hashes["new"]["llvm"], "exe_equal": hashes["base"]["exe"] == hashes["new"]["exe"]}

    items = [(name, path, mode) for name, path in row_sources().items() for mode in ("debug", "release")]
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
        for key, result in pool.map(one, items):
            results[key] = result
            print(key, result["llvm_equal"], result["exe_equal"], flush=True)
    summary = {"base": {"path": str(BASE), "sha256": digest(BASE), "commit": "deefad751a9c8d92e925aac20c0db80f8f336a4d"},
               "new": {"path": str(NEW), "sha256": digest(NEW), "commit": subprocess.check_output(["git", "-C", str(ROOT), "rev-parse", "HEAD"], text=True).strip(),
                       "dirty": subprocess.check_output(["git", "-C", str(ROOT), "status", "--porcelain", "src"], text=True)},
               "comparisons": len(results), "all_llvm_equal": all(r["llvm_equal"] for r in results.values()),
               "all_exe_equal": all(r["exe_equal"] for r in results.values()), "results": results}
    (AREA / "identity.json").write_text(json.dumps(summary, indent=1) + "\n")
    print(json.dumps({k: summary[k] for k in ("comparisons", "all_llvm_equal", "all_exe_equal")}))


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("command")
    parser.add_argument("group", nargs="?")
    parser.add_argument("--cells", help="lox: engine:script:N,... ")
    parser.add_argument("--out", help="results file name under results/")
    parser.add_argument("--divisor", type=int, default=10)
    args = parser.parse_args()
    if args.command == "prepare":
        return prepare()
    if args.command == "build":
        return build_group(args.group)
    if args.command == "identity":
        return identity()
    if args.command == "run":
        if args.group == "lox":
            cells = [tuple(cell.split(":")) for cell in args.cells.split(",")]
            results = run_lox([(e, s, int(n)) for e, s, n in cells])
        elif args.group == "eda":
            results = run_eda()
        elif args.group == "parity":
            results = run_parity()
        elif args.group == "rows":
            results = run_rows(args.divisor)
        else:
            raise SystemExit("unknown group")
        directory = AREA / "results"
        directory.mkdir(exist_ok=True)
        (directory / (args.out or f"{args.group}.json")).write_text(json.dumps(results, indent=1) + "\n")
        return
    raise SystemExit("unknown command")


if __name__ == "__main__":
    main()
