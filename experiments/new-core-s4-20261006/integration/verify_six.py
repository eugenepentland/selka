#!/usr/bin/env python3
"""Compare the registered S4 rows' five built arms to independent Python oracles."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import shlex
import subprocess

ROOT = Path(__file__).resolve().parents[3]
CASES = ("tree_build_walk", "record_pass", "grid_dp", "union_find", "float_format", "buffer_write")
PROBES = ((2, 1, 1), (3, 42, 7), (17, 999983, 31), (64, 3, 7), (4096, 2, 7),
          (64, 300, 7), (4100, 30, 999983))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bin", type=Path, required=True)
    parser.add_argument("--evidence", type=Path, required=True)
    args = parser.parse_args()
    area = args.evidence.resolve()
    if area.exists() or not area.is_relative_to(ROOT / "experiments"):
        parser.error("use a fresh evidence directory under experiments")
    area.mkdir(parents=True)
    records = []
    summary = {"qualified": False, "comparisons": records, "error": None}
    try:
        for case in CASES:
            oracle_path = ROOT / "experiments/new-core-s4-rows-20261006" / case / "oracle.py"
            spec = importlib.util.spec_from_file_location("oracle_" + case, oracle_path)
            oracle = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(oracle)
            for size, iterations, seed in PROBES:
                expected = oracle.checksum(size, iterations, seed)
                for arm in ("old", "new", "rust", "zig-safe", "go"):
                    filename = f"row_{case}_{arm}" if arm in ("old", "new") else f"{case}-{arm}"
                    binary = (args.bin / filename).resolve()
                    argv = [str(binary)] + ([] if arm in ("old", "new") else [case])
                    argv += list(map(str, (size, iterations, seed)))
                    result = subprocess.run(argv, text=True, capture_output=True, timeout=120)
                    index = len(records) + 1
                    log = area / f"command-{index:04d}.log"
                    log.write_text("$ " + shlex.join(argv) + "\nstdout=" + repr(result.stdout) +
                                   "\nstderr=" + repr(result.stderr) + f"\nexit={result.returncode}\n")
                    fields = result.stdout.split()
                    valid = (result.returncode == 0 and result.stdout.count("\n") == 1 and
                             len(fields) == 2 and all(x.isdecimal() for x in fields) and
                             int(fields[0]) == expected and int(fields[1]) > 0)
                    records.append({"case": case, "arm": arm, "size": size, "iterations": iterations,
                                    "seed": seed, "expected": expected, "status": result.returncode,
                                    "binary_sha256": hashlib.sha256(binary.read_bytes()).hexdigest(),
                                    "oracle_sha256": hashlib.sha256(oracle_path.read_bytes()).hexdigest(),
                                    "log": log.name, "qualified": valid})
                    if not valid:
                        raise RuntimeError(f"wrong answer or invalid execution; retained {log}")
            print(f"{case}: all five arms match the independent oracle at seven probes", flush=True)
        summary["qualified"] = True
    except Exception as error:
        summary["error"] = str(error)
        raise
    finally:
        (area / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
