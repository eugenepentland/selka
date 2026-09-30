#!/usr/bin/env python3
"""MODULE-TEST-1 equivalence harness: `mylang test` of an entry (module by
module) against `mylang test --whole-program`.

usage: module_test_oracle.py MYLANG ENTRY_OR_DIR... [--jobs N] [--json OUT]
                             [--work DIR] [--keep] [--gc-stress]

For every entry (a directory contributes each `*.my` under it), it runs the
tests both ways, each over a fresh cache, and asserts the same exit status and
the same report on standard output. The per-module run must have taken the
per-module path: its trace (`MYLANG_TEST_TRACE`) names a module compile or no
compiler child at all, and never a `native-test-compile` session. It then runs
both again unchanged and asserts the same reports again, and that the
per-module rerun compiled no module, and linked no library unless a test that
is not cacheable ran again. Exit status 1 when anything differs.
"""
import argparse
import concurrent.futures
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
RUNTIMES = {"rc": ["--rc-runtime"], "gc": ["--gc-runtime"], "stats": ["--rc-runtime=stats"], "sites": ["--rc-runtime=sites"]}


def entries(paths):
    out = []
    for path in paths:
        p = Path(path)
        if p.is_dir():
            out += sorted(q for q in p.rglob("*.my") if ".mylang-cache" not in q.parts)
        else:
            out.append(p)
    return out


def run(cmd, cwd, trace=None, timeout=900):
    env = dict(os.environ)
    env.pop("MYLANG_TEST_TRACE", None)
    if trace:
        env["MYLANG_TEST_TRACE"] = str(trace)
    try:
        proc = subprocess.run(cmd, cwd=cwd, capture_output=True, timeout=timeout, env=env)
        return (proc.returncode, proc.stdout, proc.stderr)
    except subprocess.TimeoutExpired:
        return None


def lines(path):
    return path.read_text().splitlines() if path.exists() else []


def compare(args, number, entry, root):
    work = root / f"{number:04d}-{entry.stem}"
    shutil.rmtree(work, ignore_errors=True)
    work.mkdir(parents=True)
    out = {"entry": str(entry), "status": "equal", "problems": []}
    mylang = str(Path(args.mylang).resolve())
    target = str(entry.resolve())
    extra = RUNTIMES["gc" if args.gc_stress else args.runtime] + (["--gc-stress"] if args.gc_stress else [])
    trace = work / "trace.txt"
    module = run([mylang, "test", target, "--cache-dir", str(work / "cm")] + extra, entry.parent, trace)
    whole = run([mylang, "test", target, "--cache-dir", str(work / "cw"), "--whole-program"] + extra, entry.parent)
    if module is None or whole is None:
        out["problems"].append("a test run timed out")
    else:
        out["no_tests"] = whole == (3, b"0 passed, 0 cached, 0 failed, 0 skipped\n", b"")
        out["reference_failed"] = whole[0] != 0 and not out["no_tests"]
        out["tests"] = sum(line.startswith((b"passed ", b"failed ", b"reused ")) for line in whole[1].splitlines())
        if module != whole:
            out["problems"].append(f"reports differ: module rc={module[0]} whole rc={whole[0]}\n{module[1][-600:]!r}\n{whole[1][-600:]!r}")
            out["stderr"] = {"module": module[2].decode(errors="replace"), "whole": whole[2].decode(errors="replace")}
        cold = lines(trace)
        if any("native-test-compile" in line for line in cold):
            out["problems"].append("the per-module run started a whole-program session")
        out["modules"] = sum(1 for line in cold if line.startswith("compile-module "))
        trace.unlink(missing_ok=True)
        module_again = run([mylang, "test", target, "--cache-dir", str(work / "cm")] + extra, entry.parent, trace)
        whole_again = run([mylang, "test", target, "--cache-dir", str(work / "cw"), "--whole-program"] + extra, entry.parent)
        if module_again is None or whole_again is None:
            out["problems"].append("an unchanged test run timed out")
        elif module_again != whole_again:
            out["problems"].append("unchanged reruns report differently")
            out["warm_reports"] = {"module": None if module_again is None else [module_again[0], module_again[1].decode(errors="replace"), module_again[2].decode(errors="replace")], "whole": None if whole_again is None else [whole_again[0], whole_again[1].decode(errors="replace"), whole_again[2].decode(errors="replace")]}
        warm = lines(trace)
        if any(line.startswith("compile-module ") for line in warm):
            out["problems"].append("an unchanged rerun compiled a module")
        # A test that is not cacheable (it reads a clock, say) runs again and
        # needs a library; one whose receipt answers never does.
        executed = module_again is not None and any(line.startswith((b"passed ", b"failed ")) for line in module_again[1].splitlines())
        if not executed and any(line.startswith("module-link ") for line in warm):
            out["problems"].append("an unchanged rerun that executed nothing linked a library")
    if out["problems"]:
        out["status"] = "different"
    elif not args.keep:
        shutil.rmtree(work, ignore_errors=True)
    return out


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("mylang")
    parser.add_argument("paths", nargs="+")
    parser.add_argument("--jobs", type=int, default=min(6, os.cpu_count() or 1))
    parser.add_argument("--json")
    parser.add_argument("--work")
    parser.add_argument("--keep", action="store_true")
    parser.add_argument("--gc-stress", action="store_true")
    parser.add_argument("--runtime", choices=RUNTIMES, default="rc")
    args = parser.parse_args()
    root = Path(args.work or tempfile.mkdtemp(prefix="module-test-oracle-")).resolve()
    root.mkdir(parents=True, exist_ok=True)
    todo = entries(args.paths)
    if not todo:
        parser.error("no programs selected")
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as pool:
        results = list(pool.map(lambda item: compare(args, item[0], item[1], root), enumerate(todo)))
    totals = {"programs": len(results), "equal": 0, "reference_failed": sum(r.get("reference_failed", False) for r in results), "tests": sum(r.get("tests", 0) for r in results), "no_tests": sum(r.get("no_tests", False) for r in results), "modules": 0, "different": []}
    for result in results:
        if result["status"] == "equal":
            totals["equal"] += 1
            totals["modules"] += result.get("modules", 0)
        else:
            totals["different"].append({"entry": result["entry"], "problems": result["problems"][:4]})
    if args.json:
        Path(args.json).write_text(json.dumps({"totals": totals, "results": results}, indent=1))
    print(json.dumps(totals, indent=1))
    if not args.keep and not totals["different"]:
        shutil.rmtree(root, ignore_errors=True)
    return 0 if not totals["different"] and not totals["reference_failed"] and totals["tests"] else 1


if __name__ == "__main__":
    sys.exit(main())
