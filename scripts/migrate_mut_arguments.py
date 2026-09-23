#!/usr/bin/env python3
"""Add the `mut` call-argument markers the checker asks for, corpus-wide.

Item 1 makes a call show every position it writes: `f(mut x)` where the callee
declares `x: mut T`. The compiler knows the exact set, so migration is mechanical
and this script applies the edits the diagnostics themselves point at, using byte
spans and never a source regex:

* `E_MUTATION_MARKER` "write `(mut x, ...)`"    -> insert `mut ` at the argument
* `E_MUTATION_MARKER` "remove `mut`: `(x)`"     -> delete the marker's `mut `
* `E_MUTATION_MARKER` "declared `mut` but never written" -> delete that `mut`

Every pass re-runs the checker before computing the next edit, so a change can
never invalidate an offset a later edit depends on.

Usage, from the repository root, with an installed compiler that implements item 1
(`zig build`):

    python3 scripts/migrate_mut_arguments.py --check tests/lang src/stdlib
    python3 scripts/migrate_mut_arguments.py tests/lang src/stdlib src/schematic/guest docs

`--check` reports what would change and writes nothing. Documentation is included
by passing `docs` explicitly: fenced examples are executed by `mylang doctest`, so
migrate them and re-run it afterwards.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BINARY = ROOT / "zig-out/bin/mylang"
NEVER_WRITTEN = re.compile(r"`([A-Za-z_]\w*)` is declared `mut` but never written")
MARKER_CODE = "E_MUTATION_MARKER"


def diagnose(path: Path) -> list[dict]:
    """Every `diagnostic-v1` record the checker reports for one file."""
    result = subprocess.run(
        [str(BINARY), "check", str(path), "--diagnostics=json"],
        capture_output=True, text=True, cwd=ROOT,
    )
    records = []
    for line in result.stderr.splitlines():
        line = line.strip()
        if not line.startswith("{"):
            continue
        try:
            payload = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(payload.get("diagnostic"), dict):
            records.append(payload["diagnostic"])
    return records


def span(record: dict) -> tuple[int, int] | None:
    byte_range = (record.get("location") or {}).get("bytes") or {}
    start, end = byte_range.get("start"), byte_range.get("end")
    return None if start is None or end is None else (start, end)


def marker_span(text: str, start: int) -> tuple[int, int] | None:
    """The `mut ` immediately before `start`, with the whitespace it owned."""
    head = text.rfind("mut", max(0, start - 8), start)
    if head == -1 or text[head : head + 3] != "mut":
        return None
    begin = head
    while begin > 0 and text[begin - 1] in " \t":
        begin -= 1
    end = head + 3
    while end < len(text) and text[end] in " \t":
        end += 1
    return begin, end


def apply(text: str, edits: list[tuple[int, int, str]]) -> str:
    """Apply disjoint `(start, end, replacement)` edits, back to front."""
    for start, end, replacement in sorted(edits, key=lambda edit: -edit[0]):
        text = text[:start] + replacement + text[end:]
    return text


def pass_missing_markers(text: str, records: list[dict]) -> tuple[str, int]:
    edits = []
    for record in records:
        if record.get("code") != MARKER_CODE:
            continue
        message = record.get("message", "")
        if "write `(mut " not in message:
            continue
        found = span(record)
        if found is None:
            continue
        edits.append((found[0], found[0], "mut "))
    return apply(text, edits), len(edits)


def pass_unneeded_markers(text: str, records: list[dict]) -> tuple[str, int]:
    edits = []
    for record in records:
        if record.get("code") != MARKER_CODE:
            continue
        message = record.get("message", "")
        if "remove `mut`: `(" not in message:
            continue
        found = span(record)
        if found is None:
            continue
        marker = marker_span(text, found[0])
        if marker is None:
            continue
        edits.append((marker[0], marker[1], ""))
    return apply(text, edits), len(edits)


def pass_stale_parameters(text: str, records: list[dict]) -> tuple[str, int]:
    edits = []
    for record in records:
        if record.get("code") != MARKER_CODE:
            continue
        found = span(record)
        if found is None:
            continue
        marker = marker_span(text, found[0])
        if marker is None:
            continue
        if NEVER_WRITTEN.search(record.get("message", "")) is None:
            continue
        edits.append((marker[0], marker[1], ""))
    return apply(text, edits), len(edits)


def migrate(path: Path, check: bool) -> list[str]:
    original = text = path.read_text()
    notes: list[str] = []

    def diagnose_candidate(candidate: str) -> list[dict]:
        path.write_text(candidate)
        return diagnose(path)

    for _ in range(64):
        records = diagnose_candidate(text)
        text, marked = pass_missing_markers(text, records)
        if not marked:
            break
        notes.append(f"marked {marked} argument(s)")

    for _ in range(16):
        records = diagnose_candidate(text)
        text, dropped = pass_unneeded_markers(text, records)
        if not dropped:
            break
        notes.append(f"dropped {dropped} unneeded marker(s)")

    for _ in range(16):
        records = diagnose_candidate(text)
        text, stale = pass_stale_parameters(text, records)
        if not stale:
            break
        notes.append(f"removed {stale} stale `mut` parameter(s)")

    path.write_text(original if check else text)
    return notes if text != original else []


def unresolved(path: Path) -> list[str]:
    """Mutation-contract diagnostics that remain after migration."""
    return [
        f"{record.get('code')}: {record.get('message', '')}"
        for record in diagnose(path)
        if record.get("code") in {MARKER_CODE, "E_REMOVED_SPELLING"}
    ]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("roots", nargs="+", type=Path)
    parser.add_argument("--check", action="store_true", help="report without writing")
    arguments = parser.parse_args()
    changed = blocked = 0
    for root in arguments.roots:
        files = sorted(root.rglob("*.my")) if root.is_dir() else [root]
        for path in files:
            notes = migrate(path, arguments.check)
            if notes:
                changed += 1
                print(f"{path}: {'; '.join(notes)}")
            for message in unresolved(path)[:1]:
                blocked += 1
                print(f"{path}: STILL REJECTED: {message}")
    print(f"{changed} file(s) {'would change' if arguments.check else 'changed'}; {blocked} still rejected")
    return 0


if __name__ == "__main__":
    sys.exit(main())
