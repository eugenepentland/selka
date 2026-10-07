#!/usr/bin/env python3
"""Inspect real unit emission with an explicit LLVM/link placeholder, never native validation."""
import argparse
import fcntl
import hashlib
import importlib.util
import json
import os
import re
import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("synthetic", ROOT / "experiments/new-core-s4-20261006/gen_program.py")
synthetic = importlib.util.module_from_spec(spec)
spec.loader.exec_module(synthetic)
RECORDER = '''#!/usr/bin/env python3
"""Explicit placeholder for emission inspection; creates no executable code."""
import json
import os
from pathlib import Path
import sys
with Path(os.environ["S4_EMIT_COMMANDS"]).open("a") as log:
    log.write(json.dumps(sys.argv) + "\\n")
args = sys.argv[1:]
if "-o" not in args:
    raise SystemExit("emission recorder expected a -o path")
Path(args[args.index("-o") + 1]).write_bytes(b"S4 emission placeholder, not native code\\n")
'''


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def emit(args, recorder, source, destination, compiler, mode, label):
    destination.mkdir(parents=True, exist_ok=False)
    commands = destination / "placeholder-commands.jsonl"
    command = [str(compiler.resolve()), "build", str(source / "main.my"), "--zig", str(recorder),
               "--cache-dir", str(destination / "cache"), "-o", str(destination / "NOT-EXECUTABLE")]
    if mode == "release":
        command.append("--release")
    start = time.monotonic()
    result = subprocess.run(["taskset", "-c", "10", *command], capture_output=True, text=True,
                            env={**os.environ, "S4_EMIT_COMMANDS": str(commands)}, timeout=900)
    seconds = time.monotonic() - start
    (destination / "command.json").write_text(json.dumps({"command": command, "status": result.returncode,
         "stdout": result.stdout, "stderr": result.stderr, "seconds": seconds, "native_validation": False}, indent=2) + "\n")
    if result.returncode:
        raise ValueError(f"emission failed: {destination}/command.json")
    units = {}
    for path in sorted((destination / "cache").glob("program-*/*.ll")):
        text = path.read_text()
        units[path.name] = {"sha256": digest(path), "bytes": path.stat().st_size,
             "source_path": re.search(r'^source_filename = "([^"]*)"', text, re.MULTILINE)[1],
             "imports": re.findall(r'^define available_externally[^@\n]*@"([^"]*)"', text, re.MULTILINE)}
    if not units:
        raise ValueError("no LLVM unit texts were retained")
    return {"compiler": label, "mode": mode, "seconds": seconds, "units": units,
            "unit_count": len(units), "llvm_bytes": sum(unit["bytes"] for unit in units.values()),
            "import_count": sum(len(unit["imports"]) for unit in units.values())}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--new", type=Path, required=True)
    parser.add_argument("--before", type=Path)
    parser.add_argument("--sizes", nargs="+", type=int, default=(120, 1200, 4800))
    parser.add_argument("--ripple", action="store_true", help="also inspect 1200-module body/check/helper edits")
    parser.add_argument("--evidence", type=Path, required=True)
    args = parser.parse_args()
    area = args.evidence.resolve()
    area.relative_to(ROOT / "experiments")
    area.mkdir(parents=True, exist_ok=False)
    cache = ROOT / ".mylang-cache/s4-emission" / area.name
    cache.mkdir(parents=True, exist_ok=False)
    recorder = area / "EMISSION-ONLY-zig-recorder.py"
    recorder.write_text(RECORDER)
    recorder.chmod(0o755)
    compilers = {"new": args.new.resolve()}
    if args.before:
        compilers["before"] = args.before.resolve()
    report = {"complete": False, "native_validation": False,
              "source_commit": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
              "compilers": {label: {"path": str(path), "sha256": digest(path)} for label, path in compilers.items()},
              "sizes": {}, "ripple": []}
    try:
        with Path("/run/user/1000/mylang-slots/cpu10.lock").open("a") as slot:
            fcntl.flock(slot, fcntl.LOCK_EX)
            for size in args.sizes:
                source = cache / f"source-{size}"
                synthetic.generate(size, str(source), None)
                result = {}
                for mode in ("debug", "release"):
                    emissions = {label: emit(args, recorder, source, cache / f"{size}-{mode}-{label}", compiler, mode, label)
                                 for label, compiler in compilers.items()}
                    if "before" in emissions and emissions["new"]["units"] != emissions["before"]["units"]:
                        raise ValueError(f"cold synthetic emission changed after loop-only imports: {size}/{mode}")
                    result[mode] = emissions
                    print(size, mode, {label: (row["unit_count"], row["llvm_bytes"], row["import_count"])
                                      for label, row in emissions.items()}, flush=True)
                report["sizes"][str(size)] = result
            if args.ripple:
                size = 1200
                for mode in ("debug", "release"):
                    baseline = report["sizes"][str(size)][mode]["new"]["units"]
                    for kind, target, expected in (("edit", 650, {"p6.my"}), ("grow", 650, {"p6.my"}),
                                                   ("helper", 600, {"p5.my", "p6.my"} if mode == "release" else {"p6.my"})):
                        source = cache / f"source-{mode}-{kind}"
                        synthetic.generate(size, str(source), target if kind == "edit" else None,
                                           target if kind == "grow" else None, target if kind == "helper" else None)
                        changed = emit(args, recorder, source, cache / f"ripple-{mode}-{kind}", args.new, mode, "new")["units"]
                        if baseline.keys() != changed.keys():
                            raise ValueError(f"unit ownership changed: {mode}/{kind}")
                        paths = {row["source_path"] for name, row in changed.items() if row != baseline[name]}
                        report["ripple"].append({"mode": mode, "kind": kind, "changed_paths": sorted(paths), "expected": sorted(expected)})
                        if paths != expected:
                            raise ValueError(f"unexpected unit ripple: {mode}/{kind}/{paths}")
                        print(mode, kind, sorted(paths), flush=True)
        for label, compiler in compilers.items():
            if digest(compiler) != report["compilers"][label]["sha256"]:
                raise ValueError(f"compiler changed: {label}")
        report["complete"] = True
    finally:
        (area / "summary.json").write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    main()
