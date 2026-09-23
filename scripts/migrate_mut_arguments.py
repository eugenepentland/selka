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
never invalidate an offset a later edit depends on. Checking an entry reports the
diagnostics of every module it imports, each located in its own file, so each
diagnostic is applied to the file it names: one entry migrates its whole project.
Files without a `main` (library and test modules) cannot be checked on their own;
they are migrated through the entries that import them.

Usage, from the repository root, with an installed compiler that implements item 1
(`zig build`):

    python3 scripts/migrate_mut_arguments.py --check tests/lang src/stdlib
    python3 scripts/migrate_mut_arguments.py tests/lang src/stdlib src/schematic/guest docs
    python3 scripts/migrate_mut_arguments.py --binary /path/to/mylang ../app/main.my

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
    """Every `diagnostic-v1` record the checker reports for one entry, any file."""
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


def by_file(entry: Path, records: list[dict]) -> dict[Path, list[dict]]:
    """Records grouped by the file they are located in.

    A location path is relative to the entry's directory (the project root), so
    `check main.my` reports `driver.my:28` for an imported module's diagnostic.
    """
    grouped: dict[Path, list[dict]] = {}
    for record in records:
        located = (record.get("location") or {}).get("path")
        if not located:
            continue
        target = Path(located)
        if not target.is_absolute():
            target = entry.parent / target
        grouped.setdefault(target.resolve(), []).append(record)
    return grouped


def span(record: dict, text: str) -> tuple[int, int] | None:
    """The record's location as character offsets into `text`.

    Diagnostics carry UTF-8 byte offsets; a file with any non-ASCII character (a `§`
    in a comment) would otherwise receive every later edit at the wrong place.
    """
    byte_range = (record.get("location") or {}).get("bytes") or {}
    start, end = byte_range.get("start"), byte_range.get("end")
    if start is None or end is None:
        return None
    encoded = text.encode()
    return (len(encoded[:start].decode(errors="ignore")), len(encoded[:end].decode(errors="ignore")))


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
        # "`f` writes `x`; write `(a, mut x)`": the marked argument may be at any
        # position, so match the replacement form rather than its first argument.
        if "; write `(" not in message or "mut " not in message:
            continue
        found = span(record, text)
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
        found = span(record, text)
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
        found = span(record, text)
        if found is None:
            continue
        marker = marker_span(text, found[0])
        if marker is None:
            continue
        if NEVER_WRITTEN.search(record.get("message", "")) is None:
            continue
        edits.append((marker[0], marker[1], ""))
    return apply(text, edits), len(edits)


def migrate(entry: Path, check: bool) -> dict[Path, list[str]]:
    """Apply the three passes to every file the entry's check reports, to a fixed point."""
    originals: dict[Path, str] = {}
    notes: dict[Path, list[str]] = {}
    # A large function reports one marker per check, so a project can need hundreds
    # of rounds; every round must change something or the loop stops.
    passes = (
        ("marked {} argument(s)", pass_missing_markers, 2000),
        ("dropped {} unneeded marker(s)", pass_unneeded_markers, 2000),
        ("removed {} stale `mut` parameter(s)", pass_stale_parameters, 2000),
    )
    counts: dict[Path, dict[str, int]] = {}
    for label, apply_pass, limit in passes:
        for _ in range(limit):
            changed = 0
            for path, records in by_file(entry, diagnose(entry)).items():
                if not path.is_file():
                    continue
                text = path.read_text()
                originals.setdefault(path, text)
                updated, count = apply_pass(text, records)
                if count:
                    path.write_text(updated)
                    changed += count
                    per_file = counts.setdefault(path, {})
                    per_file[label] = per_file.get(label, 0) + count
            if not changed:
                break
    if check:
        for path, text in originals.items():
            path.write_text(text)
    for path, per_file in counts.items():
        notes[path] = [label.format(count) for label, count in per_file.items()]
    return notes


def unresolved(entry: Path) -> dict[Path, list[str]]:
    """Errors that remain after migration, by file: the markers this script could not
    place and anything it does not handle (an `E_MUTATION_OVERLAP` needs a hand edit).
    An entry without `main` reports only `E_MAIN`, which says nothing about markers."""
    remaining: dict[Path, list[str]] = {}
    for path, records in by_file(entry, diagnose(entry)).items():
        for record in records:
            if record.get("severity") == "error" and record.get("code") != "E_MAIN":
                remaining.setdefault(path, []).append(f"{record.get('code')}: {record.get('message', '')}")
    return remaining


def main() -> int:
    global BINARY
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("roots", nargs="+", type=Path)
    parser.add_argument("--check", action="store_true", help="report without writing")
    parser.add_argument("--binary", type=Path, default=BINARY, help="mylang executable to check with")
    arguments = parser.parse_args()
    BINARY = arguments.binary.resolve()
    changed: dict[Path, list[str]] = {}
    blocked: dict[Path, list[str]] = {}
    for root in arguments.roots:
        root = root.resolve()
        files = sorted(root.rglob("*.my")) if root.is_dir() else [root]
        for path in files:
            for touched, found in migrate(path, arguments.check).items():
                changed.setdefault(touched, []).extend(found)
            for stuck, messages in unresolved(path).items():
                blocked.setdefault(stuck, messages)
    for path, found in sorted(changed.items()):
        print(f"{path}: {'; '.join(found)}")
    for path, messages in sorted(blocked.items()):
        print(f"{path}: STILL REJECTED: {messages[0]}")
    print(f"{len(changed)} file(s) {'would change' if arguments.check else 'changed'}; {len(blocked)} still rejected")
    return 0


if __name__ == "__main__":
    sys.exit(main())
