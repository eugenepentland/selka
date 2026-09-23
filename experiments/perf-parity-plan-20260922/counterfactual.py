#!/usr/bin/env python3
"""Build counterfactual arms of mylang benchmarks from rewritten manifests.

usage: counterfactual.py NAME [NAME...] --arm ARM=CAT[,CAT...] [--arm ...]
                         [--src DIR] [--work DIR] [--mylang PATH]

For each benchmark NAME (source `<src>/<NAME>.my`), emits the release-policy
manifest once (`emit-qbe --drop-debug --drop-step-checks --drop-frame-checks`,
falling back to `emit-project-qbe` for module programs), verifies that an
unmodified manifest rebuild is byte-identical to the plain build, applies
`rewrite_il.py` per arm, and builds `<work>/<NAME>.<ARM>` with
`mylang build --manifest-file=`. `bench.py --cf ARM` then times those binaries
beside the ordinary arms. The rewrite statistics go to `<work>/<NAME>.cf.json`.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
DEFAULT_MYLANG = ROOT.parents[1] / "perf-audit-20260922/install-a3/bin/mylang"
EMIT_FLAGS = ["--drop-debug", "--drop-step-checks", "--drop-frame-checks"]


def run(cmd, **kw):
    return subprocess.run([str(c) for c in cmd], capture_output=True, text=True, **kw)


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("names", nargs="+")
    ap.add_argument("--arm", action="append", default=[], help="ARM=cat1,cat2")
    ap.add_argument("--src", type=Path, default=HERE / "suite")
    ap.add_argument("--work", type=Path, default=ROOT.parents[1] / "perf-plan-20260922/work/bench")
    ap.add_argument("--mylang", type=Path, default=DEFAULT_MYLANG)
    ap.add_argument("--adapter", type=Path, help="--llvm-adapter for every build (e.g. a copy patched to accept `hlt`)")
    opts = ap.parse_args()
    src_dir, work = opts.src.resolve(), opts.work.resolve()
    work.mkdir(parents=True, exist_ok=True)
    cache = work / "mycache"
    status = 0
    for name in opts.names:
        source = src_dir / f"{name}.my"
        manifest = work / f"{name}.manifest.json"
        project = False
        p = run([opts.mylang, "emit-qbe", source, *EMIT_FLAGS], cwd=src_dir)
        if p.returncode != 0:
            p = run([opts.mylang, "emit-project-qbe", source, *EMIT_FLAGS], cwd=src_dir)
            project = True
        if p.returncode != 0:
            print(f"{name}: emit failed\n{p.stderr[-2000:]}", file=sys.stderr)
            status = 1
            continue
        manifest.write_text(p.stdout)
        extra = ["--project"] if project else []
        # The release path (ReleaseFast, LLVM O3 + LTO) was the plain build's
        # default until 2026-09-23; name it so every arm still measures it.
        extra += ["--backend", "llvm", "--llvm-opt", "3", "--lto"]
        if opts.adapter:
            extra += ["--llvm-adapter", str(opts.adapter)]
        record = {"name": name, "project": project, "arms": {}}
        # control: the unmodified manifest must rebuild the plain binary exactly
        plain, control = work / f"{name}.cf-plain", work / f"{name}.cf-control"
        b1 = run([opts.mylang, "build", source, "-o", plain, "--cache-dir", cache, *extra], cwd=src_dir)
        b2 = run([opts.mylang, "build", source, "-o", control, f"--manifest-file={manifest}", "--cache-dir", cache, *extra], cwd=src_dir)
        identical = b1.returncode == 0 and b2.returncode == 0 and sha(plain) == sha(control)
        record["control_identical"] = identical
        if not identical:
            print(f"{name}: WARNING manifest rebuild differs from plain build ({b1.stderr[-500:]}{b2.stderr[-500:]})", file=sys.stderr)
        for spec in opts.arm:
            arm, cats = spec.split("=", 1)
            rewritten = work / f"{name}.{arm}.json"
            r = run([sys.executable, HERE / "rewrite_il.py", manifest, rewritten, cats])
            if r.returncode != 0:
                print(f"{name} {arm}: rewrite failed\n{r.stderr}", file=sys.stderr)
                status = 1
                continue
            stats = json.loads(r.stdout.strip().splitlines()[-1])
            out = work / f"{name}.{arm}"
            b = run([opts.mylang, "build", source, "-o", out, f"--manifest-file={rewritten}", "--cache-dir", cache, *extra], cwd=src_dir)
            record["arms"][arm] = {"categories": cats, "rewrite": stats, "built": b.returncode == 0,
                                   "stderr": b.stderr[-2000:] if b.returncode else ""}
            print(f"{name} {arm}: {'built' if b.returncode == 0 else 'BUILD FAILED'} {stats}", file=sys.stderr)
            if b.returncode != 0:
                print(b.stderr[-2000:], file=sys.stderr)
                status = 1
        (work / f"{name}.cf.json").write_text(json.dumps(record, indent=1))
    return status


if __name__ == "__main__":
    sys.exit(main())
