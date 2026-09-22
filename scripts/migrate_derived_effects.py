#!/usr/bin/env python3
"""Delete effect clauses that only restate the ceiling a signature implies.

A function's effect ceiling is derived from its parameter list: a `Stream`
parameter permits `output`, a `Filesystem` parameter `filesystem`, `Network`
`network`, `Clock` `clock`, `Entropy` `random`, `Environment` `environment`, a
`Host` parameter `host`, a `mut` parameter `mutation`, a callback parameter its
own declared ceiling, and allocation is always permitted. A clause that permits
exactly that set says nothing, so it is deleted; a clause that permits less is a
narrowing and stays.

Only `effects(...)` can name an effect no parameter supplies, so a positive
clause that names one is left alone -- removing the unused capability parameter
that used to supply it is a separate, compiler-driven pass. `noalloc` is never
redundant because allocation is always permitted; a `noio` clause on a function
with no io-capable parameter is.

`host def` and `extern def` declarations are never touched: they have no body,
and their clause is the authority they declare rather than a summary of their
parameters.

Usage: python3 scripts/migrate_derived_effects.py [--apply] FILE_OR_DIR ...
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

CAPABILITY_EFFECTS = {
    "Filesystem": "filesystem",
    "Network": "network",
    "Clock": "clock",
    "Entropy": "random",
    "Environment": "environment",
    "Stream": "output",
    "Host": "host",
}
ALL_EFFECTS = (
    "filesystem",
    "network",
    "clock",
    "random",
    "environment",
    "host",
    "managed_allocation",
    "output",
    "mutation",
)
IO_EFFECTS = {"filesystem", "network", "output"}

DECL = re.compile(
    r"^[ \t]*(?P<mods>(?:(?:public|export|host|extern|restricted|conversion)[ \t]+)*)def[ \t]+"
    r"(?P<name>[A-Za-z_][A-Za-z0-9_]*)[ \t]*(?P<generics>\[[^\]]*\])?[ \t]*\(",
    re.MULTILINE,
)


def match_close(text: str, open_index: int) -> int:
    """Index of the bracket closing the group that opens at `open_index`."""
    pairs = {"(": ")", "[": "]", "{": "}"}
    stack = [text[open_index]]
    for i in range(open_index + 1, len(text)):
        if text[i] in pairs:
            stack.append(text[i])
        elif text[i] in ")]}":
            if not stack or pairs[stack[-1]] != text[i]:
                return -1
            stack.pop()
            if not stack:
                return i
    return -1


def split_top_level(text: str) -> list[str]:
    """The top-level comma-separated pieces of one parameter list body."""
    parts, depth, current = [], 0, ""
    for ch in text:
        if ch in "([":
            depth += 1
        elif ch in ")]":
            depth -= 1
        if ch == "," and depth == 0:
            parts.append(current)
            current = ""
            continue
        current += ch
    parts.append(current)
    return [p for p in (x.strip() for x in parts) if p]


def skip_type(text: str, i: int) -> int:
    """Index just past one type expression spelled in `text` at `i`."""
    if text.startswith("def(", i):
        close = match_close(text, i + 3)
        if close < 0:
            return len(text)
        i = close + 1
        arrow = re.compile(r"\s*->\s*").match(text, i)
        if arrow:
            i = skip_type(text, arrow.end())
        clause = re.compile(r"\s*effects\s*\(").match(text, i)
        if clause:
            i = match_close(text, clause.end() - 1) + 1
        return i
    start = i
    depth = 0
    while i < len(text):
        ch = text[i]
        if depth == 0 and i > start and re.match(r"[ \t]+(effects[ \t]*\(|noalloc\b|noio\b)", text[i:]):
            break
        if ch in "([":
            depth += 1
        elif ch in ")]":
            if depth == 0:
                break
            depth -= 1
        elif depth == 0 and (ch == ":" or text.startswith("->", i)):
            break
        i += 1
    return i


class Clause:
    def __init__(self, kind: str, span: tuple[int, int], mask: set[str]):
        self.kind = kind
        self.span = span
        self.mask = mask

    @property
    def text(self) -> str:
        return ""


def parse_clause(text: str, i: int):
    """Parse an optional clause at `i`; returns (clause or None, end index)."""
    match = re.compile(r"[ \t]*(effects[ \t]*\(|noalloc|noio)").match(text, i)
    if not match:
        return None, i
    spelling = match.group(1)
    if spelling.startswith("effects"):
        close = match_close(text, match.end() - 1)
        if close < 0:
            return None, i
        body = text[match.end() : close]
        mask = {name.strip() for name in body.split(",") if name.strip()}
        return Clause("effects", (match.start(1), close + 1), mask), close + 1
    if spelling == "noalloc":
        return Clause("noalloc", (match.start(1), match.end(1)), set(ALL_EFFECTS) - {"managed_allocation"}), match.end(1)
    return Clause("noio", (match.start(1), match.end(1)), set(ALL_EFFECTS) - IO_EFFECTS), match.end(1)


def parse_parameters(text: str) -> list[tuple[str, bool, str]]:
    """(name, is_mut, type text) for every parameter of one parameter list body."""
    parameters = []
    for part in split_top_level(text):
        mut = False
        head, separator, rest = part.partition(":")
        if not separator:
            parameters.append((part.strip(), False, ""))
            continue
        declared_type = rest.split("=", 1)[0].strip()
        if declared_type.startswith("mut "):
            mut = True
            declared_type = declared_type[4:].strip()
        parameters.append((head.strip(), mut, declared_type))
    return parameters


def derived_mask(parameters: list[tuple[str, bool, str]]) -> set[str]:
    mask = {"managed_allocation"}
    for _, mut, declared_type in parameters:
        if mut:
            mask.add("mutation")
        base = declared_type.split("[", 1)[0].strip()
        if base in CAPABILITY_EFFECTS:
            mask.add(CAPABILITY_EFFECTS[base])
        if declared_type.startswith("def("):
            clause = re.search(r"effects\s*\(([^)]*)\)", declared_type)
            if clause:
                mask |= {name.strip() for name in clause.group(1).split(",") if name.strip()}
    return mask


def function_body(text: str, header_end: int) -> tuple[int, int]:
    """The indented block after `header_end`, or an empty span for a declaration."""
    colon = text.find(":", header_end)
    line_end = text.find("\n", header_end)
    if colon < 0 or (line_end >= 0 and colon > line_end):
        return (header_end, header_end)
    indent_end = colon + 1
    end = indent_end
    for line in text[indent_end:].split("\n"):
        if line.strip() and not line.startswith((" ", "\t")):
            break
        end += len(line) + 1
    return (indent_end, min(end, len(text)))


def migrate(text: str):
    """Yield (start, end, description) deletions for one source text."""
    deletions = []
    for declaration in DECL.finditer(text):
        mods = declaration.group("mods").split()
        if "host" in mods or "extern" in mods:
            continue
        open_paren = declaration.end() - 1
        close = match_close(text, open_paren)
        if close < 0:
            continue
        parameters = parse_parameters(text[open_paren + 1 : close])
        i = close + 1
        arrow = re.compile(r"\s*->\s*").match(text, i)
        if arrow:
            i = skip_type(text, arrow.end())
        clause, _ = parse_clause(text, i)
        if clause is None:
            continue
        derived = derived_mask(parameters)
        if clause.kind == "effects":
            if clause.mask == derived:
                deletions.append((*clause.span, f"{declaration.group('name')}: restating effects({', '.join(sorted(clause.mask))})"))
            continue
        if clause.kind == "noio" and derived <= clause.mask:
            deletions.append((*clause.span, f"{declaration.group('name')}: restating noio"))
    return deletions


def main(argv):
    apply = "--apply" in argv
    targets = [a for a in argv[1:] if not a.startswith("--")]
    files = []
    for target in targets:
        path = Path(target)
        files.extend(sorted(path.rglob("*.my")) if path.is_dir() else [path])
    total = 0
    for path in files:
        text = path.read_text(encoding="utf-8")
        deletions = migrate(text)
        if not deletions:
            continue
        total += len(deletions)
        print(f"{path}: {len(deletions)} clause(s)")
        for start, end, description in deletions:
            print(f"  {description}")
        if apply:
            for start, end, _ in sorted(deletions, reverse=True):
                text = text[:start].rstrip() + text[end:]
            path.write_text(text, encoding="utf-8")
    print(f"{total} clause(s) {'removed' if apply else 'to remove'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
