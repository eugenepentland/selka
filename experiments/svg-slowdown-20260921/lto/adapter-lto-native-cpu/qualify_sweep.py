#!/usr/bin/env python3
"""Build every `.my` file under the language tree with both backend arms.

    qualify_sweep.py [--jobs N] [--json OUT] [--roots ...] [--only GLOB]

The qualification gate for the LLVM arm is *build coverage*, not test coverage:
a guest test suite only builds the entry points some suite reaches, so an
unsupported opcode in a construct no test exercises stays invisible.  This walks
every `.my` file under the requested roots, builds it twice — once through the
default QBE tool and once through `qbe_llvm.py` — with identical flags and
separate caches, and records both outcomes.

A file that fails in both arms is not a backend finding (it is a fragment, a
negative fixture, or an entry point that needs `--project`); only a file the QBE
arm builds and the LLVM arm refuses is an LLVM-arm coverage failure.  Every
record keeps the LLVM `ParseError` verbatim.
"""

from __future__ import annotations

import argparse
import concurrent.futures
import fnmatch
import hashlib
import json
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

from qualify_identity import identity

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
ADAPTER = HERE / "qbe_llvm.py"

#: The default roots, in the order the qualification task names them.
ROOTS = ("tests/lang", "tests", "examples", "experiments/sexpr-port")

PARSE_ERROR = re.compile(r"qbe_llvm: ([^\s:]+):(\d+): (.*)")


def entries(roots):
    """Every `.my` file under the roots, deduplicated and path-sorted."""
    found = {}
    for root in roots:
        base = REPO / root
        if not base.is_dir():
            continue
        for path in base.rglob("*.my"):
            found[path.resolve()] = path
    return [found[key] for key in sorted(found)]


def build(mylang, source, output, cache, mode, tool):
    """Build one file with one arm, returning (status, stdout, stderr, ms)."""
    command = [str(mylang), "build", str(source), "-o", str(output),
               f"--mode={mode}", f"--cache-dir={cache}", "--keep-symbols"]
    if tool is not None:
        command.append(f"--qbe={tool}")
    start = time.perf_counter()
    done = subprocess.run(command, capture_output=True, text=True, timeout=1800)
    return (done.returncode, done.stdout, done.stderr, (time.perf_counter() - start) * 1000.0)


def build_error(stderr):
    """The first backend diagnostic in one arm's stderr, or the last line."""
    match = PARSE_ERROR.search(stderr)
    if match:
        return {"unit": match.group(1), "line": int(match.group(2)), "message": match.group(3).strip()}
    for line in stderr.splitlines():
        if line.strip() and not line.startswith(" "):
            return {"unit": "", "line": 0, "message": line.strip()}
    return {"unit": "", "line": 0, "message": stderr.strip()[-300:]}


def check(index, source, options, scratch):
    """Build one file with both arms and classify the pair of outcomes."""
    binary = scratch / f"{index:04d}.bin"
    record = {"index": index, "path": str(source), "relative": str(source.relative_to(REPO))}
    try:
        qbe = build(options.mylang, source, binary, options.qbe_cache, options.mode, None)
    except subprocess.TimeoutExpired:
        qbe = (124, "", "timeout", 0.0)
    try:
        llvm = build(options.mylang, source, binary, options.llvm_cache, options.mode, str(ADAPTER))
    except subprocess.TimeoutExpired:
        llvm = (124, "", "timeout", 0.0)
    record["qbe"] = {"status": qbe[0], "ms": round(qbe[3], 1),
                     "error": None if qbe[0] == 0 else build_error(qbe[2]),
                     "stderr": qbe[2][-2000:]}
    record["llvm"] = {"status": llvm[0], "ms": round(llvm[3], 1),
                      "error": None if llvm[0] == 0 else build_error(llvm[2]),
                      "stderr": llvm[2][-2000:]}
    record["binary_bytes"] = binary.stat().st_size if binary.exists() and llvm[0] == 0 else None
    if qbe[0] == 0 and llvm[0] == 0:
        record["verdict"] = "both-built"
    elif qbe[0] != 0 and llvm[0] != 0:
        record["verdict"] = "both-failed"
    elif llvm[0] != 0:
        record["verdict"] = "llvm-only-failure"
    else:
        record["verdict"] = "llvm-only-success"
    return record


def worker_caches(options):
    """One warmed cache per arm, copied per worker so builds never contend."""
    seed_qbe = options.work / "seed-qbe"
    seed_llvm = options.work / "seed-llvm"
    warm = REPO / "experiments" / "sexpr-port" / "main.my"
    for seed, tool in ((seed_qbe, None), (seed_llvm, str(ADAPTER))):
        if seed.exists():
            continue
        seed.mkdir(parents=True)
        build(options.mylang, warm, options.work / "warm.bin", seed, "ReleaseFast", tool)
    caches = []
    for index in range(options.jobs):
        pair = (options.work / f"cache-qbe-{index}", options.work / f"cache-llvm-{index}")
        for seed, target in ((seed_qbe, pair[0]), (seed_llvm, pair[1])):
            if not target.exists():
                shutil.copytree(seed, target)
        caches.append(pair)
    return caches


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--mylang", default=str(REPO / "zig-out" / "bin" / "mylang"))
    parser.add_argument("--work", default="/tmp/llvm-qual")
    parser.add_argument("--json", dest="out")
    parser.add_argument("--jobs", type=int, default=10)
    parser.add_argument("--mode", default="ReleaseFast")
    parser.add_argument("--roots", nargs="*", default=list(ROOTS))
    parser.add_argument("--only", help="fnmatch pattern applied to the repo-relative path")
    parser.add_argument("--limit", type=int, help="build only the first N entries")
    options = parser.parse_args()

    options.mylang = Path(options.mylang)
    options.work = Path(options.work)
    scratch = options.work / "bin"
    options.work.mkdir(parents=True, exist_ok=True)
    scratch.mkdir(exist_ok=True)

    paths = entries(options.roots)
    if options.only:
        paths = [p for p in paths if fnmatch.fnmatch(str(p.relative_to(REPO)), options.only)]
    if options.limit:
        paths = paths[: options.limit]
    if not paths:
        raise SystemExit("no entries matched")

    caches = worker_caches(options)
    report = {
        "tool": "qualify_sweep.py",
        "compiler": str(options.mylang),
        "compiler_sha256": hashlib.sha256(options.mylang.read_bytes()).hexdigest(),
        "identity_start": identity(options.mylang),
        "adapter_sha256": hashlib.sha256(ADAPTER.read_bytes()).hexdigest(),
        "adapter_sources": {path.name: hashlib.sha256(path.read_bytes()).hexdigest()
                            for path in sorted(HERE.glob("*.py"))},
        "mode": options.mode,
        "roots": options.roots,
        "jobs": options.jobs,
        "entries": len(paths),
        "started": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "results": [],
    }
    print(f"{len(paths)} entries, {options.jobs} workers", flush=True)

    done = 0
    with concurrent.futures.ThreadPoolExecutor(max_workers=options.jobs) as pool:
        futures = {}
        for index, path in enumerate(paths):
            qbe_cache, llvm_cache = caches[index % options.jobs]
            local = argparse.Namespace(**vars(options))
            local.qbe_cache = qbe_cache
            local.llvm_cache = llvm_cache
            futures[pool.submit(check, index, path, local, scratch)] = path
        for future in concurrent.futures.as_completed(futures):
            record = future.result()
            report["results"].append(record)
            done += 1
            if record["verdict"] != "both-built":
                mark = "!!" if record["verdict"] == "llvm-only-failure" else " ~"
                detail = ""
                if record["llvm"]["error"]:
                    detail = " | " + record["llvm"]["error"]["message"][:110]
                print(f"{mark} {record['verdict']:19s} {record['relative']}{detail}", flush=True)
            elif done % 50 == 0:
                print(f"  {done}/{len(paths)}", flush=True)

    report["results"].sort(key=lambda item: item["index"])
    counts = {}
    for record in report["results"]:
        counts[record["verdict"]] = counts.get(record["verdict"], 0) + 1
    report["counts"] = counts
    report["finished"] = time.strftime("%Y-%m-%dT%H:%M:%S%z")
    report["identity_end"] = identity(options.mylang)
    if options.out:
        Path(options.out).write_text(json.dumps(report, indent=1) + "\n")
    print("\n" + ", ".join(f"{key}={value}" for key, value in sorted(counts.items())))
    return 1 if counts.get("llvm-only-failure") else 0


if __name__ == "__main__":
    sys.exit(main())
