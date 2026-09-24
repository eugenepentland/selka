#!/usr/bin/env python3
"""Check the Zig translator's units against the retired Python adapter, byte for byte.

usage: equivalence.py RUNTIME_DIR DUMP_DIR...

Each DUMP_DIR is what a `--release` build wrote under `MYLANG_LLVM_DUMP`: for
every translated unit `SYMBOL.ssa` (the IL), `SYMBOL.ll` (the Zig translator's
IR) and `SYMBOL.sigs.json` (the closure signatures its text names). The adapter
is run on the same IL with the same signatures, the same target policy (read
from the IR's own `target-cpu`/`target-features` attributes) and the runtime
registry of RUNTIME_DIR (the build's materialized runtime tree), and its IR must
equal the Zig translator's. Run it under several `PYTHONHASHSEED` values: the
adapter iterates some sets whose order that seed decides.

Prints one line per directory and a total; exits 1 on any difference.
"""
import json
import os
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "llvm-backend"))
sys.dont_write_bytecode = True


def policy(ir):
    cpu = re.search(r'"target-cpu"="([^"]*)"', ir)
    features = re.search(r'"target-features"="([^"]*)"', ir)
    return (cpu.group(1) if cpu else ""), (features.group(1) if features else "")


def main():
    os.environ["MYLANG_QBE_LLVM_RUNTIME_SOURCES"] = sys.argv[1]
    import qbe_llvm  # noqa: E402 - reads the runtime directory on first use
    total = same = 0
    failed_directories = 0
    for directory in sys.argv[2:]:
        units = sorted(Path(directory).glob("*.ssa"))
        differ = []
        for ssa in units:
            stem = ssa.with_suffix("")
            zig_ir = stem.with_suffix(".ll").read_text()
            table = {name: (tuple(entry["parameters"]), entry["result"])
                     for name, entry in json.loads(Path(f"{stem}.sigs.json").read_text()).items()}
            cpu, features = policy(zig_ir)
            os.environ["MYLANG_QBE_LLVM_TARGET_CPU"] = cpu
            os.environ["MYLANG_QBE_LLVM_TARGET_FEATURES"] = features
            try:
                python_ir = qbe_llvm.translate_text(ssa.read_text(), ssa.name, table)
            except Exception as error:  # noqa: BLE001 - a refusal is a difference here
                python_ir = f"REFUSED: {error}"
            if python_ir == zig_ir:
                same += 1
            else:
                differ.append(ssa.stem)
        total += len(units)
        if differ:
            failed_directories += 1
        print(f"{directory}: {len(units)} units, {len(units) - len(differ)} identical" + (f", different: {differ[:3]}" if differ else ""))
    print(f"TOTAL units={total} identical={same} directories_with_differences={failed_directories} "
          f"PYTHONHASHSEED={os.environ.get('PYTHONHASHSEED', 'random')}")
    sys.exit(1 if same != total else 0)


if __name__ == "__main__":
    main()
