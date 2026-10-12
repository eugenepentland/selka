#!/usr/bin/env python3
"""Native RSS metrology controls; correctness only, never timing evidence."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import tracemalloc

import measure


def legacy_once(binary, size, cpu):
    with tempfile.TemporaryFile() as output:
        child = subprocess.Popen(["taskset", "-c", str(cpu), str(binary), str(size)],
                                 cwd=measure.ROOT, env=measure.clean_env(), stdout=output)
        _, status, usage = os.wait4(child.pid, 0)
        child.returncode = os.waitstatus_to_exitcode(status)
        assert child.returncode == 0
        return usage.ru_maxrss


def worker(args):
    # Keep the parent's pages resident throughout both measurement paths.
    memory = bytearray(args.parent_mib * 1024 * 1024)
    for offset in range(0, len(memory), 4096):
        memory[offset] = 1
    cpu = min(os.sched_getaffinity(0))
    rows = []
    for size in (1, 64):
        expected = f"{size} {size * 1024 * 1024 // os.sysconf('SC_PAGESIZE')}\n"
        rows.append({"child_mib": size,
                     "legacy_outer_wait4_rss_kib": legacy_once(args.binary, size, cpu),
                     "corrected": [measure.run_rss_once([str(args.binary), str(size)],
                                    str(measure.ROOT), measure.clean_env(), [cpu], expected, 10)
                                   for _ in range(3)]})
    assert len(memory) == args.parent_mib * 1024 * 1024
    print(json.dumps({"parent_mib": args.parent_mib, "rows": rows}))


def qualify(args):
    if args.output.exists():
        raise ValueError("refusing to overwrite qualification evidence")
    observations = []
    for parent in (0, 256):
        command = [sys.executable, "-B", __file__, "worker", "--binary", str(args.binary),
                   "--parent-mib", str(parent)]
        result = subprocess.run(command, check=True, capture_output=True, text=True)
        observations.append(json.loads(result.stdout))
    for observation in observations:
        for row in observation["rows"]:
            for sample in row["corrected"]:
                assert "wall_ns" not in sample
                value = sample["maxrss_kib"]
                assert 0 <= value < 16 * 1024 if row["child_mib"] == 1 else 48 * 1024 <= value <= 80 * 1024
    for small_parent, large_parent in zip(observations[0]["rows"], observations[1]["rows"]):
        samples = [row["maxrss_kib"] for row in small_parent["corrected"] + large_parent["corrected"]]
        assert max(samples) - min(samples) < 8 * 1024
    tracemalloc.start()
    compiler_sha = measure.digest(args.compiler)
    _, hash_peak = tracemalloc.get_traced_memory()
    tracemalloc.stop()
    assert hash_peak < 3 * 1024 * 1024
    cpu = min(os.sched_getaffinity(0))
    runtime = measure.run_once([str(args.binary), "1"], str(measure.ROOT), measure.clean_env(),
                               [cpu], f"1 {1024 * 1024 // os.sysconf('SC_PAGESIZE')}\n", 10)
    assert "maxrss_kib" not in runtime and runtime["wall_ns"] > 0
    try:
        measure.run_rss_once([str(args.binary), "1"], str(measure.ROOT), measure.clean_env(), [cpu], "wrong\n", 10)
    except RuntimeError:
        mismatch_rejected = True
    else:
        raise AssertionError("incorrect checksum accepted")
    report = {"scope": __doc__, "status": "pass", "observations": observations,
              "compiler_sha256": compiler_sha, "stream_hash_python_peak_bytes": hash_peak,
              "runtime_rss_absent": True, "wrong_output_rejected": mismatch_rejected,
              "binary": str(args.binary), "binary_sha256": measure.digest(args.binary),
              "gnu_time_sha256": measure.digest("/usr/bin/time"),
              "source_sha256": measure.digest(Path(__file__).with_name("samples") / "rss_child.c"),
              "harness_sha256": measure.digest(Path(measure.__file__)),
              "legacy_contamination_reproduced": observations[1]["rows"][0]["legacy_outer_wait4_rss_kib"] > 200 * 1024}
    measure.save(args.output, report)
    print(json.dumps(report, indent=2))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    w = sub.add_parser("worker")
    w.add_argument("--binary", type=lambda p: Path(p).resolve(), required=True)
    w.add_argument("--parent-mib", type=int, required=True)
    w.set_defaults(handler=worker)
    q = sub.add_parser("qualify")
    q.add_argument("--binary", type=lambda p: Path(p).resolve(), required=True)
    q.add_argument("--compiler", type=Path, required=True)
    q.add_argument("--output", type=Path, required=True)
    q.set_defaults(handler=qualify)
    args = parser.parse_args()
    args.handler(args)


if __name__ == "__main__":
    main()
