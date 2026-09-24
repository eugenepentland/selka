#!/usr/bin/env python3
"""Record every translation the Python adapter's own unit tests perform.

usage: harvest_fixtures.py OUTDIR

Runs `experiments/llvm-backend/test_adapter.py` with `translate_text` wrapped, and
writes one case per call: `N.ssa` (the input IL), `N.ll` (the adapter's IR) or
`N.err` (the refusal), `N.sigs.json` (the closure signatures it was handed) and
`N.env.json` (the switches, target policy and runtime-source directory in force).
`equivalence.py`'s Zig side replays each case and must produce the same bytes, or
refuse the same inputs. The adapter is the oracle here; nothing in the toolchain
runs it.
"""
import json
import os
import sys
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
ADAPTER = HERE.parent / "llvm-backend"
sys.path.insert(0, str(ADAPTER))
sys.dont_write_bytecode = True

import qbe_llvm  # noqa: E402
import runtime_signatures  # noqa: E402
import test_adapter  # noqa: E402

SWITCHES = ("MYLANG_QBE_LLVM_ALIAS", "MYLANG_QBE_LLVM_ELEMENT_GEP", "MYLANG_QBE_LLVM_STICKY",
            "MYLANG_QBE_LLVM_TARGET_CPU", "MYLANG_QBE_LLVM_TARGET_FEATURES")


def main():
    out = Path(sys.argv[1])
    out.mkdir(parents=True, exist_ok=True)
    original = qbe_llvm.translate_text
    counter = [0]

    def recorder(text, unit_name, signatures=None):
        counter[0] += 1
        stem = out / f"{counter[0]:04d}"
        stem.with_suffix(".ssa").write_text(text)
        table = {name: {"parameters": list(entry[0]), "result": entry[1]} for name, entry in (signatures or {}).items()}
        stem.with_suffix(".sigs.json").write_text(json.dumps(table, indent=1, sort_keys=True))
        environment = {name: os.environ[name] for name in SWITCHES if name in os.environ}
        environment["runtime_sources"] = runtime_signatures._SRC
        stem.with_suffix(".env.json").write_text(json.dumps(environment, indent=1, sort_keys=True))
        try:
            ir = original(text, unit_name, signatures)
        except Exception as error:  # noqa: BLE001 - every refusal is a case
            stem.with_suffix(".err").write_text(f"{type(error).__name__}: {error}\n")
            raise
        stem.with_suffix(".ll").write_text(ir)
        return ir

    qbe_llvm.translate_text = recorder
    test_adapter.translate_text = recorder
    suite = unittest.defaultTestLoader.loadTestsFromModule(test_adapter)
    result = unittest.TextTestRunner(stream=sys.stderr, verbosity=0).run(suite)
    print(f"harvested {counter[0]} translations; unit tests ok={result.wasSuccessful()}")


if __name__ == "__main__":
    main()
