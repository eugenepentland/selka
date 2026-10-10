#!/usr/bin/env python3
"""Record GDB behavior of ordinary Debug, optimized Debug, and Release guests."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import subprocess


SOURCES = {
    "compute.my": """public func calculate(seed: int) -> int:
    mut first = seed + 7
    mut second = first * 3
    mut total = 0
    for i in range(seed):
        total += second + i
    return total
""",
    "main.my": """import compute

func main(args: str[], out: Stream) -> int:
    mut seed = len(args) + 3
    mut answer = compute.calculate(seed)
    out.print(answer)
    return 0
""",
    "tiny.my": """public func bump(value: int) -> int:
    return value + 7
""",
    "inline.my": """import tiny

func main(args: str[], out: Stream) -> int:
    mut seed = len(args)
    mut answer = tiny.bump(seed)
    out.print(answer)
    return 0
""",
}
MODES = {"debug": ["--unoptimized"], "optimized_debug": [], "release": ["--release"]}
SCENARIOS = {
    "function_step": ("main", ["break compute::calculate", "run a b", "bt", "info args",
                                "info locals", "print seed", "print first", "step", "bt", "continue"]),
    "function_next": ("main", ["break compute::calculate", "run a b", "next", "bt", "continue"]),
    "arithmetic_line": ("main", ["break compute.my:2", "run a b", "bt", "continue"]),
    "call_line": ("main", ["break main.my:5", "run a b", "bt", "info locals", "step", "bt", "continue"]),
    "inline_function": ("inline", ["break tiny::bump", "run a b", "bt", "continue"]),
}

# Run inside GDB's Python interpreter. Record failures as observations: missing
# variables and removed inline helpers are the behaviors this probe measures.
PROBE = r'''
import gdb
import json
import os

for command in ["set pagination off", "set confirm off", "set debuginfod enabled off",
                "set disable-randomization off", "set breakpoint pending off"]:
    gdb.execute(command)

def position():
    try:
        frame = gdb.selected_frame()
        sal = frame.find_sal()
        return {"function": frame.name(), "line": sal.line,
                "file": sal.symtab.filename if sal.symtab else None}
    except gdb.error:
        return None

def breakpoints():
    found = []
    for bp in gdb.breakpoints() or []:
        places = []
        for location in bp.locations:
            if location.address is None:
                continue
            sal = gdb.find_pc_line(location.address)
            places.append({"line": sal.line, "file": sal.symtab.filename if sal.symtab else None})
        found.append({"hits": bp.hit_count, "locations": places})
    return found

rows = []
for command in json.loads(os.environ["MYLANG_GDB_COMMANDS"]):
    try:
        output = gdb.execute(command, to_string=True)
        error = None
    except gdb.error as problem:
        output = ""
        error = str(problem)
    rows.append({"command": command, "output": output, "error": error,
                 "position": position(), "breakpoints": breakpoints()})
with open(os.environ["MYLANG_GDB_REPORT"], "w") as stream:
    json.dump(rows, stream, indent=2)
'''


def run(argv, **kwargs):
    result = subprocess.run(argv, capture_output=True, text=True, timeout=60, **kwargs)
    if result.returncode:
        raise RuntimeError(f"{argv}: {result.stdout}\n{result.stderr}")
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler", type=Path, required=True)
    parser.add_argument("--gdb", default="gdb")
    parser.add_argument("--gdb-data-directory", type=Path)
    parser.add_argument("--output", type=Path, required=True, help="new artifact directory")
    args = parser.parse_args()
    compiler = args.compiler.resolve(strict=True)
    root = args.output.resolve()
    root.mkdir(parents=True, exist_ok=False)
    source = root / "sources"
    source.mkdir()
    for name, content in SOURCES.items():
        (source / name).write_text(content)
    probe = root / "probe.py"
    probe.write_text(PROBE)
    debugger = [args.gdb]
    if args.gdb_data_directory:
        debugger.append("--data-directory=" + str(args.gdb_data_directory.resolve()))
    report = {"captured_utc": datetime.now(timezone.utc).isoformat(),
              "compiler_sha256": hashlib.sha256(compiler.read_bytes()).hexdigest(),
              "gdb": run([*debugger, "--version"]).stdout.splitlines()[0],
              "sources": SOURCES, "scenarios": {k: v[1] for k, v in SCENARIOS.items()},
              "modes": {}}
    for mode, flags in MODES.items():
        directory = root / mode
        directory.mkdir()
        data = {"flags": flags, "programs": {}, "sessions": {}}
        for entry, expected in [("main", "190\n"), ("inline", "9\n")]:
            binary = directory / entry
            llvm = directory / (entry + ".ll")
            run([str(compiler), "build", str(source / (entry + ".my")), "-o", str(binary),
                 "--emit-llvm", str(llvm), "--cache-dir", str(directory / "cache"), *flags])
            result = run([str(binary), "a", "b"])
            if result.stdout != expected or result.stderr:
                raise RuntimeError(f"{mode}/{entry}: guest output mismatch")
            ir = llvm.read_text()
            data["programs"][entry] = {
                "stdout": result.stdout, "binary_sha256": hashlib.sha256(binary.read_bytes()).hexdigest(),
                "local_variable_metadata": ir.count("!DILocalVariable("),
                "variable_location_intrinsics": ir.count("@llvm.dbg.value") + ir.count("@llvm.dbg.declare"),
            }
        for name, (entry, commands) in SCENARIOS.items():
            output = directory / (name + ".json")
            environment = dict(os.environ, MYLANG_GDB_COMMANDS=json.dumps(commands), MYLANG_GDB_REPORT=str(output))
            result = run([*debugger, "-nx", "-batch", "-x", str(probe), str(directory / entry)],
                         cwd=source, env=environment)
            data["sessions"][name] = {"observations": json.loads(output.read_text()),
                                       "stdout": result.stdout, "stderr": result.stderr}
        report["modes"][mode] = data
    (root / "results.json").write_text(json.dumps(report, indent=2) + "\n")
    print(root / "results.json")


if __name__ == "__main__":
    main()
