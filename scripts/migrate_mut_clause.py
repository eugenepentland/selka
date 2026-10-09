#!/usr/bin/env python3
"""Mechanically migrate a `mutates(...)` clause to `name: mut T` parameters.

A declared `mutates(a, b)` footprint and the set of `name: mut T` parameters
describe the same fact, so this rewrites one into the other: each named parameter
gains `mut` before its declared type and the clause disappears. Call sites are
deliberately left alone -- adding the required `mut` argument marker is a
separate pass driven by the compiler's own `E_MUTATION_MARKER` paste, so a
half-migrated file fails loudly instead of silently changing meaning.

A clause on a callback type names that callback's parameters, while a clause after
a declared signature names the function's own parameters. Each clause is matched
to the bracket group it annotates by scanning the top-level bracket pairs that
close before it and keeping the last one followed by nothing but a result type and
an effect ceiling. A rewrite joins parameters with `, ` and single spaces, which
is the spelling the formatter produces anyway.

Usage: python3 scripts/migrate_mut_clause.py FILE.selka [FILE.selka ...]
"""

import re
import sys

# `mutates(a)` / `mutates(a, b)` after a declared or callback parameter list.
CLAUSE = re.compile(r"mutates\(([^()]*)\)")


def split_parameters(text):
    """The top-level comma-separated parameters of one parameter list."""
    parts = []
    depth = 0
    current = ""
    for character in text:
        if character in "([":
            depth += 1
        elif character in ")]":
            depth -= 1
        if character == "," and depth == 0:
            parts.append(current)
            current = ""
            continue
        current += character
    parts.append(current)
    return [part for part in (part.strip() for part in parts) if part]


def parameter_name(text):
    """The declared name of one parameter, or None when it declares none."""
    head = text.split(":", 1)[0].split("=", 1)[0].strip()
    return head if head.isidentifier() else None


# A `def` head directly in front of a parameter list: the keyword, the declared
# name, and an optional generic parameter list. Both a declared signature and a
# callback type are written this way, and nothing else is.
# The name cannot be `def` itself, so the head matched is never the `def` of a
# callback type written as a parameter of an enclosing declaration.
DEF_HEAD = re.compile(r"\bdef\s+(?!def\b)[\w.]+(\s*\[[^\[\]]*\])?\s*$")


def is_parameter_list(text, start):
    """Whether the bracket opening at `start` opens a parameter list.

    Only a `def` head introduces one, so the arguments of an ordinary call -- and
    in particular the `effects(...)` ceiling -- are never mistaken for a list a
    clause could annotate. The head is looked for on the bracket's own line, and
    its name may not be `def`, so a callback type in a parameter never counts as
    the head of the declaration that contains it.
    """
    line_start = text.rfind("\n", 0, start) + 1
    return DEF_HEAD.search(text[line_start:start]) is not None


def parameter_spans(text):
    """Every top-level bracket group of `text`, in source order.

    Depth is tracked per bracket kind, so a group inside a template argument
    (`list[int]`) or a callback type never appears as a group of its own. Each
    entry is `(open_index, close_index)`.
    """
    kinds = {"(": ")", "[": "]", "{": "}"}
    stack = []
    spans = []
    for index, character in enumerate(text):
        if character in kinds:
            stack.append((character, index))
        elif character in ")]}":
            if not stack or kinds[stack[-1][0]] != character:
                continue
            opener, at = stack.pop()
            del opener
            if not stack:
                spans.append((at, index))
    return spans


def trailing_span(text, limit):
    """The parameter list one clause annotates, as `(start, end)` inside it.

    Walking back from the clause, the first bracket group that opens a parameter
    list is the one the clause names: the function's own list for a declared
    clause, and the callback's own list for a clause written inside a parameter
    type. The `effects(...)` ceiling between them is a call, not a list.
    """
    spans = parameter_spans(text[:limit])
    for start, close in reversed(spans):
        if not is_parameter_list(text, start):
            continue
        return (start + 1, close)
    return None


def rewrite(text, start, end, names):
    """Add `mut` to every parameter of `text[start:end]` that `names` lists."""
    rewritten = []
    for part in split_parameters(text[start:end]):
        declared_name = parameter_name(part)
        _, separator, declared = part.partition(":")
        if separator and declared_name in names and not declared.strip().startswith("mut "):
            rewritten.append(f"{declared_name}: mut {declared.strip()}")
        else:
            rewritten.append(" ".join(part.split()))
    return text[:start] + ", ".join(rewritten) + text[end:]


def find_clause(text, names, after):
    """Offset of the clause naming exactly `names` at or after `after`."""
    for candidate in CLAUSE.finditer(text):
        if candidate.start() < after:
            continue
        found = [name.strip() for name in candidate.group(1).split(",") if name.strip()]
        if found == names:
            return candidate.start()
    return -1


def migrate(text):
    """Migrate every clause in one source text. Returns the text and the count.

    Clauses are rewritten right to left so removing one never moves the text the
    next one is measured against.
    """
    count = 0
    for match in reversed(list(CLAUSE.finditer(text))):
        names = [name.strip() for name in match.group(1).split(",") if name.strip()]
        if not names:
            text = text[: match.start()] + text[match.end() :]
            continue
        span = trailing_span(text, match.start())
        if span is None:
            continue
        start, end = span
        text = rewrite(text, start, end, names)
        offset = find_clause(text, names, start)
        if offset < 0:
            continue
        text = text[:offset].rstrip() + text[text.index(")", offset) + 1 :]
        count += 1
    return text, count


def main(argv):
    if len(argv) < 2:
        print(__doc__, file=sys.stderr)
        return 2
    total = 0
    for path in argv[1:]:
        with open(path, "r", encoding="utf-8") as handle:
            text = handle.read()
        migrated, count = migrate(text)
        if count == 0:
            continue
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(migrated)
        print(f"{path}: {count} clause(s)")
        total += count
    print(f"{total} clause(s) migrated")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
