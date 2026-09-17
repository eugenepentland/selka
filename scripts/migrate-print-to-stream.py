#!/usr/bin/env python3
"""Migrate bare `print(`/`eprint(` calls to the `Stream` capability spelling.

A top-level `def f(...)` body that calls `print(` becomes `out.print(` and one
that calls `eprint(` becomes `err.print(`; the function gains an
`out: Stream`/`err: Stream` parameter, and every call site inside the same
source forwards the caller's stream. A source that prints only from `def main`
needs nothing further, because `main` already receives the streams from the
entry point. A helper needs its own parameter and a threaded call site -- which
is exactly the visibility the capability rule buys.

Three input shapes are understood:

  * a `.my` file: the whole file is guest source;
  * a `.md` file: every fenced ```mylang / ```my block is rewritten in place
    (prose, other fences and the fence markers are untouched);
  * a `.zig` file: every multiline string literal that contains a top-level
    `def ` is rewritten; Zig's own code is never touched.

Run it once over a corpus and review the diff:

    python3 scripts/migrate-print-to-stream.py examples docs src/*.zig

It rewrites files in place and prints a per-file count of changed sites.
`--check` reports what would change without writing.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

FUNCTION = re.compile(r"^def\s+([A-Za-z_]\w*)\s*\(")
MULTILINE = re.compile(r"^(\s*)\\\\(.*)$")
FENCE = re.compile(r"^\s*```(mylang|my)\s*$")
FENCE_END = re.compile(r"^\s*```\s*$")
PRINT = re.compile(r"(?<![\w.])print\s*\(")
EPRINT = re.compile(r"(?<![\w.])eprint\s*\(")
LAMBDA_PRINT = re.compile(r"lambda[^\n]*print\s*\(")


def function_header(line: str) -> tuple[str, int, int] | None:
    """Parse `def name(params) ...:` with nested callback parentheses.

    Returns `(name, params_start, params_end)`, where the ranges are indices into
    `line` for the parameter text between the balanced parentheses, or None when
    the line is not a top-level function header.
    """
    match = FUNCTION.match(line)
    if not match:
        return None
    if not line.rstrip().endswith(":"):
        return None
    open_paren = match.end() - 1
    depth = 0
    for index in range(open_paren, len(line)):
        char = line[index]
        if char == "(":
            depth += 1
        elif char == ")":
            depth -= 1
            if depth == 0:
                return match.group(1), open_paren + 1, index
    return None


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


def find_calls(line: str, names: set[str]) -> list[tuple[str, int]]:
    """Return `(name, open_paren_index)`, rightmost first so appends stay valid."""
    found: list[tuple[str, int]] = []
    for name in names:
        for match in re.finditer(r"(?<![\w.])" + re.escape(name) + r"\s*\(", line):
            found.append((name, match.end() - 1))
    return sorted(found, key=lambda item: item[1], reverse=True)


def append_arguments(line: str, open_paren: int, additions: list[str]) -> str:
    """Append `additions` before the `)` matching the `(` at `open_paren`."""
    depth = 0
    for index in range(open_paren, len(line)):
        char = line[index]
        if char in "([{":
            depth += 1
        elif char in ")]}":
            depth -= 1
            if depth == 0:
                inner = line[open_paren + 1 : index].strip()
                joined = ", ".join(([inner] if inner else []) + additions)
                return line[: open_paren + 1] + joined + line[index:]
    return line


def migrate_source(text: str) -> tuple[str, int]:
    """Rewrite one guest source string. Line count is preserved."""
    if LAMBDA_PRINT.search(text):
        return text, 0
    lines = text.splitlines(keepends=True)
    functions: dict[str, tuple[int, int, int, int]] = {}
    for index, line in enumerate(lines):
        header = function_header(line.rstrip("\n"))
        if header:
            name, start, end = header
            body_start, body_end = body_bounds(lines, index)
            functions[name] = (index, start, end, body_start, body_end)
    # A user function shadowing `print`/`eprint` owns the name: leave the source alone.
    if "print" in functions or "eprint" in functions:
        return text, 0
    needs: dict[str, set[str]] = {name: set() for name in functions}
    for name, (_, _, _, start, end) in functions.items():
        body = "".join(lines[start:end])
        if PRINT.search(body):
            needs[name].add("out")
        if EPRINT.search(body):
            needs[name].add("err")
    # A helper that forwards a stream to a helper it calls needs that stream too.
    calls: dict[str, list[tuple[str, int]]] = {}
    for name, (_, _, _, start, end) in functions.items():
        body = "".join(lines[start:end])
        calls[name] = find_calls(body, set(functions) - {name})
    for _ in range(len(functions) + 1):
        grew = False
        for name, found in calls.items():
            for callee, _ in found:
                for stream in needs.get(callee, ()):
                    if stream not in needs[name]:
                        needs[name].add(stream)
                        grew = True
        if not grew:
            break
    changed = False
    for name, (header, params_start, params_end, start, end) in functions.items():
        if not needs[name]:
            continue
        ordered = [stream for stream in ("out", "err") if stream in needs[name]]
        signature = "".join(lines[header])[params_start:params_end]
        new_signature = add_parameters(signature, ordered)
        if new_signature != signature:
            line = lines[header]
            lines[header] = line[:params_start] + new_signature + line[params_end:]
            changed = True
        for index in range(start, end):
            original = lines[index]
            if "out" in needs[name]:
                lines[index] = PRINT.sub("out.print(", lines[index])
            if "err" in needs[name]:
                lines[index] = EPRINT.sub("err.print(", lines[index])
            for callee, offset in find_calls(lines[index], {c for c in functions if needs.get(c)}):
                additions = [stream for stream in ("out", "err") if stream in needs[callee]]
                if additions:
                    lines[index] = append_arguments(lines[index], offset, additions)
            changed = changed or lines[index] != original
    return "".join(lines), (1 if changed else 0)


def migrate_markdown(path: Path, check: bool) -> int:
    lines = path.read_text().splitlines(keepends=True)
    out: list[str] = []
    index = 0
    changed = 0
    while index < len(lines):
        if FENCE.match(lines[index]):
            out.append(lines[index])
            start = index + 1
            end = start
            while end < len(lines) and not FENCE_END.match(lines[end]):
                end += 1
            body = "".join(lines[start:end])
            new_body, did = migrate_source(body)
            changed += did
            out.extend(new_body.splitlines(keepends=True))
            if end < len(lines):
                out.append(lines[end])
            index = end + 1
            continue
        out.append(lines[index])
        index += 1
    if changed and not check:
        path.write_text("".join(out))
    return changed


def migrate_zig(path: Path, check: bool) -> int:
    lines = path.read_text().splitlines(keepends=True)
    out = list(lines)
    changed = 0
    index = 0
    while index < len(lines):
        match = MULTILINE.match(lines[index].rstrip("\n"))
        if not match:
            index += 1
            continue
        indent = match.group(1)
        start = index
        contents: list[str] = []
        while index < len(lines):
            inner = MULTILINE.match(lines[index].rstrip("\n"))
            if not inner or inner.group(1) != indent:
                break
            contents.append(inner.group(2))
            index += 1
        text = "\n".join(contents)
        if not re.search(r"^def\s+", text, re.MULTILINE):
            continue
        new_text, did = migrate_source(text)
        if not did:
            continue
        new_contents = new_text.split("\n")
        if len(new_contents) != len(contents):
            print(f"{path}: multiline literal changed line count; skipping", file=sys.stderr)
            continue
        for offset, content in enumerate(new_contents):
            out[start + offset] = indent + "\\\\" + content + "\n"
        changed += did
    if changed and not check:
        path.write_text("".join(out))
    return changed


def migrate(path: Path, check: bool) -> int:
    if path.suffix == ".md":
        return migrate_markdown(path, check)
    if path.suffix == ".zig":
        return migrate_zig(path, check)
    original = path.read_text()
    new_text, changed = migrate_source(original)
    if changed and not check:
        path.write_text(new_text)
    return changed


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("roots", nargs="+", type=Path)
    parser.add_argument("--check", action="store_true", help="report without writing")
    options = parser.parse_args()
    total = 0
    for root in options.roots:
        if root.is_dir():
            targets = sorted(
                path
                for pattern in ("*.my", "*.md", "*.zig")
                for path in root.rglob(pattern)
                if ".mylang-cache" not in path.parts and ".zig-cache" not in path.parts
            )
        else:
            targets = [root]
        for path in targets:
            changed = migrate(path, options.check)
            if changed:
                print(f"{path}: {changed} edit(s)", file=sys.stderr)
                total += changed
    print(f"{'would change' if options.check else 'changed'} {total} site(s)", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
