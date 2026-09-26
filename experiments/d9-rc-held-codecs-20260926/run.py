#!/usr/bin/env python3
"""Check real library codec ownership on both native backends."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
FIXTURE = Path(__file__).resolve().parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler", type=Path, required=True)
    parser.add_argument("--qbe", type=Path, required=True)
    parser.add_argument("--work", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    work = args.work.resolve()
    work.mkdir(parents=True, exist_ok=True)
    compiler = args.compiler.resolve()
    driver = work / "driver"
    subprocess.run(["cc", "-std=c11", "-Wall", "-Wextra", "-Werror", "-I", str(ROOT / "src"),
                    str(FIXTURE / "driver.c"), "-ldl", "-o", str(driver)], check=True)
    result = {"compiler_sha256": hashlib.sha256(compiler.read_bytes()).hexdigest(),
              "source_sha256": {name: hashlib.sha256((FIXTURE / name).read_bytes()).hexdigest()
                                for name in ("bridge.my", "library.my", "driver.c")}, "backends": {}}
    for backend in ("qbe", "llvm"):
        library = work / ("bridge-" + backend + ".so")
        command = [str(ROOT / "scripts/build-slot.sh"), "build", str(compiler), "build", str(FIXTURE / "library.my"),
                   "--library", "--rc-runtime=stats", "--backend", backend, "--mode", "ReleaseFast",
                   "--qbe=" + str(args.qbe.resolve()), "--cache-dir=" + str(work / ("cache-" + backend)), "-o", str(library)]
        subprocess.run(command, cwd=ROOT, check=True)
        run = subprocess.run([str(driver), str(library)], capture_output=True, text=True, check=True)
        counts = [json.loads(line.removeprefix("MYLANG_RC_COUNTS "))
                  for line in run.stderr.splitlines() if line.startswith("MYLANG_RC_COUNTS ")]
        assert len(counts) == 4, run.stderr
        for count in counts:
            assert not count["saturated"] and count["heap_allocate"] == count["retire"], count
            assert count["owner_acquire"] + count["heap_allocate"] == count["owner_release"], count
            assert count["hold_acquire"] == count["hold_release"], count
        result["backends"][backend] = {"command": command, "stdout": run.stdout, "counts": counts,
                                         "library_sha256": hashlib.sha256(library.read_bytes()).hexdigest()}
        print(backend + ": 5 held-view bridge scenarios passed with balanced cleanup", flush=True)
    assert result["backends"]["qbe"]["counts"] == result["backends"]["llvm"]["counts"]
    args.output.write_text(json.dumps(result, indent=2) + "\n")


if __name__ == "__main__":
    main()
