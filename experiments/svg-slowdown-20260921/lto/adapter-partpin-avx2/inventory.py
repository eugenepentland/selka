#!/usr/bin/env python3
"""Inventory the opcodes, types, signatures and symbols of emitted QBE units.

    inventory.py MANIFEST.json [MANIFEST.json ...] [--json OUT]

Reads the manifest the frontend emits for a whole program (`mylang
emit-project-qbe`) and reports every distinct QBE construct the closure uses.
The report is the supported-subset contract for the LLVM adapter: anything the
translator does not handle must appear here first.
"""
import argparse
import collections
import json
import re
import sys

# A QBE instruction line is either `%tmp =T op args` or `op args`.  The type
# letter after `=` is optional whitespace, which the emitter sometimes omits.
INSTRUCTION = re.compile(r"^(?:%[\w.$]+\s*=\s*([lwsbd]|:[\w.$]+)\s+)?([a-z][\w.]*)\s*(.*)$")
FUNCTION = re.compile(r"^(export\s+)?function\s+(?:([lwsbd])\s+)?\$?([\w.$]+)\s*\((.*?)\)", re.M)
DATA = re.compile(r"^(export\s+)?data\s+\$?([\w.$]+)\s*=", re.M)
TYPE = re.compile(r"^type\s+(:\S+)\s*=\s*(.*)$", re.M)
EXTERNAL = re.compile(r"extern\s+\$([\w.$]+)")


def units(manifest):
    """Every emitted unit: the manifest's functions plus its entry unit."""
    for function in manifest["functions"]:
        yield function["name"], function["il"]
    yield "entry", manifest.get("entry_il", "")


def signature_of(il):
    """The function header line of one unit, or None when absent."""
    for line in il.split("\n"):
        stripped = line.strip()
        if stripped.startswith("function ") or stripped.startswith("export function "):
            return stripped
    return None


def scan(il, opcodes, types, calls, signatures, data, externs, unsupported, labels):
    """Accumulate one unit's constructs into the caller's counters."""
    for line in il.split("\n"):
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        if stripped.startswith("type "):
            types[stripped.split("=")[0].strip()] += 1
            continue
        match = FUNCTION.match(stripped)
        if match:
            signatures[match.group(3)] += 1
            continue
        match = DATA.match(stripped)
        if match:
            data[match.group(2)] += 1
            continue
        if stripped.startswith("@"):
            # A block label, not an instruction.
            labels[stripped] += 1
            continue
        if stripped in ("}", "}"):
            continue
        match = INSTRUCTION.match(stripped)
        if not match:
            unsupported.append(stripped)
            continue
        opcode = match.group(2)
        opcodes[opcode] += 1
        if match.group(1):
            types["=" + match.group(1)] += 1
        if opcode == "call":
            target = re.match(r"\$?([\w.$]+)", match.group(3))
            if target:
                calls[target.group(1)] += 1
    for name in EXTERNAL.findall(il):
        externs[name] += 1


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("manifests", nargs="+")
    parser.add_argument("--json", dest="out")
    options = parser.parse_args()
    report = {"manifests": {}}
    for path in options.manifests:
        with open(path) as handle:
            manifest = json.load(handle)
        opcodes = collections.Counter()
        types = collections.Counter()
        calls = collections.Counter()
        signatures = collections.Counter()
        data = collections.Counter()
        externs = collections.Counter()
        unsupported = []
        labels = collections.Counter()
        unit_names = []
        for name, il in units(manifest):
            unit_names.append(name)
            scan(il, opcodes, types, calls, signatures, data, externs, unsupported,
                 labels)
        entry = {"units": len(unit_names), "opcodes": dict(opcodes.most_common()),
                 "assignment_types": dict(types.most_common()),
                 "call_targets": dict(calls.most_common()),
                 "signature_kinds": dict(signatures.most_common()),
                 "data": len(data), "externs": len(externs), "blocks": len(labels),
                 "extern_names": sorted(externs), "unparsed_lines": unsupported[:20]}
        report["manifests"][path] = entry
        print(f"== {path}: {len(unit_names)} units")
        print("opcodes:", ", ".join(f"{k}={v}" for k, v in opcodes.most_common()))
        print("assignment types:", ", ".join(f"{k}={v}" for k, v in types.most_common()))
        print("function signature kinds:", ", ".join(f"{k}={v}" for k, v in signatures.most_common()))
        print("data items:", len(data), "extern symbols:", len(externs))
        print("call targets:", len(calls))
        if unsupported:
            print("UNPARSED:", unsupported[:5])
    if options.out:
        with open(options.out, "w") as handle:
            json.dump(report, handle, indent=1)
    return 0


if __name__ == "__main__":
    sys.exit(main())
