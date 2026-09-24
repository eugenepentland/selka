#!/usr/bin/env python3
"""Pack the retired Python adapter's translations into the Zig translator's golden corpus.

usage: pack_fixtures.py HARVEST_DIR OUT.json [DUMP_DIR SYMBOL ...]

HARVEST_DIR is what `harvest_fixtures.py` wrote (the adapter's own unit tests);
each DUMP_DIR SYMBOL pair adds one unit a real `--release` build dumped
(`MYLANG_QBE_LLVM_DUMP`), with the closure signatures its text names computed
from every unit of that dump. Every case carries the IL, the signatures, the
switches and target policy it was translated under, and the adapter's IR (or
null when the adapter refused it). `src/qbe_build_llvm_test.zig` replays them.
The expected IR is re-derived here with the runtime registry read from
RUNTIME_DIR (default: the repository's `src`), so the Zig side, which reads
the bundled runtime tree, sees the same helper declarations.
"""
import json
import os
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "llvm-backend"))
sys.dont_write_bytecode = True

SWITCHES = ("MYLANG_QBE_LLVM_ALIAS", "MYLANG_QBE_LLVM_ELEMENT_GEP", "MYLANG_QBE_LLVM_STICKY")


def translate(qbe_llvm, case):
    """The adapter's IR for one case under its own switches, or None when it refuses."""
    saved = {name: os.environ.get(name) for name in SWITCHES + ("MYLANG_QBE_LLVM_TARGET_CPU", "MYLANG_QBE_LLVM_TARGET_FEATURES")}
    try:
        for name in SWITCHES:
            os.environ.pop(name, None)
        os.environ.update(case["switches"])
        os.environ["MYLANG_QBE_LLVM_TARGET_CPU"] = case["target_cpu"]
        os.environ["MYLANG_QBE_LLVM_TARGET_FEATURES"] = case["target_features"]
        table = {name: (tuple(entry["parameters"]), entry["result"]) for name, entry in case["signatures"].items()}
        return qbe_llvm.translate_text(case["ssa"], case["name"], table)
    except Exception:  # noqa: BLE001 - any refusal (both modules define ParseError) is a refused case
        return None
    finally:
        for name, value in saved.items():
            if value is None:
                os.environ.pop(name, None)
            else:
                os.environ[name] = value


def harvested(directory):
    for ssa in sorted(Path(directory).glob("*.ssa")):
        stem = ssa.with_suffix("")
        environment = json.loads(stem.with_suffix(".env.json").read_text())
        yield {
            "name": f"adapter-test-{ssa.stem}",
            "ssa": ssa.read_text(),
            "signatures": json.loads(stem.with_suffix(".sigs.json").read_text()),
            "switches": {name: environment[name] for name in SWITCHES if name in environment},
            "target_cpu": environment.get("MYLANG_QBE_LLVM_TARGET_CPU", ""),
            "target_features": environment.get("MYLANG_QBE_LLVM_TARGET_FEATURES", ""),
        }


def dumped(qbe_llvm, directory, symbol):
    root = Path(directory)
    table = {}
    for ssa in root.glob("*.ssa"):
        unit = qbe_llvm.parse_unit(ssa.read_text(), ssa.name)
        table[unit.function.name] = {"parameters": [letter for letter, _ in unit.function.parameters], "result": unit.function.result}
    text = (root / f"{symbol}.ssa").read_text()
    named = set(re.findall(r"\$+([\w.$]+)", text))
    ir = (root / f"{symbol}.ll").read_text()
    cpu = re.search(r'"target-cpu"="([^"]*)"', ir)
    features = re.search(r'"target-features"="([^"]*)"', ir)
    return {
        "name": f"{root.parent.name}-{root.name}-{symbol[:14]}",
        "ssa": text,
        "signatures": {name: table[name] for name in sorted(named) if name in table},
        "switches": {},
        "target_cpu": cpu.group(1) if cpu else "",
        "target_features": features.group(1) if features else "",
    }


def main():
    runtime = os.environ.get("RUNTIME_DIR", str(HERE.parent.parent / "src"))
    os.environ["MYLANG_QBE_LLVM_RUNTIME_SOURCES"] = runtime
    import qbe_llvm  # noqa: E402 - reads the runtime directory at first use
    cases = list(harvested(sys.argv[1]))
    extra = sys.argv[3:]
    for directory, symbol in zip(extra[::2], extra[1::2]):
        cases.append(dumped(qbe_llvm, directory, symbol))
    for case in cases:
        case["expected"] = translate(qbe_llvm, case)
    Path(sys.argv[2]).write_text(json.dumps(cases, indent=1, sort_keys=True) + "\n")
    refused = sum(1 for case in cases if case["expected"] is None)
    print(f"packed {len(cases)} cases ({refused} refused) with the runtime registry of {runtime}")


if __name__ == "__main__":
    main()
