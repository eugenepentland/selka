#!/usr/bin/env python3
"""FS-X run 2: which programs' release LLVM the versioning fix changed (coordinator, 2026-10-09).

Emits the release LLVM of every parity program, Lox and EDA with run 1's compiler and with
run 2's, and lists the programs whose text differs. Only those are timed again; the rest
keep run 1's timing, since identical LLVM gives identical code.
usage: llvm_diff.py OUT.json
"""
import concurrent.futures, json, os, subprocess, sys
from pathlib import Path

WT = Path(__file__).resolve().parents[3]
OLD = "/home/epentland/.cache/mylang/fs-final-x-run1/bin/mylang"
NEW = "/home/epentland/.cache/mylang/fs-final-x/bin/mylang"
WORK = WT / ".mylang-cache/cex/llvm-diff"
CLOCK = WT / "benchmarks/runtime/ports/native_clock.c"


def emit(compiler, tag, label, source, cwd, links):
    out = WORK / tag / f"{label}.ll"
    out.parent.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ, TMPDIR=str(WORK / "tmp"), MYLANG_CORE_RUNTIME_CACHE=str(WORK / "rt"))
    (WORK / "tmp").mkdir(parents=True, exist_ok=True)
    argv = ["taskset", "-c", "0,1,4-9,12-19", compiler, "build", str(source), "-o", str(WORK / tag / f"{label}.bin"),
            "--release", "--emit-llvm", str(out), "--cache-dir", str(WORK / tag / "cache")]
    for link in links:
        argv += ["--link", str(link)]
    subprocess.run(argv, cwd=cwd, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return out.read_bytes() if out.exists() else None


def main():
    jobs = []
    for group in ("suite", "micro", "lib"):
        for source in sorted((WT / "bench/parity" / group).glob("*.my")):
            jobs.append((f"parity:{source.stem}", source, source.parent, []))
    for source in sorted((WT / "test/core").glob("row_*.my")) + [WT / f"test/core/{n}.my" for n in
                  ("binary_search", "int_math", "float_math", "call_direct", "branch_mixed", "branch_predictable")]:
        jobs.append((f"row:{source.stem.removeprefix('row_')}", source, source.parent, [CLOCK]))
    lox = WT / ".mylang-cache/lox/ports/mylang"
    jobs.append(("lox", lox / "main.my", lox, []))
    eda = WT / ".mylang-cache/cex/eda-src"
    jobs.append(("eda", eda / "src/main.my", eda, []))

    def one(job):
        label, source, cwd, links = job
        old = emit(OLD, "run1", label.replace(":", "-"), source, cwd, links)
        new = emit(NEW, "run2", label.replace(":", "-"), source, cwd, links)
        return label, ("missing" if old is None or new is None else "identical" if old == new else "changed")

    with concurrent.futures.ThreadPoolExecutor(4) as pool:
        result = dict(pool.map(one, jobs))
    changed = sorted(k for k, v in result.items() if v != "identical")
    Path(sys.argv[1]).write_text(json.dumps({"old": OLD, "new": NEW, "programs": result, "changed": changed}, indent=1))
    print(f"{len(result)} programs, {len(changed)} not identical: {changed}")
    import gzip
    with gzip.open(WT / "experiments/fs-x-20261009/run1/results/parity-final.json.gz", "rt") as handle:
        benchmarks = set(json.load(handle)["benchmarks"])

    def benchmark(stem):
        while stem not in benchmarks and "_" in stem:
            stem = stem.rsplit("_", 1)[0]
        return stem

    parity = sorted({benchmark(k.split(":", 1)[1]) for k in changed if k.startswith("parity:")})
    print("PARITY_FILTER=" + ",".join(parity))
    print("LOX_CHANGED=" + ("1" if "lox" in changed else "0"))
    print("EDA_CHANGED=" + ("1" if "eda" in changed else "0"))


if __name__ == "__main__":
    main()
