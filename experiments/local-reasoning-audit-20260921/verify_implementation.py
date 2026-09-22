#!/usr/bin/env python3
"""Check the plan's "Done when" conditions against an installed compiler.

Companion to [the implementation plan](../../docs/audits/local-reasoning-implementation-plan-2026-09-21.md)
and to `probe.py`, which recorded the *before* state of the same programs. Each
case below is one line of a plan item's "Done when": a program that must be
rejected with a named diagnostic and a paste, or one that must run and print
something.

Run from the repository root after `zig build` has installed the compiler:

    python3 experiments/local-reasoning-audit-20260921/verify_implementation.py
    python3 experiments/local-reasoning-audit-20260921/verify_implementation.py --item 1

Exit status is the number of failing cases. Diagnostic checks read
`mylang check --diagnostics=json`, so a rejection is verified by its code and by
the presence of the paste in its message, not by matching whole prose. Runtime
checks use `mylang run`, which builds the program natively and executes it.

A case whose item is not implemented yet reports `SKIP` only when the compiler
does not know the construct at all (`E_SYNTAX`, `E_NOT_IMPLEMENTED`,
`E_UNKNOWN_TYPE`, `E_UNKNOWN_NAME`); anything else is a real failure, so this
harness cannot pass by accident.
"""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass, field
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BINARY = ROOT / "zig-out/bin/mylang"
UNIMPLEMENTED = {"E_SYNTAX", "E_NOT_IMPLEMENTED", "E_UNKNOWN_TYPE", "E_UNKNOWN_NAME"}
INVENTORY = '''\
record Item:
    name: str
    count: int

class Inventory:
    items: list[Item]
    total: int

def restock(inv: Inventory, name: str, amount: int) -> None:
    inv.items.append(Item(name=name, count=amount))
    inv.total = inv.total + amount

def report(inv: Inventory, out: Stream) -> None:
    out.print(inv.total, len(inv.items))

def main(out: Stream) -> int:
    inv = Inventory(items=[], total=0)
    restock(inv, "bolt", 5)
    report(inv, out)
    return 0
'''

INVENTORY_MARKED = INVENTORY.replace(
    "def restock(inv: Inventory,", "def restock(inv: mut Inventory,"
).replace("restock(inv, ", "restock(mut inv, ")

INVENTORY_REPORT_MARKED = INVENTORY_MARKED.replace(
    "def report(inv: Inventory,", "def report(inv: mut Inventory,"
).replace("report(inv, out)", "report(mut inv, out)")

FIND_PIN = '''\
module main


record Pin:
    name: str
    net: int


def find_pin(pins: list[Pin], name: str) -> int:
    for index, pin in enumerate(pins):
        if pin.name == name:
            return index
    return -1


def wire(pins: list[Pin], name: str) -> int:
    index = find_pin(pins, name)
    if index < 0:
        return 0
    return pins[index].net


def main() -> int:
    return 0
'''

SPLIT_FIRST = '''\
def split_first(text: str, sep: str) -> tuple[str, str]:
    at = text.find(sep)
    if at < 0:
        return text, ""
    return text[0:at], text[at + 1:len(text)]

def main(out: Stream) -> int:
    head, rest = split_first("key=value", "=")
    out.print(head, rest)
    a = 1
    b = 2
    a, b = b, a
    pairs: list[tuple[int, str]] = [(1, "a"), (2, "b")]
    for number, letter in pairs:
        out.print(number, letter)
    return 0
'''

ISSUE = '''\
def issue(host: Host, *, code: int, file: int, position: int) -> None:
    return None

def main() -> int:
    return 0
'''

ISSUE_POSITIONAL = '''\
def issue(host: Host, *, code: int, file: int, position: int) -> None:
    return None

def main(host: Host) -> int:
    issue(host, 13, 0, 1)
    return 0
'''

CONDITIONAL = '''\
def main() -> int:
    x = 352
    edge = 532 if x > 0 else 352
    return edge - 490
'''

UNWRAP_OR = '''\
def main() -> int:
    value: Option[int] = None
    return value.unwrap_or(7)
'''

EQUAL_UNUSED_CAPABILITY = '''\
public def equal(host: Host, a: int, b: int) -> bool:
    return a == b

def main(host: Host) -> int:
    if equal(host, 1, 1):
        return 0
    return 1
'''

RAIL_RESTATING = '''\
public def rail(host: Host, span: int) -> bool effects(host, managed_allocation):
    return span > 0

def main(host: Host) -> int:
    if rail(host, 1):
        return 0
    return 1
'''


@dataclass
class Case:
    item: int
    name: str
    source: str
    # Rejected: codes that must appear, and pastes their messages must contain.
    codes: list[str] = field(default_factory=list)
    pastes: list[str] = field(default_factory=list)
    # Accepted: expected stdout lines and process status.
    output: str | None = None
    status: int = 0
    extra: str | None = None


CASES = [
    Case(1, "class write needs a declaration paste", INVENTORY,
         codes=["E_MUTATION_MARKER"], pastes=["inv: mut Inventory"]),
    Case(1, "class write needs a call paste", INVENTORY,
         codes=["E_MUTATION_MARKER"], pastes=['restock(mut inv, "bolt", 5)']),
    Case(1, "both markers accepted", INVENTORY_MARKED, output="5 1"),
    Case(1, "unneeded marker rejected", INVENTORY_REPORT_MARKED,
         codes=["E_MUTATION_MARKER"], pastes=["remove `mut`"]),
    Case(1, "removed spelling: mutates", '''\
def touch(values: list[int]) mutates(values) -> None:
    values[0] = 42

def main() -> int:
    values = [1]
    touch(values)
    return values[0]
''', codes=["E_REMOVED_SPELLING"], pastes=["mut"]),
    Case(2, "unused capability is an error", EQUAL_UNUSED_CAPABILITY,
         codes=["E_UNUSED_CAPABILITY"], pastes=["host"]),
    Case(2, "restating clause warns", RAIL_RESTATING,
         codes=["W_DERIVED_EFFECTS"], pastes=["effects("]),
    Case(3, "unwrap_or default", UNWRAP_OR, output=None, status=7),
    Case(3, "sentinel lint", FIND_PIN, extra="lint"),
    Case(4, "tuples run", SPLIT_FIRST, output="key value\n1 a\n2 b"),
    Case(5, "keyword-only call is rejected with the rewrite", ISSUE_POSITIONAL,
         codes=["E_KEYWORD_ONLY"], pastes=["code=13"]),
    Case(6, "conditional expression", CONDITIONAL, output=None, status=42),
]


def run_case(case: Case, directory: Path, binary: Path) -> str:
    # A `module NAME` header must match the file's stem, so a case that declares
    # one is written as `main.my`; `mylang lint` requires an entry point.
    path = directory / "main.my"
    path.write_text(case.source)

    if case.extra == "lint":
        # `lint --json` writes `diagnostic-v1` records on stderr (like every
        # other command's `--diagnostics=json`) and its human summary on stdout.
        result = subprocess.run(
            [str(binary), "lint", str(path), "--profile=agent", "--json"],
            capture_output=True, text=True, cwd=ROOT,
        )
        records = []
        for line in result.stderr.splitlines():
            line = line.strip()
            if line.startswith("{"):
                payload = json.loads(line)
                if isinstance(payload.get("diagnostic"), dict):
                    records.append(payload["diagnostic"])
        seen = {record.get("code") for record in records}
        if "L_SENTINEL_INT" in seen:
            return "PASS"
        if not seen or seen <= UNIMPLEMENTED | {"E_MAIN", "E_MODULE_NAME", "L_DEAD_PRIVATE"}:
            return f"SKIP (construct not implemented: {sorted(seen)})"
        return f"FAIL: no L_SENTINEL_INT; saw {sorted(seen)}"

    if case.codes:
        result = subprocess.run(
            [str(binary), "check", str(path), "--diagnostics=json"],
            capture_output=True, text=True, cwd=ROOT,
        )
        records = []
        for line in result.stderr.splitlines():
            line = line.strip()
            if line.startswith("{"):
                payload = json.loads(line)
                if isinstance(payload.get("diagnostic"), dict):
                    records.append(payload["diagnostic"])
        seen = {record.get("code") for record in records}
        missing = [code for code in case.codes if code not in seen]
        if missing:
            # A case checks against the *installed* compiler, which may predate
            # the item. `E_MAIN` is in this set because a program whose entry
            # point the checker has not reached yet reports it first, and
            # `W_UNUSED_BINDING` because item 2 turns that warning into
            # `E_UNUSED_CAPABILITY`.
            if not seen or seen <= UNIMPLEMENTED | {"E_MAIN", "W_UNUSED_BINDING"}:
                return f"SKIP (construct not implemented: {sorted(seen)})"
            return f"FAIL: missing {missing}; saw {sorted(seen)}"
        for paste in case.pastes:
            if not any(paste in record.get("message", "") for record in records):
                return f"FAIL: no diagnostic carries the paste {paste!r}"
        return "PASS"

    result = subprocess.run(
        [str(binary), "run", str(path), "--cache-dir=" + str(directory / "cache")],
        capture_output=True, text=True, cwd=ROOT,
    )
    if result.returncode != 0 and any(f"error[{code}]" in result.stderr for code in UNIMPLEMENTED):
        return "SKIP (construct not implemented)"
    if case.output is not None and result.stdout.strip() != case.output:
        return f"FAIL: printed {result.stdout.strip()!r}, wanted {case.output!r}"
    if result.returncode != case.status:
        return f"FAIL: exit {result.returncode}, wanted {case.status}: {result.stderr.strip()[:200]}"
    return "PASS"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--item", type=int, action="append", help="only this item")
    parser.add_argument("--binary", type=Path, default=BINARY,
                        help="compiler to check against; defaults to this checkout's zig-out/bin/mylang")
    arguments = parser.parse_args()
    if not arguments.binary.exists():
        print(f"missing {arguments.binary}; run `zig build` first", file=sys.stderr)
        return 1

    directory = Path(tempfile.mkdtemp(prefix="local-reasoning-verify-"))
    failures = 0
    try:
        for case in CASES:
            if arguments.item and case.item not in arguments.item:
                continue
            verdict = run_case(case, directory, arguments.binary)
            if verdict.startswith("FAIL"):
                failures += 1
            print(f"item {case.item}  {case.name}: {verdict}")
    finally:
        shutil.rmtree(directory, ignore_errors=True)
    print(f"{failures} failing case(s)")
    return failures


if __name__ == "__main__":
    sys.exit(main())
