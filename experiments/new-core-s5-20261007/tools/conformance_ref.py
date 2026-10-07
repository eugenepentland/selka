#!/usr/bin/env python3
"""S5 conformance against the frozen old-core references (S5-D2).

S2's conformance_checked.py unchanged, except that the old core never runs:
`Tool.old` returns its frozen report from references/conformance-v1.json (each
test's name, status and trap code, which is all conformance.py compares).
`--references FILE` replaces `--mylang`; every other conformance.py option is the same.
"""
import argparse
import importlib.util
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[3]


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, ROOT / path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main():
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--references", type=Path, required=True)
    known, rest = parser.parse_known_args()
    files = json.loads(known.references.read_text())["files"]
    checked = load("conformance_checked", "experiments/new-core-s2-20261005/wave-b/integration/conformance_checked.py")
    sweep = load("conformance", "experiments/new-core-s1-20261005/conformance.py")
    original = sweep.parse
    sweep.parse = lambda done, what: checked.checked_report(original, done, what)

    def frozen(self, path):
        entry = files.get(sweep.short(path))
        if entry is None:
            return "old core (frozen): no reference for %s" % sweep.short(path)
        if "problem" in entry:
            return entry["problem"]
        return {"tests": [{"name": name, "status": status, "reason": trap} for name, status, trap in entry["tests"]]}

    sweep.Tool.old = frozen
    sys.argv = [sys.argv[0], *rest]
    return sweep.main()


if __name__ == "__main__":
    raise SystemExit(main())
