#!/usr/bin/env python3
"""Run the unchanged live-view guests and require balanced counted RC cleanup."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
SOURCES = ["tests/lang/dictionary_views.my", "tests/lang/rc_dictionary_views.my"]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler", type=Path, required=True)
    parser.add_argument("--qbe", type=Path, required=True)
    parser.add_argument("--backend", choices=("qbe", "llvm"), required=True)
    parser.add_argument("--work", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    work = args.work.resolve()
    work.mkdir(parents=True, exist_ok=True)
    spec = importlib.util.spec_from_file_location("collection_probes", ROOT / "experiments/d9-rc-collection-probes-20260926/run.py")
    probe = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(probe)
    entry, cases, source_hashes = probe.prepare(work, SOURCES)
    compiler = args.compiler.resolve()
    binary = work / ("held-views-" + args.backend)
    command = [str(ROOT / "scripts/build-slot.sh"), "build", str(compiler), "build", str(entry),
               "--rc-runtime=stats", "--backend", args.backend, "--mode", "ReleaseFast",
               "--cache-dir=" + str(work / "cache"), "-o", str(binary)]
    command += (["--qbe=" + str(args.qbe.resolve())] if args.backend == "qbe" else ["--llvm-opt", "3", "--lto"])
    subprocess.run(command, cwd=ROOT, check=True)
    run = subprocess.run([str(binary)], cwd=ROOT, capture_output=True, text=True)
    counts = [json.loads(line.removeprefix("MYLANG_RC_COUNTS "))
              for line in run.stderr.splitlines() if line.startswith("MYLANG_RC_COUNTS ")]
    assert run.returncode == 0 and run.stdout.strip() == "0", (run.returncode, run.stdout, run.stderr)
    assert len(counts) == 1 and not counts[0]["saturated"], run.stderr
    count = counts[0]
    assert count["heap_allocate"] == count["retire"], count
    assert count["heap_allocate"] + count["owner_acquire"] == count["owner_release"], count
    assert count["hold_acquire"] == count["hold_release"], count
    result = {"backend": args.backend, "guest_mode": "ReleaseFast", "cases": cases,
              "source_sha256": source_hashes, "compiler_sha256": hashlib.sha256(compiler.read_bytes()).hexdigest(),
              "source_commit": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
              "binary_sha256": hashlib.sha256(binary.read_bytes()).hexdigest(),
              "command": command, "exit": run.returncode, "stdout": run.stdout, "stderr": run.stderr, "counts": count}
    args.output.write_text(json.dumps(result, indent=2) + "\n")
    print(f"{args.backend}: {len(cases)} live-view assertions passed; {count['retire']} allocations retired")


if __name__ == "__main__":
    main()
