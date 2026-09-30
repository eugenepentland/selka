#!/usr/bin/env python3
"""MODULE-CHECK-1 equivalence harness: `mylang check` of a project (module by
module) against the whole-program check (`check --no-cache`).

usage: module_check_oracle.py MYLANG ENTRY_OR_DIR... [--jobs N] [--json OUT]
                              [--work DIR] [--keep]

For every program (a directory contributes each `*.my` under it; an entry
without `main` is checked through a generated driver module that imports it,
since `check` of a library goes to the whole-program check), it checks the
program both ways, the per-module check over a fresh cache, and asserts the
same exit status, standard output and standard error. When the whole-program
check accepts the program, the per-module check must have taken the
per-module path (its variant's `state.json` exists); it then deletes every
module's result file and checks again, and asserts the same output and that no
module was checked again (no result file came back). Exit status 1 when
anything differs.
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
RUNTIMES = {"rc": ["--rc-runtime"], "gc": ["--gc-runtime"], "gc-stress": ["--gc-runtime", "--gc-stress"], "stats": ["--rc-runtime=stats"], "sites": ["--rc-runtime=sites"]}


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
        proc = subprocess.run(cmd, cwd=cwd, capture_output=True, timeout=timeout)
        return (proc.returncode, proc.stdout, proc.stderr)
    except subprocess.TimeoutExpired:
        return None


def variants(cache):
    root = cache / "modules"
    return [d for d in root.iterdir() if d.is_dir() and not d.name.startswith("standard-")] if root.is_dir() else []


def compare(args, number, entry, root):
    work = root / f"{number:04d}-{entry.stem}"
    shutil.rmtree(work, ignore_errors=True)
    work.mkdir(parents=True)
    out = {"entry": str(entry), "status": "equal", "path": "whole", "problems": []}
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
            target = mirror / f"mcdrv_{entry.stem}.my"
            target.write_text(f"module mcdrv_{entry.stem}\nimport {entry.stem}\n\n\ndef main() -> int:\n    return 0\n")
    mylang = str(Path(args.mylang).resolve())
    cache = work / "cm"
    whole = run([mylang, "check", *RUNTIMES[args.runtime], str(target), "--no-cache"], cwd=target.parent)
    module = run([mylang, "check", *RUNTIMES[args.runtime], str(target), f"--cache-dir={cache}"], cwd=target.parent)
    if whole is None or module is None:
        out["status"] = "different"
        out["problems"].append("a check timed out")
        return out
    if whole != module:
        out["problems"].append(f"outputs differ: whole rc={whole[0]} module rc={module[0]}\n{whole[2][-400:]!r}\n{module[2][-400:]!r}")
    out["reference_failed"] = whole[0] != 0
    if whole[0] == 0:
        found = variants(cache)
        if not found or not (found[0] / "state.json").exists():
            out["problems"].append("an accepted program did not take the per-module check")
        else:
            out["path"] = "module"
            results = list(found[0].glob("out/*.result.json"))
            out["modules"] = len(results)
            for result in results:
                result.unlink()
            states = {str(p.relative_to(cache)): (p.read_bytes(), p.stat().st_mtime_ns, p.stat().st_ino)
                      for p in cache.glob("modules/*/state.json")}
            again = run([mylang, "check", *RUNTIMES[args.runtime], str(target), f"--cache-dir={cache}"], cwd=target.parent)
            if again != module:
                out["problems"].append("an unchanged re-check printed something else")
            if list(found[0].glob("out/*.result.json")):
                out["problems"].append("an unchanged re-check checked a module again")
            after = {str(p.relative_to(cache)): (p.read_bytes(), p.stat().st_mtime_ns, p.stat().st_ino)
                     for p in cache.glob("modules/*/state.json")}
            if after != states:
                out["problems"].append("an unchanged re-check rewrote its locked state files")
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
    parser.add_argument("--work")
    parser.add_argument("--keep", action="store_true")
    parser.add_argument("--runtime", choices=RUNTIMES, default="rc")
    args = parser.parse_args()
    root = Path(args.work or tempfile.mkdtemp(prefix="module-check-oracle-")).resolve()
    root.mkdir(parents=True, exist_ok=True)
    todo = entries(args.paths)
    if not todo:
        parser.error("no programs selected")
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as pool:
        results = list(pool.map(lambda item: compare(args, item[0], item[1], root), enumerate(todo)))
    totals = {"programs": len(results), "equal": 0, "reference_failed": sum(r.get("reference_failed", False) for r in results), "per_module": 0, "whole_program": 0, "modules": 0, "different": []}
    for result in results:
        if result["status"] == "equal":
            totals["equal"] += 1
            totals["per_module" if result["path"] == "module" else "whole_program"] += 1
            totals["modules"] += result.get("modules", 0)
        else:
            totals["different"].append({"entry": result["entry"], "problems": result["problems"][:4]})
    if args.json:
        Path(args.json).write_text(json.dumps({"totals": totals, "results": results}, indent=1))
    print(json.dumps(totals, indent=1))
    if not args.keep and not totals["different"]:
        shutil.rmtree(root, ignore_errors=True)
    return 0 if not totals["different"] and not totals["reference_failed"] else 1


if __name__ == "__main__":
    sys.exit(main())
