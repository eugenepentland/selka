#!/usr/bin/env python3
"""Strict, pinned scale measurements. Run through build-slot, then claim the
reserved CPU pool before starting. Every sample must succeed; source edits and
background seeder settling are outside the measured interval. Separate owned
work roots keep control and candidate caches and snapshots independent.
"""
import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import time
from pathlib import Path


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def source_identity(root):
    h = hashlib.sha256()
    files = sorted(root.glob("*.my"))
    for p in files:
        h.update(p.name.encode() + b"\0" + p.read_bytes())
    return {"sha256": h.hexdigest(), "files": len(files), "lines": sum(p.read_bytes().count(b"\n") for p in files), "bytes": sum(p.stat().st_size for p in files)}


def settle(cache, expected, limit=900):
    start = time.perf_counter()
    while time.perf_counter() - start < limit:
        states = [p for p in cache.glob("modules/*/state.json") if not p.parent.name.startswith("standard-")]
        for p in states:
            state = json.loads(p.read_text())
            if len(state.get("modules", [])) == expected:
                return round(time.perf_counter() - start, 6)
        time.sleep(0.05)
    raise RuntimeError("owned check seeder did not publish the complete project")


def sample(cmd, tree, cpus, expected_tests=None):
    cache = next(Path(s.split("=", 1)[1]) for s in cmd if s.startswith("--cache-dir="))
    before = {str(p): p.stat().st_mtime_ns for p in cache.glob("modules/*/out/*.result.json")} if cmd[1] == "build" else {}
    started = time.perf_counter()
    proc = subprocess.run(["/usr/bin/time", "-f", "__RSS__ %M", "taskset", "-c", cpus] + cmd, cwd=tree, capture_output=True, timeout=1800)
    wall = time.perf_counter() - started
    stdout, stderr = proc.stdout.decode(), proc.stderr.decode()
    if proc.returncode != 0:
        raise RuntimeError(f"measurement failed ({proc.returncode}): {cmd!r}\n{stdout}\n{stderr}")
    rss = re.search(r"__RSS__ (\d+)", stderr)
    out = {"seconds": round(wall, 6), "status": proc.returncode, "max_rss_kib": int(rss.group(1)) if rss else None, "stdout_sha256": hashlib.sha256(proc.stdout).hexdigest()}
    if cmd[1] == "build":
        after = {str(p): p.stat().st_mtime_ns for p in cache.glob("modules/*/out/*.result.json")}
        out["compiled_records"] = sum(before.get(name) != stamp for name, stamp in after.items())
        out["project_variants"] = sum(not p.parent.name.startswith("standard-") for p in cache.glob("modules/*/state.json"))
    if expected_tests is not None:
        counts = re.search(r"(\d+) passed, (\d+) cached, (\d+) failed, (\d+) skipped", stdout)
        if counts is None:
            raise RuntimeError("missing test counts")
        passed, cached, failed, skipped = map(int, counts.groups())
        if passed + cached != expected_tests or failed or skipped:
            raise RuntimeError(f"test coverage {counts.group(0)} does not match {expected_tests}")
        out["tests"] = {"passed": passed, "cached": cached, "failed": failed, "skipped": skipped}
    return out


def edit(path, number, interface=False):
    text = path.read_text()
    if interface:
        text += f"\n\npublic def zz_added_{number}(n: int) -> int:\n    return n + {number}\n"
    else:
        text, count = re.subn(r"(\+ ?)(\d+)(\)[^\n]*EDIT_BODY)", lambda m: f"{m.group(1)}{9100 + number}{m.group(3)}", text, count=1)
        if count != 1:
            raise RuntimeError("missing unique EDIT_BODY marker")
    path.write_text(text)


def ladder(args, step, root):
    tree = root / "src"
    shutil.copytree(args.tier, tree)
    cache = root / "cache"
    scratch = root / "scratch"
    scratch.mkdir()
    os.environ["TMPDIR"] = str(scratch)
    modules = sorted(tree.glob("m[0-9]*.my"))
    middle = modules[len(modules) // 2]
    expected_tests = len(modules) if step == "test" else None
    command = [str(args.mylang), step, "main.my", f"--cache-dir={cache}"]
    if step == "build":
        command += ["--project", "-o", str(root / "prog")]
    if args.whole and step in ("build", "test"):
        command += ["--whole-program"]
    if step == "check" and args.whole:
        # check-project is the same configured graph check, with no module scheduler.
        command[1] = "check-project"
    if step == "run" and args.whole:
        # Explicit report requests intentionally use the whole-program run path.
        command += ["--report"]
    out = {"command": command, "cold": sample(command, tree, args.cpus, expected_tests)}
    if step == "check" and args.seeder:
        out["seeded_after_seconds"] = settle(cache, len(modules) + 1)
    for phase in ("noop", "body", "interface"):
        rows = []
        for n in range(args.samples):
            if phase != "noop":
                edit(middle, n + 1, phase == "interface")
            rows.append(sample(command, tree, args.cpus, expected_tests))
        out[phase] = {"minimum_seconds": min(r["seconds"] for r in rows), "samples": rows}
    return out


def main():
    p = argparse.ArgumentParser()
    p.add_argument("mylang", type=Path)
    p.add_argument("tier", type=Path)
    p.add_argument("work", type=Path)
    p.add_argument("--steps", default="build,check,run")
    p.add_argument("--samples", type=int, default=3)
    p.add_argument("--cpus", default=os.environ.get("MYLANG_MEASURE_CPUS", "2,3,10,11"))
    p.add_argument("--whole", action="store_true")
    p.add_argument("--seeder", action="store_true")
    p.add_argument("--revision", required=True)
    p.add_argument("--json", type=Path, required=True)
    a = p.parse_args()
    if a.samples < 1:
        p.error("samples must be positive")
    a.mylang, a.tier, a.work = (path.resolve() for path in (a.mylang, a.tier, a.work))
    if a.work.exists():
        p.error("work directory must be fresh")
    a.work.mkdir(parents=True)
    result = {"revision": a.revision, "compiler": str(a.mylang), "compiler_sha256": digest(a.mylang), "cpus": a.cpus, "fixture": source_identity(a.tier), "samples": a.samples, "protocol": "admission outside clock; successful samples only; edits outside clock; separate owned caches", "load_start": Path("/proc/loadavg").read_text().split()[0], "steps": {}}
    for step in a.steps.split(","):
        if step not in ("build", "check", "run", "test"):
            p.error("unknown step")
        root = a.work / step
        root.mkdir()
        result["steps"][step] = ladder(a, step, root)
        a.json.write_text(json.dumps(result, indent=1))
        print(step, {k: v["minimum_seconds"] for k, v in result["steps"][step].items() if isinstance(v, dict) and "minimum_seconds" in v}, flush=True)
    result["load_end"] = Path("/proc/loadavg").read_text().split()[0]
    a.json.write_text(json.dumps(result, indent=1))
    print(json.dumps(result, indent=1))


if __name__ == "__main__":
    main()
