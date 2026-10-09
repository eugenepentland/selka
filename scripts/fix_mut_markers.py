#!/usr/bin/env python3
"""Add the `mut` call-site markers the compiler asks for.

The checker's `E_MUTATION_MARKER` message for a missing marker carries the paste
("`f` writes `x`; write `f(mut x)`") and the diagnostic's location is the argument
expression. The insertion offset is derived from the file's own text rather than
from the diagnostic's byte span, because a project diagnostic reports positions in
the merged project source while this script edits one file. The compiler is re-run
after each round, since adding a marker can expose the next one.

Usage: python3 scripts/fix_mut_markers.py [--compiler PATH] FILE.selka [FILE.selka ...]
"""

import json
import os
import subprocess
import sys

DEFAULT_COMPILER = "zig-out/bin/selka"


def diagnostics(compiler, path):
    """Every `E_MUTATION_MARKER` diagnostic a project reports, with its own file.

    A project diagnostic names the module's own path and reports its line and
    column in that module, so a marker is never inserted into the entry file for
    an argument that lives in an import.
    """
    result = subprocess.run([compiler, "check", "--diagnostics=json", path], capture_output=True, text=True)
    found = []
    for line in result.stdout.splitlines() + result.stderr.splitlines():
        line = line.strip()
        if not line.startswith("{"):
            continue
        try:
            diagnostic = json.loads(line)["diagnostic"]
        except (KeyError, ValueError):
            continue
        if diagnostic["code"] != "E_MUTATION_MARKER":
            continue
        found.append((diagnostic["location"], diagnostic["message"]))
    return found


def resolve(entry, location):
    """The source file one diagnostic location belongs to, or None."""
    named = location.get("path") or entry
    candidate = os.path.join(os.path.dirname(os.path.abspath(entry)), named)
    if os.path.exists(candidate):
        return candidate
    return entry if not os.path.isabs(named) else (named if os.path.exists(named) else None)


def missing_marker(message):
    """Whether one message asks for a marker on an argument."""
    return "; write `" in message and "(mut " in message


def declared_parameters(message):
    """The `name: mut T` declarations one declaration-side message asks for."""
    marker = "reachable from the caller; declare "
    if marker not in message:
        return []
    paste = message.split(marker, 1)[1].strip()
    if not paste.startswith("`"):
        return []
    found = []
    for fragment in paste.strip("`").split("`, `"):
        name, separator, declared = fragment.partition(": mut ")
        if separator and declared:
            found.append((name.strip(), declared.strip()))
    return found


def offset_of(text, line, column):
    """Byte offset of a one-based line and column in `text`."""
    at = 0
    for _ in range(line - 1):
        newline = text.find(b"\n", at)
        if newline < 0:
            return None
        at = newline + 1
    end = text.find(b"\n", at)
    if end < 0:
        end = len(text)
    target = at + column - 1
    return target if target <= end else None


def unused_marker(message):
    """Whether one message asks for a `mut` to be removed from a parameter."""
    return "; remove `mut`: `" in message


def remove_mut(text, at):
    """Delete the `mut ` the compiler blamed at `at`.

    `at` is the marker's own offset at a call site, and at a declaration it is
    either the marker or the parameter name, in which case the marker sits
    between the name's colon and the declared type.
    """
    if text[at : at + 4] == b"mut ":
        return text[:at] + text[at + 4 :], 1
    line_end = text.find(b"\n", at)
    line_end = len(text) if line_end < 0 else line_end
    line_start = text.rfind(b"\n", 0, at) + 1
    marker = text.rfind(b"mut ", line_start, at)
    if marker < 0:
        colon = text.find(b":", at, line_end)
        marker = text.find(b"mut ", colon, colon + 8)
    if marker < 0:
        return text, 0
    return text[:marker] + text[marker + 4 :], 1


def parameter_list(text, at):
    """The `(start, end)` of the parameter list whose `(` follows offset `at`."""
    open_at = text.find(b"(", at, at + 200)
    if open_at < 0:
        return None
    depth = 0
    for index in range(open_at, min(len(text), open_at + 1024)):
        if text[index : index + 1] == b"(":
            depth += 1
        elif text[index : index + 1] == b")":
            depth -= 1
            if depth == 0:
                return (open_at, index)
    return None


def declare(text, span, names):
    """Insert `mut ` before the declared type of each named parameter.

    `span` is the extent of one statement the compiler blamed. The function's
    parameter list is the first `(` that follows a `def` head before that
    statement, and a parameter is only rewritten inside that list.
    """
    head = text.rfind(b"def ", 0, span[0])
    if head < 0:
        return text, 0
    bounds = parameter_list(text, head)
    if bounds is None:
        return text, 0
    start, end = bounds
    added = 0
    for name, _ in names:
        token = name.encode()
        found = text.find(token, start, end)
        if found < 0:
            continue
        colon = text.find(b":", found + len(token), end)
        if colon < 0:
            continue
        if text[colon + 1 : colon + 6] == b" mut ":
            continue
        text = text[: colon + 1] + b" mut " + text[colon + 2 :]
        end += 4
        added += 1
    return text, added


def insertions(compiler, entry):
    """Per file: argument offsets to mark, and declarations to extend.

    Argument offsets are byte offsets in the module's own text, rightmost first.
    Declaration requests are the function's own name span, which `declare` reads
    the parameter list from.
    """
    wanted = {}
    declarations = {}
    removals = {}
    for location, message in diagnostics(compiler, entry):
        target = resolve(entry, location)
        if target is None:
            continue
        with open(target, "rb") as handle:
            text = handle.read()
        at = offset_of(text, location["start"]["line"], location["start"]["column"])
        if at is None:
            continue
        if unused_marker(message) or (not missing_marker(message) and "remove `mut`" in message):
            removals.setdefault(target, set()).add(at)
            continue
        if missing_marker(message):
            wanted.setdefault(target, set()).add(at)
            continue
        names = declared_parameters(message)
        if not names:
            continue
        start = offset_of(text, location["start"]["line"], location["start"]["column"])
        end = offset_of(text, location["end"]["line"], location["end"]["column"])
        if start is None or end is None:
            continue
        declarations.setdefault(target, {}).setdefault((start, end), names)
    return (
        {target: sorted(offsets, reverse=True) for target, offsets in wanted.items()},
        declarations,
        {target: sorted(offsets, reverse=True) for target, offsets in removals.items()},
    )


def fix(path, compiler, rounds=8):
    """Insert every requested marker in the project, re-checking after each round."""
    added = 0
    for _ in range(rounds):
        wanted, declarations, removals = insertions(compiler, path)
        if not wanted and not declarations and not removals:
            break
        changed = False
        for target, offsets in removals.items():
            with open(target, "rb") as handle:
                original = handle.read()
            text = original
            for at in offsets:
                text, count = remove_mut(text, at)
                added += count
            if text == original:
                continue
            changed = True
            with open(target, "wb") as handle:
                handle.write(text)
        for target, requests in declarations.items():
            with open(target, "rb") as handle:
                original = handle.read()
            text = original
            for (start, end), names in requests.items():
                text, count = declare(text, (start, end), names)
                added += count
            if text == original:
                continue
            changed = True
            with open(target, "wb") as handle:
                handle.write(text)
        for target, offsets in wanted.items():
            # Byte offsets, so each file is read and rewritten as bytes: a decoded
            # string indexes code points, and one non-ASCII character before an
            # offset would shift every later insertion.
            with open(target, "rb") as handle:
                original = handle.read()
            text = original
            for at in offsets:
                if text[max(0, at - 4) : at] == b"mut ":
                    continue
                text = text[:at] + b"mut " + text[at:]
                added += 1
            if text == original:
                continue
            changed = True
            with open(target, "wb") as handle:
                handle.write(text)
        if not changed:
            break
    return added


def main(argv):
    compiler = DEFAULT_COMPILER
    paths = []
    index = 1
    while index < len(argv):
        if argv[index] == "--compiler":
            index += 1
            compiler = argv[index]
        else:
            paths.append(argv[index])
        index += 1
    if not paths:
        print(__doc__, file=sys.stderr)
        return 2
    total = 0
    for path in paths:
        added = fix(path, compiler)
        if added:
            print(f"{path}: {added} marker(s)")
        total += added
    print(f"{total} marker(s) added")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
