#!/usr/bin/env python3
"""WAVE 4 migration: add `host: Host` as the first parameter of every
`extern def` / `host def` declaration in the repository.

Shared files (SPEC.md, docs/effects.md, docs/io.md) and historical audits are
left untouched; their proposed edits live in docs/audits/wave4-notes.md.
"""
from __future__ import annotations

import pathlib
import re
import sys

SKIP = {
    "SPEC.md",
    "docs/effects.md",
    "docs/io.md",
}
SKIP_PREFIX = ("docs/audits/",)

HEAD = re.compile(r"^(\s*\\\\?\s*(?:extern|host)\s+def\s+[A-Za-z_][A-Za-z0-9_]*\s*(?:\[[^\]]*\])?\s*\()")
ROOTS = ("src", "test", "tests", "examples", "docs", "experiments")


def rewrite(text: str) -> tuple[str, int]:
    changed = 0
    out = []
    for line in text.splitlines(keepends=True):
        m = HEAD.match(line)
        if not m:
            out.append(line)
            continue
        after = m.end()
        close = line.find(")", after)
        if close == -1:
            out.append(line)
            continue
        params = line[after:close]
        stripped = params.strip()
        if stripped.startswith("host: Host"):
            out.append(line)
            continue
        inserted = "host: Host" if stripped.startswith(")") or stripped == "" else "host: Host, "
        out.append(line[:after] + inserted + line[after:])
        changed += 1
    return "".join(out), changed


def main() -> int:
    root = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".")
    total = 0
    files = 0
    for base in ROOTS:
        directory = root / base
        if not directory.is_dir():
            continue
        for path in sorted(directory.rglob("*")):
            if not path.is_file():
                continue
            rel = str(path.relative_to(root))
            if rel in SKIP or rel.startswith(SKIP_PREFIX):
                continue
            if path.suffix not in {".zig", ".selka", ".md", ".c", ".txt"}:
                continue
            try:
                text = path.read_text()
            except UnicodeDecodeError:
                continue
            updated, count = rewrite(text)
            if count:
                path.write_text(updated)
                files += 1
                total += count
                print(f"{rel}: {count}")
    print(f"total {total} declaration(s) in {files} file(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
