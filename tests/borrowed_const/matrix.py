#!/usr/bin/env python3
"""Generate the borrowed-`const` matrix (borrowed results R1, the performance plan's B7).

A `const name = place` binds a read-only borrow of a parameter, an element, a
field, a dictionary value or a local owner. The matrix crosses owners and places
with uses and owner events:

- owners: a plain parameter (a list of lists, a list, a record field, a dictionary
  value), a `mut` parameter, and a local (a list of lists, a record field, a
  dictionary value);
- uses: read, a plain argument, a `mut` argument, an `own` argument, a store, an
  append, a return;
- events: none, after the last use, a change of the owner before the use, a change
  in a branch or a loop before the use, and a move of a local owner before the use.

Accepted cells become `public func test_*() -> bool` entries in
`tests/lang/borrowed_const_matrix.selka`; `selka test` runs them in debug and in
release with `--verify-facts` and the leak check. Refused cells become
`tests/borrowed_const/refused/<cell>.selka` and are listed with their expected code in
`tests/borrowed_const/manifest.txt`; `src/core/borrowed_const_test.zig` proves each one
is refused with that code.

`--check` regenerates in memory and compares with the committed files, so a
template change without regeneration fails.
"""
import argparse
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
LANG_FILE = os.path.join(ROOT, "tests", "lang", "borrowed_const_matrix.selka")
REFUSED_DIR = os.path.join(ROOT, "tests", "borrowed_const", "refused")
MANIFEST = os.path.join(ROOT, "tests", "borrowed_const", "manifest.txt")

PRELUDE = """record Holder:
    items: int[]
    tag: int


func measure(xs: int[]) -> int:
    return len(xs)


func bump(mut xs: int[]):
    append(mut xs, 1)


func keep_own(own xs: int[]) -> int:
    return len(xs)
"""

# Owner kinds: the parameter list (None for a local), the argument that builds a
# parameter, the local declaration (None for a parameter), the place of the
# binding, whether the owner is `mut`, whether it is a local, and the owner's
# change statement and its type.
OWNERS = {
    "plain_rows": dict(param="o: int[][]", arg="[[1, 2, 3], [4, 5]]", decl=None, place="o[1]", mutable=False, local=False, change=None, rtype="int[]"),
    "plain_list": dict(param="o: int[]", arg="[4, 5]", decl=None, place="o", mutable=False, local=False, change=None, rtype="int[]"),
    "plain_field": dict(param="o: Holder", arg="Holder(items=[4, 5], tag=0)", decl=None, place="o.items", mutable=False, local=False, change=None, rtype="int[]"),
    "plain_dict": dict(param="o: dict[str, int[]]", arg='{"a": [4, 5]}', decl=None, place='o["a"]', mutable=False, local=False, change=None, rtype="int[]"),
    "mut_rows": dict(param="mut o: int[][]", arg="[[1, 2, 3], [4, 5]]", decl=None, place="o[1]", mutable=True, local=False, change="append(mut o, [7])", rtype="int[]"),
    "local_rows": dict(param=None, arg=None, decl="mut o: int[][] = [[1, 2, 3], [4, 5]]", place="o[1]", mutable=True, local=True, change="append(mut o, [7])", rtype="int[]"),
    "local_field": dict(param=None, arg=None, decl="mut o = Holder(items=[4, 5], tag=0)", place="o.items", mutable=True, local=True, change="o.items = [7]", rtype="int[]"),
    "local_dict": dict(param=None, arg=None, decl='mut o: dict[str, int[]] = {"a": [4, 5]}', place='o["a"]', mutable=True, local=True, change='o["z"] = [7]', rtype="int[]"),
}

# Uses: the statements that read the binding `e`, and the refusal code each
# expects (None for an accepted use). The total is `total`, declared by the cell.
USES = {
    "read": dict(lines=["total += len(e)"], expect=None),
    "arg": dict(lines=["total += measure(e)"], expect=None),
    "mutarg": dict(lines=["bump(mut e)", "total += len(e)"], expect="E_IMMUTABLE"),
    "ownarg": dict(lines=["total += keep_own(own e)"], expect="E_OWN_MARKER"),
    # `mut kept = e` stored once from a place borrows it, as a `const` does (D4, lane OC's H1, 10 November 2026).
    "store": dict(lines=["mut kept = e", "total += len(kept)"], expect=None),
    "append": dict(lines=["mut sink: int[][] = []", "append(mut sink, e)", "total += len(sink)"], expect="E_OWN_MARKER"),
}

# The cells: (owner, use, event). An event is one of none, after, change, branch,
# loop, move. `after` and `change` are only for mutable owners; `move` only for locals.
CELLS = []
for owner in ["plain_rows", "plain_list", "plain_field", "plain_dict"]:
    for use in USES:
        CELLS.append((owner, use, "none"))
for owner in ["mut_rows", "local_rows", "local_field", "local_dict"]:
    CELLS.append((owner, "read", "none"))
    CELLS.append((owner, "arg", "none"))
    CELLS.append((owner, "read", "after"))
    CELLS.append((owner, "read", "change"))
    CELLS.append((owner, "read", "branch"))
    CELLS.append((owner, "read", "loop"))
    for use in ["mutarg", "ownarg", "store", "append"]:
        CELLS.append((owner, use, "none"))
    if OWNERS[owner]["local"]:
        CELLS.append((owner, "read", "move"))
CELLS.append(("plain_list", "return", "none"))

# An event's statements, placed before the use unless `after`.
EVENT_EXPECT = {
    "none": None,
    "after": None,
    "change": "E_SINGLE_OWNER_OVERLAP",
    "branch": "E_SINGLE_OWNER_OVERLAP",
    "loop": "E_SINGLE_OWNER_OVERLAP",
    "move": "E_SINGLE_OWNER_OVERLAP",
}


def cell_name(owner, use, event):
    """The cell's name: owner, use and event joined by underscores."""
    return f"{owner}_{use}_{event}"


def indent(lines, depth):
    """Indent each line by `depth` four-space levels."""
    pad = "    " * depth
    return [pad + line if line else line for line in lines]


def body(owner, use, event):
    """The statements of the cell's function body, and the expected refusal (or None)."""
    spec = OWNERS[owner]
    lines = []
    if spec["decl"] is not None:
        lines.append(spec["decl"])
    if use == "return":
        lines.append(f"const e = {spec['place']}")
        lines.append("return e")
        return lines, None
    lines.append("mut total = 0")
    lines.append(f"const e = {spec['place']}")
    use_lines = USES[use]["lines"]
    change = spec["change"]
    if event == "change":
        lines.append(change)
        lines.extend(use_lines)
    elif event == "branch":
        lines.append("if total == 0:")
        lines.extend(indent([change], 1))
        lines.extend(use_lines)
    elif event == "loop":
        lines.append("for i in range(1):")
        lines.extend(indent([change] + use_lines, 1))
    elif event == "move":
        lines.append("const moved = own o")
        lines.extend(use_lines)
    elif event == "after":
        lines.extend(use_lines)
        lines.append(change)
    else:
        lines.extend(use_lines)
    lines.append("return total")
    expect = USES[use]["expect"] or EVENT_EXPECT[event]
    return lines, expect


def cell_source(owner, use, event):
    """The cell's function (named `cell_<name>`) and its refusal, if any."""
    name = cell_name(owner, use, event)
    spec = OWNERS[owner]
    if use == "return":
        # Returning the borrowed binding requires a declared source. This
        # refusal cell deliberately omits `from o`; the const alone cannot
        # authorize a borrowed result under R4.
        lines, _ = body(owner, use, event)
        signature = f"func cell_{name}({spec['param'] or ''}) -> {spec['rtype']}:"
        expect = "E_BORROW_UNDECLARED"
    else:
        lines, expect = body(owner, use, event)
        signature = f"func cell_{name}({spec['param'] or ''}) -> int:"
    text = [signature] + indent(lines, 1)
    return name, "\n".join(text) + "\n", expect


def accepted_test(owner, use, event):
    """The public test that calls an accepted cell and checks its value."""
    name = cell_name(owner, use, event)
    spec = OWNERS[owner]
    if spec["param"] is not None and spec["param"].startswith("mut "):
        # A `mut` parameter takes a named writable argument at the call.
        return (f"public func test_{name}() -> bool:\n    mut data = {spec['arg']}\n"
                f"    return cell_{name}(mut data) == 2\n")
    return f"public func test_{name}() -> bool:\n    return cell_{name}({spec['arg'] or ''}) == 2\n"


def build():
    """Return the accepted guest file text, and the refused cells as (name, source, code)."""
    accepted = [PRELUDE]
    refused = []
    tests = []
    for owner, use, event in CELLS:
        name, source, expect = cell_source(owner, use, event)
        if expect is None:
            accepted.append(source)
            if use != "return":
                tests.append(accepted_test(owner, use, event))
        else:
            refused.append((name, PRELUDE + "\n\n" + source + "\n\nfunc main(out: Stream) -> int:\n    print(out, 0)\n    return 0\n", expect))
    lang = "# Borrowed `const` matrix (generated by tests/borrowed_const/matrix.py; do not edit).\n" \
        "# Each cell binds a place of a parameter or a local owner with `const`; accepted cells must\n" \
        "# check and return 2, refused cells are in tests/borrowed_const/refused.\n" \
        + "\n\n".join(accepted) + "\n\n" + "\n\n".join(tests)
    return lang, refused


def manifest_text(refused):
    """The manifest: one line per refused cell, `refused <cell> <code> [<code>...]`; the compiler's first code must be one of them."""
    lines = ["# borrowed-const matrix: one line per refused cell (kind, cell, the refusal codes it may take)"]
    for name, _, code in refused:
        lines.append(f"refused {name} {code}")
    return "\n".join(lines) + "\n"


def expected_files():
    """Map each committed path to its generated text."""
    lang, refused = build()
    files = {LANG_FILE: lang, MANIFEST: manifest_text(refused)}
    for name, source, _ in refused:
        files[os.path.join(REFUSED_DIR, f"{name}.selka")] = source
    return files


def main():
    """Write the matrix, or with --check compare it with the committed files."""
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--check", action="store_true", help="fail if a committed file differs from the generator")
    args = parser.parse_args()
    files = expected_files()
    if args.check:
        stale = []
        for path, text in files.items():
            try:
                with open(path, encoding="utf-8") as handle:
                    current = handle.read()
            except FileNotFoundError:
                current = None
            if current != text:
                stale.append(os.path.relpath(path, ROOT))
        if stale:
            print("borrowed-const matrix is stale: " + ", ".join(stale))
            return 1
        print("borrowed-const matrix is current")
        return 0
    os.makedirs(REFUSED_DIR, exist_ok=True)
    for path, text in files.items():
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(text)
    print(f"wrote {len(files)} files")
    return 0


if __name__ == "__main__":
    sys.exit(main())
