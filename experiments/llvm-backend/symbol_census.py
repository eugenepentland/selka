#!/usr/bin/env python3
"""Census every `$symbol` the emitted QBE IL references, for an LLVM backend.

    symbol_census.py --out symbols.json MANIFEST.json [MANIFEST.json ...]

A frontend manifest (`mylang emit-project-qbe`) holds one QBE unit per emitted
function: `functions[i].il`.  Every unit defines exactly one function, so any
`$symbol` a unit *calls* but no unit *defines* is external and must be declared
by whatever emits the final object.

The census reports, per symbol:

  kind        "function"  -- defined by one of the units (closure-internal)
              "data"      -- defined by a `data $name = ...` line in a unit
              "external"  -- neither of the above: the C runtime or generated
                             metadata must provide it
  call_shapes one entry per distinct call site shape, e.g.
              {"result": "l", "args": ["l", "l", "l"]}

and, for external symbols, the reference sites (`call`, `extern`, `operand`).
"""
import argparse
import collections
import json
import re
import sys

# `function l $name(l %a, :tX %b) {`  /  `export function $name() {`
HEADER = re.compile(r"^(?:export\s+)?function\s+(?:([lwsbd])\s+)?\$?([\w.$]+)\s*\((.*?)\)\s*\{")
DATA = re.compile(r"^(?:export\s+)?data\s+\$?([\w.$]+)\s*=")
EXTERN = re.compile(r"\bextern\s+\$([\w.$]+)")
# `%t =l call $name(args)` or `%t =w call $name(args)` or `call $name(args)`
CALL = re.compile(r"^(?:%[\w.$]+\s*=\s*([lwsbd])\s+)?call\s+\$?([\w.$]+)\s*\((.*)\)\s*$")
SYMBOL = re.compile(r"\$([\w.$]+)")
# `%t =l op args` / `op args`, used only to name the opcode operating on a
# symbol operand.
OPERAND = re.compile(r"^(?:%[\w.$]+\s*=\s*[lwsbd]\s+)?([a-z][\w.]*)\s+(.*)$")


def split_args(text):
    """Split a QBE call argument list on commas at parenthesis depth zero."""
    text = text.strip()
    if not text:
        return []
    args, depth, current = [], 0, []
    for char in text:
        if char in "([{":
            depth += 1
        elif char in ")]}":
            depth -= 1
        if char == "," and depth == 0:
            args.append("".join(current).strip())
            current = []
        else:
            current.append(char)
    args.append("".join(current).strip())
    return [a for a in args if a]


def arg_type(arg):
    """The QBE type letter of one call argument, or `?` for an aggregate."""
    head = arg.split(None, 1)[0] if arg.split() else arg
    if head in ("l", "w", "s", "b", "d"):
        return head
    if head.startswith(":"):
        return head  # aggregate passed by value (a named type)
    return head


def census(manifests):
    """Fold every manifest into one symbol -> record map."""
    records = {}

    def record(name):
        return records.setdefault(name, {
            "kind": None, "defined_in": [], "seen_in": [],
            "call_shapes": [], "reference_sites": collections.Counter(),
            "operand_contexts": collections.Counter(),
        })

    # Pass 1: what every unit defines.
    units = []
    for path in manifests:
        with open(path) as handle:
            manifest = json.load(handle)
        for function in manifest["functions"]:
            units.append((path, function["name"], function["symbol"], function["il"]))
    defined_functions, defined_data = set(), set()
    for _, _, symbol, il in units:
        defined_functions.add(symbol)
        for line in il.split("\n"):
            stripped = line.strip()
            match = HEADER.match(stripped)
            if match:
                defined_functions.add(match.group(2))
                continue
            match = DATA.match(stripped)
            if match:
                defined_data.add(match.group(1))
    # A `data` line may name a symbol also declared `extern` elsewhere; the
    # definition wins.
    for symbol in defined_functions | defined_data:
        entry = record(symbol)
        entry["kind"] = "function" if symbol in defined_functions else "data"

    # Pass 2: every reference.
    for path, name, symbol, il in units:
        for line in il.split("\n"):
            stripped = line.strip()
            if not stripped or stripped.startswith("#"):
                continue
            if HEADER.match(stripped) or DATA.match(stripped):
                continue
            match = CALL.match(stripped)
            if match:
                target = match.group(2)
                entry = record(target)
                entry["reference_sites"]["call"] += 1
                shape = {
                    "result": match.group(1) or "void",
                    "args": [arg_type(a) for a in split_args(match.group(3))],
                    "args_raw": split_args(match.group(3)),
                    "unit": symbol,
                }
                if shape not in entry["call_shapes"]:
                    entry["call_shapes"].append(shape)
                # A call's argument list may itself name data symbols; only the
                # arguments are operands, never the callee.
                for token in SYMBOL.findall(match.group(3)):
                    record(token)["reference_sites"]["operand"] += 1
                continue
            # `extern $x` is a symbolic-operand modifier (`storel extern $x, %p`),
            # not a statement of its own, so look for it anywhere on the line.
            for token in EXTERN.findall(stripped):
                record(token)["reference_sites"]["extern"] += 1
            for token in SYMBOL.findall(stripped):
                if token == symbol:
                    continue
                entry = record(token)
                entry["reference_sites"]["operand"] += 1
                found = OPERAND.match(stripped)
                if found:
                    entry["operand_contexts"][found.group(1)] += 1
                if f"{path}:{name}" not in entry["seen_in"]:
                    entry["seen_in"].append(f"{path}:{name}")

    # Classify.
    for name, entry in records.items():
        if entry["kind"] is None:
            entry["kind"] = "external"
        entry["reference_sites"] = dict(entry["reference_sites"])
        entry["operand_contexts"] = dict(entry["operand_contexts"])
    return records


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("manifests", nargs="+")
    parser.add_argument("--out", required=True)
    options = parser.parse_args()
    records = census(options.manifests)
    by_kind = collections.Counter(entry["kind"] for entry in records.values())
    report = {
        "manifests": options.manifests,
        "counts": dict(by_kind),
        "symbols": {name: records[name] for name in sorted(records)},
    }
    with open(options.out, "w") as handle:
        json.dump(report, handle, indent=1, sort_keys=False)
    print(f"{len(records)} symbols: " + ", ".join(f"{k}={v}" for k, v in sorted(by_kind.items())))
    external = sorted(n for n, e in records.items() if e["kind"] == "external")
    print(f"external ({len(external)}):")
    for name in external:
        sites = ",".join(sorted(records[name]["reference_sites"]))
        shapes = {json.dumps(s["args"], separators=(",", "")) for s in records[name]["call_shapes"]}
        print(f"  {name:60s} {sites:20s} args={sorted(shapes)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
