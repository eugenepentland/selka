#!/usr/bin/env python3
"""One-off migration: bare `print(`/`eprint(` inside a `def main` body become
`out.print(`/`err.print(`, and main gains `out: Stream` / `err: Stream`.

The rewrite is intentionally conservative: only top-level `def main(...)` bodies
are touched, because a helper that prints needs a hand-added `Stream` parameter
and a call site that threads one -- which is exactly the visibility the
capability rule buys. Run it once over a corpus and review the diff:

    python3 scripts/migrate-print-to-stream.py examples experiments

It rewrites files in place and prints a per-file count of changed call sites.
`--check` reports what would change without writing.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

MAIN = re.compile(r"^def\s+main\s*\((.*?)\)\s*(->\s*[^:]+)?:")
PRINT_CALL = re.compile(r"(?<![\w.])print\s*\(")
EPRINT_CALL = re.compile(r"(?<![\w.])eprint\s*\(")


def body_bounds(lines: list[str], header: int) -> tuple[int, int]:
    """Return [start, end) line indices of the indented body after `header`."""
    indent = len(lines[header]) - len(lines[header].lstrip())
    end = header + 1
    while end < len(lines):
        stripped = lines[end].strip()
        if stripped and len(lines[end]) - len(lines[end].lstrip()) <= indent:
            break
        end += 1
    return header + 1, end


def add_parameters(signature: str, wanted: list[str]) -> str:
    """Insert `name: Stream` parameters that are not already declared."""
    existing = {part.split(":")[0].strip() for part in signature.split(",") if part.strip()}
    added = [f"{name}: Stream" for name in wanted if name not in existing]
    if not added:
        return signature
    if signature.strip():
        return signature.rstrip() + ", " + ", ".join(added)
    return ", ".join(added)


def migrate(path: Path, check: bool) -> int:
    original = path.read_text()
    lines = original.splitlines(keepends=True)
    changed = 0
    index = 0
    while index < len(lines):
        match = MAIN.match(lines[index])
        if not match:
            index += 1
            continue
        start, end = body_bounds(lines, index)
        body = "".join(lines[start:end])
        new_body = PRINT_CALL.sub("out.print(", body)
        new_body = EPRINT_CALL.sub("err.print(", new_body)
        used_out = "out.print(" in new_body
        used_err = "err.print(" in new_body
        new_signature = add_parameters(
            match.group(1), [n for n, used in (("out", used_out), ("err", used_err)) if used]
        )
        if new_signature != match.group(1):
            lines[index] = lines[index][: match.start(1)] + new_signature + lines[index][match.end(1) :]
            changed += 1
        if new_body != body:
            changed += 1
            lines[start:end] = new_body.splitlines(keepends=True)
            end = start + len(new_body.splitlines(keepends=True))
        index = end
    if changed and not check:
        path.write_text("".join(lines))
    return changed


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("roots", nargs="+", type=Path)
    parser.add_argument("--check", action="store_true", help="report without writing")
    options = parser.parse_args()
    total = 0
    for root in options.roots:
        targets = sorted(root.rglob("*.my")) if root.is_dir() else [root]
        for path in targets:
            changed = migrate(path, options.check)
            if changed:
                print(f"{path}: {changed} edit(s)", file=sys.stderr)
                total += changed
    print(f"{'would change' if options.check else 'changed'} {total} site(s)", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
