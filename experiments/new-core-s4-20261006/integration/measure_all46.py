#!/usr/bin/env python3
"""S4's 46-row registry, using S3's strict interleaved CPU-10 measurement.

The frozen runtime references remain read-only. S4 reference binaries are built
in this worktree. Every compiler invocation has its own retained command log.
Run through build-slot.sh build and the shared CPU-10 flock, as in S3.
"""
import importlib.util
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
HERE = ROOT / "experiments/new-core-s4-rows-20261006"
spec = importlib.util.spec_from_file_location(
    "s3_rows", ROOT / "experiments/new-core-s3-20261006/wave-c/s3-a/measure_all40.py")
rows = importlib.util.module_from_spec(spec)
spec.loader.exec_module(rows)
CASES = ("tree_build_walk", "record_pass", "grid_dp", "union_find", "float_format", "buffer_write")
for case in CASES:
    data = json.loads((HERE / case / "case.json").read_text())
    rows.UNITS[case] = ("s4", data["unit"], data["iterations"]["4096"], data["iterations"]["64"])
rows.DEFAULT_BIN = ROOT / ".mylang-cache/s4/all46"
original_build = rows.build
original_configurations = rows.configurations


def command_log(directory, command, extra_env=None):
    logs = directory / "build-logs"
    logs.mkdir(parents=True, exist_ok=True)
    index = 1
    while (logs / f"command-{index:04d}.log").exists():
        index += 1
    log = logs / f"command-{index:04d}.log"
    with log.open("x") as output:
        output.write("$ " + shlex.join(map(str, command)) + "\n")
        output.flush()
        result = subprocess.run(command, stdout=output, stderr=subprocess.STDOUT,
                                env={**os.environ, "PATH": os.environ["PATH"] + os.pathsep + str(Path.home() / ".cargo/bin"), **(extra_env or {})})
        output.write(f"\nexit={result.returncode}\n")
    if result.returncode:
        raise rows.InvalidMeasurement(f"reference build failed; retained {log}")


def build(args, selected):
    # Capture each inherited old/new compiler invocation separately too.
    original_run = subprocess.run

    def logged_run(command, **options):
        result = original_run(command, **options)
        if len(command) > 1 and command[1] == "build":
            directory = args.bin / "build-logs"
            directory.mkdir(parents=True, exist_ok=True)
            name = Path(command[command.index("-o") + 1]).name
            index = 1
            while (directory / f"{name}-{index:02d}.log").exists():
                index += 1
            (directory / f"{name}-{index:02d}.log").write_text(
                "$ " + shlex.join(map(str, command)) + "\n" + result.stdout + result.stderr + f"\nexit={result.returncode}\n")
        return result

    subprocess.run = logged_run
    try:
        original_build(args, [case for case in selected if case not in CASES])
    finally:
        subprocess.run = original_run
    for case in selected:
        if case not in CASES:
            continue
        source = HERE / case
        registered = ROOT / f"test/core/row_{case}.my"
        program = registered if registered.exists() else source / "row.my"
        for kind, compiler in (("old", args.mylang), ("new", args.core)):
            output = args.bin / f"row_{case}_{kind}"
            output.unlink(missing_ok=True)
            command = [str(compiler), "build", str(program), "-o", str(output), "--release",
                       "--cache-dir", str(args.bin / "cache" / kind), "--link", str(ROOT / "benchmarks/runtime/ports/native_clock.c")]
            if kind == "new":
                emitted = args.bin / "llvm" / f"row_{case}.ll"
                emitted.parent.mkdir(parents=True, exist_ok=True)
                emitted.unlink(missing_ok=True)
                command += ["--emit-llvm", str(emitted)]
            command_log(args.bin, command)
            if not output.is_file() or (kind == "new" and not emitted.is_file()):
                raise rows.InvalidMeasurement(f"row build did not produce its outputs: {case}/{kind}")
            print(f"build {case} {kind}: status=0", flush=True)
        command_log(args.bin, ["rustc", "-O", "--edition", "2021", str(source / "main.rs"), "-o", str(args.bin / f"{case}-rust")])
        command_log(args.bin, ["zig", "build-exe", str(source / "main.zig"), "-lc", "-O", "ReleaseSafe", f"-femit-bin={args.bin / (case + '-zig-safe')}", "--cache-dir", str(args.bin / "cache/zig")])
        command_log(args.bin, ["go", "build", "-o", str(args.bin / (case + "-go")), str(source / "main.go")],
                    {"GOMAXPROCS": "1", "GOTOOLCHAIN": "local", "GOFLAGS": "", "GOAMD64": "v1"})


def configurations(args, row):
    if row not in CASES:
        return original_configurations(args, row)
    result = {}
    for label, suffix in (("old core --release", "old"), ("new core release", "new")):
        binary = args.bin / f"row_{row}_{suffix}"
        if not binary.is_file():
            raise rows.InvalidMeasurement(f"missing binary: {binary}; run --build")
        result[label] = lambda size, iterations, binary=binary: [str(binary), str(size), str(iterations), str(rows.SEED)]
    for label, suffix in (("Rust", "rust"), ("Zig ReleaseSafe", "zig-safe"), ("Go", "go")):
        binary = args.bin / f"{row}-{suffix}"
        if not binary.is_file():
            raise rows.InvalidMeasurement(f"missing reference: {binary}; run --build")
        result[label] = lambda size, iterations, binary=binary: [str(binary), row, str(size), str(iterations), str(rows.SEED)]
    return result


rows.build = build
rows.configurations = configurations


def main():
    if "--smoke-test" in sys.argv:
        assert len(rows.UNITS) == 46
        assert all(rows.stem(case) == f"row_{case}" for case in CASES)
        assert all(rows.UNITS[case][2] > 0 and rows.UNITS[case][3] > 0 for case in CASES)
        assert rows.parse_stdout("17 103\n") == (17, 103)
        print("measure_all46: registry and strict output parser pass")
        return 0
    return rows.main()


if __name__ == "__main__":
    raise SystemExit(main())
