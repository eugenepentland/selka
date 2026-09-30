#!/usr/bin/env python3
"""MODULE-SCHEDULE-1..4 equivalence harness: the default `mylang build` of a
project (module by module) against `mylang build --whole-program`.

usage: module_build_oracle.py MYLANG ENTRY_OR_DIR... [--jobs N] [--json OUT]
                              [--mode MODE] [--work DIR] [--keep] [--no-run]

For every program (a directory contributes each `*.my` under it; an entry
without `main` is built through a generated driver module that imports it),
it builds the program both ways into separate caches, with `--report`, and
asserts: the default build took the per-module path (its report has
`module_build`), both executables are identical byte for byte, and, unless
--no-run, running both gives the same stdout, stderr and exit status. It then
builds the default path once more and asserts that nothing was compiled (every
module reused). Exit status 1 when anything differs or fails.
"""
import argparse
import concurrent.futures
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

MAIN = re.compile(r"^(public\s+)?def\s+main\s*\(", re.M)


def entries(paths):
    out = []
    for path in paths:
        p = Path(path)
        if p.is_dir():
            out += sorted(q for q in p.rglob("*.my") if ".mylang-cache" not in q.parts)
        else:
            out.append(p)
    return out


def run(cmd, cwd=None, timeout=900):
    try:
        return subprocess.run(cmd, cwd=cwd, capture_output=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        return None


def report_of(proc):
    for line in proc.stdout.decode("utf-8", "replace").splitlines():
        if line.startswith('{"version":"qbe-build-v1"'):
            return json.loads(line)
    return None


def compare(args, number, entry, root):
    work = root / f"{number:04d}-{entry.stem}"
    shutil.rmtree(work, ignore_errors=True)
    work.mkdir(parents=True)
    out = {"entry": str(entry), "status": "equal", "problems": []}
    source = entry.read_text()
    target = entry.resolve()
    named = bool(re.search(r"^module\s", source, re.M))
    if not MAIN.search(source) or not named:
        mirror = work / "src"
        shutil.copytree(entry.parent, mirror, ignore=shutil.ignore_patterns(".mylang-cache"))
        target = mirror / entry.name
        if not named:
            target.write_text(f"module {entry.stem}; " + source)
        if not MAIN.search(source):
            target = mirror / f"mbdrv_{entry.stem}.my"
            target.write_text(f"module mbdrv_{entry.stem}\nimport {entry.stem}\n\n\ndef main() -> int:\n    return 0\n")
    mylang = str(Path(args.mylang).resolve())
    mode = ["--mode", args.mode] if args.mode else []
    runtime = ["--gc-runtime" if args.runtime == "gc" else "--rc-runtime" if args.runtime == "rc" else f"--rc-runtime={args.runtime}"]
    mode += runtime
    whole = run([mylang, "build", str(target), "--project", "-o", str(work / "whole"), f"--cache-dir={work / 'cw'}", "--whole-program"] + mode)
    if whole is None or whole.returncode != 0:
        out["status"] = "reference-failed"
        out["problems"].append((whole.stderr.decode("utf-8", "replace")[-800:] if whole else "timeout"))
        return out
    module = run([mylang, "build", str(target), "--project", "-o", str(work / "module"), f"--cache-dir={work / 'cm'}", "--report"] + mode)
    if module is None or module.returncode != 0:
        out["status"] = "different"
        out["problems"].append("module build failed: " + (module.stderr.decode("utf-8", "replace")[-800:] if module else "timeout"))
        return out
    report = report_of(module)
    if report is None or report.get("module_build") is None:
        out["problems"].append("the default build did not take the per-module path")
    else:
        out["modules"] = report["module_build"]["modules"]
    if whole.stderr != module.stderr:
        out["problems"].append("the builds' warnings differ")
        out["warnings"] = {"whole": whole.stderr.decode("utf-8", "replace"), "module": module.stderr.decode("utf-8", "replace")}
    if (work / "whole").read_bytes() != (work / "module").read_bytes():
        out["problems"].append("executables differ")
    again = run([mylang, "build", str(target), "--project", "-o", str(work / "module"), f"--cache-dir={work / 'cm'}", "--report"] + mode)
    again_report = report_of(again) if again is not None and again.returncode == 0 else None
    if again_report is None or (again_report.get("module_build") or {}).get("compiled") != 0:
        out["problems"].append("an unchanged rebuild compiled a module")
    if not args.no_run:
        results = []
        for exe in (work / "whole", work / "module"):
            proc = run([str(exe)], cwd=work, timeout=60)
            results.append(None if proc is None else (proc.returncode, proc.stdout, proc.stderr))
        if any(result is None for result in results):
            out["problems"].append("an executable timed out")
        elif results[0] != results[1]:
            out["problems"].append("runs differ")
    if out["problems"]:
        out["status"] = "different"
    elif not args.keep:
        shutil.rmtree(work, ignore_errors=True)
    return out


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("mylang")
    parser.add_argument("paths", nargs="+")
    parser.add_argument("--jobs", type=int, default=min(8, os.cpu_count() or 1))
    parser.add_argument("--json")
    parser.add_argument("--mode")
    parser.add_argument("--runtime", choices=("rc", "gc", "stats", "sites"), default="rc")
    parser.add_argument("--work")
    parser.add_argument("--keep", action="store_true")
    parser.add_argument("--no-run", action="store_true")
    args = parser.parse_args()
    root = Path(args.work or tempfile.mkdtemp(prefix="module-build-oracle-")).resolve()
    root.mkdir(parents=True, exist_ok=True)
    todo = entries(args.paths)
    if not todo:
        parser.error("the accepted corpus must contain at least one entry")
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as pool:
        results = list(pool.map(lambda item: compare(args, item[0], item[1], root), enumerate(todo)))
    totals = {"programs": len(results), "equal": 0, "reference_failed": 0, "modules": 0, "different": []}
    for result in results:
        if result["status"] == "reference-failed":
            totals["reference_failed"] += 1
        elif result["status"] == "equal":
            totals["equal"] += 1
            totals["modules"] += result.get("modules", 0)
        else:
            totals["different"].append({"entry": result["entry"], "problems": result["problems"][:4]})
    if args.json:
        Path(args.json).write_text(json.dumps({"totals": totals, "results": results}, indent=1))
    print(json.dumps(totals, indent=1))
    if not args.keep and not totals["different"]:
        shutil.rmtree(root, ignore_errors=True)
    return 0 if not totals["different"] and not totals["reference_failed"] and totals["equal"] == totals["programs"] else 1


if __name__ == "__main__":
    sys.exit(main())
