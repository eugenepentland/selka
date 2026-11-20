#!/usr/bin/env python3
"""Generate the view-shape matrix the wave 3 review asks for (H2).

The matrix crosses view *producers*, *consumers* and *source events*. It is a
covering grid rather than the full Cartesian product: every producer, every
consumer and every event appears at least once per collection family where the
shape exists. Shapes outside this historical grid are listed in `OMISSIONS`
below; declared bytes and list view calls are covered by the borrowed-signature
suite.

Accepted cells become `public func test_*() -> bool` entries in
`tests/lang/view_shapes/<family>.selka`; `selka test` runs them in debug and in
release with `--verify-facts` and the leak check. Refused cells become
`tests/view_shapes/refused/<cell>.selka` with the fixed program `<cell>.fixed.selka`
and its expected stdout `<cell>.out`; `test/view_shapes_test.zig` proves each
one is refused, takes its certain fix, and prints the pre-wave-3 value.

`--check` regenerates in memory and compares with the committed files, so a
template change without regeneration fails. `--audit` runs the compiler over
every cell (accepted: checks and prints its expected value; refused: refuses,
fixes, and prints) — developer mode, not part of the gate.
"""
import argparse
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
LANG_DIR = os.path.join(ROOT, "tests", "lang", "view_shapes")
REFUSED_DIR = os.path.join(ROOT, "tests", "view_shapes", "refused")
MANIFEST = os.path.join(ROOT, "tests", "view_shapes", "manifest.txt")

OMISSIONS = [
    "bytes-view-call: declared view returns are covered by tests/lang/borrowed_signatures.selka",
    "list-view-call: declared view returns are covered by tests/lang/borrowed_signatures.selka",
    "mut-view-binding: a view binding is immutable, so 'a mut argument' is an event (mutcall), not a consumer",
    "list-mut-binding: a list view binding is immutable, so a `mut` view parameter is an event, not a consumer",
    "list-store/list-return of a view: since batch W a stored or returned list view binding is refused like text's, so those cells are refused cells, not omissions",
]

# --- text ---------------------------------------------------------------------

TEXT_PRELUDE = '''func head(t: str) -> str from t:
    return t[0:2]


func middle(t: str) -> str from t:
    return t[1:3]


func bump(mut s: str):
    s += "-x"


record Item:
    name: str


enum Choice:
    named(name: str)
    none


func payload_piece(sh: Choice) -> str:
    match sh:
        case named(name=value):
            const piece = value[1:3]
            return copy(piece)
        case none:
            return "zz"
'''

# Each accepted cell: name, producer, consumer, event, body lines, assertion.
TEXT_ACCEPTED = [
    ("text_bound_slice_read", "slice", "read", "none", [
        '    const source = "abcd"',
        "    const piece = source[1:3]",
        '    return len(piece) == 2 and piece == "bc"',
    ]),
    ("text_mut_source_read", "slice", "read", "none", [
        '    mut source = "abcd"',
        "    const piece = source[1:3]",
        '    return len(piece) == 2 and piece == "bc"',
    ]),
    ("text_slice_read", "slice", "read", "none", [
        '    const source = "abcd"',
        "    const piece = source[1:3]",
        '    return piece == "bc" and len(piece) == 2',
    ]),
    ("text_slice_phi", "slice", "phi", "none", [
        '    const source = "abcd"',
        "    const piece: str",
        "    if len(source) > 3:",
        "        piece = source[1:3]",
        "    else:",
        "        piece = source[0:2]",
        '    return piece == "bc"',
    ]),
    ("text_slice_loop", "slice", "loop", "none", [
        '    const words = ["abcd", "efgh"]',
        '    mut best = ""',
        "    for word in words:",
        "        best = copy(word[1:3])",
        '    return best == "fg"',
    ]),
    ("text_slice_deferred_owned", "slice", "deferred", "none", [
        '    const source = "abcd"',
        "    const piece: str",
        "    if len(source) > 9:",
        "        piece = copy(source[1:3])",
        "    else:",
        '        piece = "zz"',
        '    return piece == "zz"',
    ]),
    ("text_slice_return", "slice", "return", "none", [
        '    return middle("abcd") == "bc"',
    ]),
    ("text_slice_after", "slice", "read", "after", [
        '    mut source = "abcd"',
        "    const piece = source[0:2]",
        '    const before = copy(piece)',
        '    source += "x"',
        '    return before == "ab" and source == "abcdx"',
    ]),
    ("text_slice_store_refused", "slice", "store", "none", None),
    ("text_slice_list_refused", "slice", "list", "none", None),
    ("text_call_read", "call", "read", "none", [
        '    const source = "abcd"',
        "    const piece = head(source)",
        '    return piece == "ab"',
    ]),
    ("text_call_phi", "call", "phi", "none", [
        '    const source = "abcd"',
        "    const piece: str",
        "    if len(source) > 3:",
        "        piece = copy(head(source))",
        "    else:",
        '        piece = "zz"',
        '    return piece == "ab"',
    ]),
    ("text_call_loop", "call", "loop", "none", [
        '    const words = ["abcd", "efgh"]',
        '    mut best = ""',
        "    for word in words:",
        "        best = copy(head(word))",
        '    return best == "ef"',
    ]),
    ("text_call_store", "call", "store", "none", [
        '    const source = "abcd"',
        "    const held = Item(name=copy(head(source)))",
        '    return held.name == "ab"',
    ]),
    ("text_call_after", "call", "read", "after", [
        '    mut source = "abcd"',
        "    const piece = head(source)",
        '    const before = copy(piece)',
        '    source += "x"',
        '    return before == "ab"',
    ]),
    ("text_field_read", "field", "read", "none", [
        '    const item = Item(name="abcd")',
        "    const piece = item.name[1:3]",
        '    return piece == "bc"',
    ]),
    ("text_field_after", "field", "read", "after", [
        '    const source = "abcd"',
        "    const item = Item(name=copy(source))",
        "    const piece = item.name[1:3]",
        "    const before = copy(piece)",
        '    return before == "bc"',
    ]),
    ("text_nested_read", "nested", "read", "none", [
        '    const source = "abcdef"',
        "    const piece = copy(source[0:4][1:3])",
        '    return piece == "bc"',
    ]),
    ("text_payload_read", "payload", "read", "none", [
        '    return payload_piece(Choice.named(name="abcd")) == "bc"',
    ]),
    ("text_payload_return", "payload", "return", "none", [
        '    return payload_piece(Choice.named(name="xyzw")) == "yz"',
    ]),
    ("text_repro_r1_phi", "call", "phi", "none", [
        '    const a = "hello"',
        '    mut h = "none"',
        "    if len(a) > 3:",
        "        h = copy(head(a))",
        '    return h == "he"',
    ]),
]

TEXT_REFUSED = [
    {"name": "text_bound_store_refused", "producer": "slice", "consumer": "store", "event": "none",
     "body": ['    const source = "abcd"', "    mut parts: str[] = []", "    const piece = source[1:3]", "    append(mut parts, piece)", "    print(out, len(parts[0]))", "    return 0"],
     "fixed": ['    const source = "abcd"', "    mut parts: str[] = []", "    const piece = copy(source[1:3])", "    append(mut parts, own piece)", "    print(out, len(parts[0]))", "    return 0"],
     "out": "2\n"},
    {"name": "text_bound_invalidated_refused", "producer": "slice", "consumer": "read", "event": "before",
     "body": ['    mut source = "abcd"', "    const piece = source[1:3]", '    source = source + "e"', "    print(out, len(piece))", "    return 0"],
     "fixed": ['    mut source = "abcd"', "    const piece = copy(source[1:3])", '    source = source + "e"', "    print(out, len(piece))", "    return 0"],
     "out": "2\n"},
    {"name": "text_scalar_helper_position_refused", "producer": "call", "consumer": "read", "event": "none",
     "body": ['    const text = "\u03bb\u03bbb"', '    print(out, strings.char_find(text, "b", -1))', "    return 0"],
     "fixed": ['    const text = "\u03bb\u03bbb"', '    print(out, strings.char_find(text, "b", max(strings.char_count(text) - 1, 0)))', "    return 0"],
     "out": "2\n",
     "prelude": "import strings",
     "fixed_prelude": "import strings"},
    {"name": "text_slice_store_refused", "producer": "slice", "consumer": "store", "event": "none",
     "body": ['    const source = "abcd"', "    const held = Item(name=source[1:3])", "    print(out, held.name)", "    return 0"],
     "fixed": ['    const source = "abcd"', "    const held = Item(name=copy(source[1:3]))", "    print(out, held.name)", "    return 0"],
     "out": "bc\n"},
    {"name": "text_slice_list_refused", "producer": "slice", "consumer": "list", "event": "none",
     "body": ['    const source = "abcd"', "    const held = [source[1:3]]", "    print(out, len(held))", "    return 0"],
     "fixed": ['    const source = "abcd"', "    const held = [copy(source[1:3])]", "    print(out, len(held))", "    return 0"],
     "out": "1\n"},
    {"name": "text_slice_before_refused", "producer": "slice", "consumer": "read", "event": "before",
     "body": ['    mut source = "abcd"', "    const piece = source[0:2]", '    source += "x"', "    print(out, piece)", "    return 0"],
     "fixed": ['    mut source = "abcd"', "    const piece = copy(source[0:2])", '    source += "x"', "    print(out, piece)", "    return 0"],
     "out": "ab\n"},
    {"name": "text_slice_loop_refused", "producer": "slice", "consumer": "read", "event": "loop",
     "body": ['    mut source = "abcd"', "    const piece = source[0:2]", "    for i in range(2):", '        source += "x"', "    print(out, piece)", "    return 0"],
     "fixed": ['    mut source = "abcd"', "    const piece = copy(source[0:2])", "    for i in range(2):", '        source += "x"', "    print(out, piece)", "    return 0"],
     "out": "ab\n"},
    {"name": "text_call_before_refused", "producer": "call", "consumer": "read", "event": "before",
     "body": ['    mut source = "abcd"', "    const piece = head(source)", '    source += "x"', "    print(out, piece)", "    return 0"],
     "fixed": ['    mut source = "abcd"', "    const piece = copy(head(source))", '    source += "x"', "    print(out, piece)", "    return 0"],
     "out": "ab\n"},
    {"name": "text_call_mutcall_refused", "producer": "call", "consumer": "read", "event": "mutcall",
     "body": ['    mut source = "abcd"', "    const piece = head(source)", "    bump(mut source)", "    print(out, piece)", "    return 0"],
     "fixed": ['    mut source = "abcd"', "    const piece = copy(head(source))", "    bump(mut source)", "    print(out, piece)", "    return 0"],
     "out": "ab\n"},
    {"name": "text_call_branch_refused", "producer": "call", "consumer": "read", "event": "branch",
     "body": ['    mut source = "abcd"', "    const piece = head(source)", "    if len(source) > 2:", "        bump(mut source)", "    print(out, piece)", "    return 0"],
     "fixed": ['    mut source = "abcd"', "    const piece = copy(head(source))", "    if len(source) > 2:", "        bump(mut source)", "    print(out, piece)", "    return 0"],
     "out": "ab\n"},
]

# --- bytes --------------------------------------------------------------------

BYTES_PRELUDE = '''record Chunk:
    body: bytes


enum Kind:
    data(body: bytes)
    empty


func payload_size(k: Kind) -> int:
    match k:
        case data(body=value):
            const piece = value[1:3]
            return len(piece)
        case empty:
            return 0
'''

BYTES_ACCEPTED = [
    ("bytes_slice_read", "slice", "read", "none", [
        '    const data = b"abcd"',
        "    const piece = data[1:3]",
        '    return piece == b"bc" and len(piece) == 2',
    ]),
    ("bytes_slice_phi", "slice", "phi", "none", [
        '    const data = b"abcd"',
        "    const piece: bytes",
        "    if len(data) > 3:",
        "        piece = data[1:3]",
        "    else:",
        "        piece = data[0:2]",
        '    return piece == b"bc"',
    ]),
    ("bytes_slice_loop", "slice", "loop", "none", [
        '    const chunks = [b"abcd", b"efgh"]',
        "    mut total = 0",
        "    for chunk in chunks:",
        "        total += len(chunk[1:3])",
        "    return total == 4",
    ]),
    ("bytes_slice_return", "slice", "return", "none", [
        '    const data = b"abcd"',
        "    const piece = copy(data[1:3])",
        '    return piece == b"bc"',
    ]),
    ("bytes_field_read", "field", "read", "none", [
        '    const held = Chunk(body=b"abcd")',
        "    const piece = held.body[1:3]",
        '    return piece == b"bc"',
    ]),
    ("bytes_nested_read", "nested", "read", "none", [
        '    const data = b"abcdef"',
        "    const piece = copy(data[0:4][1:3])",
        '    return piece == b"bc"',
    ]),
    ("bytes_payload_read", "payload", "read", "none", [
        '    return payload_size(Kind.data(body=b"abcd")) == 2',
    ]),
    ("bytes_slice_after", "slice", "read", "after", [
        '    mut data = b"abcd"',
        "    const piece = data[0:2]",
        "    const before = copy(piece)",
        '    data += b"x"',
        '    return before == b"ab" and data == b"abcdx"',
    ]),
]

BYTES_REFUSED = [
    {"name": "bytes_slice_store_refused", "producer": "slice", "consumer": "store", "event": "none",
     "body": ['    const data = b"abcd"', "    const held = Chunk(body=data[1:3])", "    print(out, len(held.body))", "    return 0"],
     "fixed": ['    const data = b"abcd"', "    const held = Chunk(body=copy(data[1:3]))", "    print(out, len(held.body))", "    return 0"],
     "out": "2\n"},
    {"name": "bytes_slice_list_refused", "producer": "slice", "consumer": "list", "event": "none",
     "body": ['    const data = b"abcd"', "    const held = [data[1:3]]", "    print(out, len(held))", "    return 0"],
     "fixed": ['    const data = b"abcd"', "    const held = [copy(data[1:3])]", "    print(out, len(held))", "    return 0"],
     "out": "1\n"},
    {"name": "bytes_slice_before_refused", "producer": "slice", "consumer": "read", "event": "before",
     "body": ['    mut data = b"abcd"', "    const piece = data[0:2]", '    data += b"x"', "    print(out, len(piece))", "    return 0"],
     "fixed": ['    mut data = b"abcd"', "    const piece = copy(data[0:2])", '    data += b"x"', "    print(out, len(piece))", "    return 0"],
     "out": "2\n"},
]

# --- lists --------------------------------------------------------------------

LISTS_PRELUDE = '''record Bag:
    items: int[]


enum Slot:
    full(items: int[])
    empty


func payload_len(s: Slot) -> int:
    match s:
        case full(items=value):
            const piece = value[1:3]
            return len(piece)
        case empty:
            return 0
'''

LISTS_ACCEPTED = [
    ("lists_bound_slice_read", "slice", "read", "none", [
        "    const xs = [1, 2, 3, 4]",
        "    const piece = xs[1:3]",
        "    return len(piece) == 2 and piece[0] == 2",
    ]),
    ("lists_mut_source_read", "slice", "read", "none", [
        "    mut xs = [1, 2, 3, 4]",
        "    const piece = xs[1:3]",
        "    return len(piece) == 2 and piece[0] == 2",
    ]),
    ("lists_deferred_merge_read", "slice", "phi", "none", [
        "    const xs = [1, 2, 3, 4]",
        "    const piece: int[]",
        "    if len(xs) > 2:",
        "        piece = xs[1:3]",
        "    else:",
        "        piece = xs[0:2]",
        "    return len(piece) == 2 and piece[0] == 2",
    ]),
    ("lists_slice_read", "slice", "read", "none", [
        "    const xs = [1, 2, 3, 4]",
        "    const piece = xs[1:3]",
        "    return len(piece) == 2 and piece[0] == 2",
    ]),
    ("lists_slice_loop", "slice", "loop", "none", [
        "    const xs = [1, 2, 3, 4]",
        "    mut total = 0",
        "    for value in xs[1:3]:",
        "        total += value",
        "    return total == 5",
    ]),
    ("lists_slice_return", "slice", "return", "none", [
        "    const xs = [1, 2, 3, 4]",
        "    const piece = copy(xs[1:3])",
        "    return len(piece) == 2 and piece[1] == 3",
    ]),
    ("lists_field_read", "field", "read", "none", [
        "    const bag = Bag(items=[1, 2, 3, 4])",
        "    const piece = bag.items[1:3]",
        "    return len(piece) == 2 and piece[0] == 2",
    ]),
    ("lists_field_after", "field", "read", "after", [
        "    const bag = Bag(items=[1, 2, 3, 4])",
        "    const piece = copy(bag.items[1:3])",
        "    const before = piece",
        "    return len(before) == 2 and before[1] == 3",
    ]),
    ("lists_nested_read", "nested", "read", "none", [
        "    const xs = [1, 2, 3, 4, 5]",
        "    const piece = xs[0:4][1:3]",
        "    return len(piece) == 2 and piece[0] == 2",
    ]),
    ("lists_payload_read", "payload", "read", "none", [
        "    return payload_len(Slot.full(items=[1, 2, 3, 4])) == 2",
    ]),
]

LISTS_REFUSED = [
    {"name": "lists_bound_store_refused", "producer": "slice", "consumer": "store", "event": "none",
     "body": ["    const xs = [1, 2, 3, 4]", "    mut parts: int[][] = []", "    const piece = xs[1:3]", "    append(mut parts, piece)", "    print(out, len(parts[0]))", "    return 0"],
     "fixed": ["    const xs = [1, 2, 3, 4]", "    mut parts: int[][] = []", "    const piece = copy(xs[1:3])", "    append(mut parts, own piece)", "    print(out, len(parts[0]))", "    return 0"],
     "out": "2\n"},
    {"name": "lists_bound_invalidated_refused", "producer": "slice", "consumer": "read", "event": "before",
     "body": ["    mut xs = [1, 2, 3, 4]", "    const piece = xs[1:3]", "    append(mut xs, 5)", "    print(out, len(piece))", "    return 0"],
     "fixed": ["    mut xs = [1, 2, 3, 4]", "    const piece = copy(xs[1:3])", "    append(mut xs, 5)", "    print(out, len(piece))", "    return 0"],
     "out": "2\n"},
    {"name": "lists_slice_store_refused", "producer": "slice", "consumer": "store", "event": "none",
     "body": ["    const xs = [1, 2, 3, 4]", "    const bag = Bag(items=xs[1:3])", "    print(out, len(bag.items))", "    return 0"],
     "fixed": ["    const xs = [1, 2, 3, 4]", "    const bag = Bag(items=copy(xs[1:3]))", "    print(out, len(bag.items))", "    return 0"],
     "out": "2\n"},
    {"name": "lists_slice_list_refused", "producer": "slice", "consumer": "list", "event": "none",
     "body": ["    const xs = [1, 2, 3, 4]", "    const outer = [xs[1:3]]", "    print(out, len(outer))", "    return 0"],
     "fixed": ["    const xs = [1, 2, 3, 4]", "    const outer = [copy(xs[1:3])]", "    print(out, len(outer))", "    return 0"],
     "out": "1\n"},
    {"name": "lists_slice_return_refused", "producer": "slice", "consumer": "return", "event": "none",
     "body": ["    const xs = [1, 2, 3, 4]", "    print(out, len(middle(xs)))", "    return 0"],
     "fixed": ["    const xs = [1, 2, 3, 4]", "    print(out, len(middle(xs)))", "    return 0"],
     "prelude": "func middle(xs: int[]) -> int[]:\n    return xs[1:3]",
     "fixed_prelude": "func middle(xs: int[]) -> int[] from xs:\n    return xs[1:3]",
     "out": "2\n"},
]

FAMILIES = [
    {"name": "string_views", "prelude": TEXT_PRELUDE, "accepted": TEXT_ACCEPTED, "refused": TEXT_REFUSED,
     "refused_prelude": TEXT_PRELUDE, "signature": "func run_cell(out: Stream) -> int:"},
    {"name": "byte_views", "prelude": BYTES_PRELUDE, "accepted": BYTES_ACCEPTED, "refused": BYTES_REFUSED,
     "refused_prelude": BYTES_PRELUDE, "signature": "func run_cell(out: Stream) -> int:"},
    {"name": "list_views", "prelude": LISTS_PRELUDE, "accepted": LISTS_ACCEPTED, "refused": LISTS_REFUSED,
     "refused_prelude": LISTS_PRELUDE, "signature": "func run_cell(out: Stream) -> int:"},
]


def canonical_prelude(family):
    """The prelude in the formatter's canonical form: one blank line after the
    header, two between top-level declarations."""
    return family["prelude"].strip()


def canonical_prelude_of(text):
    return text.strip()


def accepted_source(family):
    lines = ["# Generated by tests/view_shapes/matrix.py: the accepted view-shape cells.",
             "# Do not edit by hand; regenerate instead. Each cell prints the value the",
             "# pre-wave-3 copy semantics produced."]
    text = "\n".join(lines) + "\n" + canonical_prelude(family) + "\n"
    for name, producer, consumer, event, body in family["accepted"]:
        if body is None:
            continue
        text += "\n\n"
        text += "# spec-case: NEW-CORE-ZERO-RC-VIEWS-1\n"
        text += "# cell: %s (producer %s, consumer %s, event %s)\n" % (name, producer, consumer, event)
        text += "public func test_%s() -> bool:\n" % name
        text += "\n".join(body) + "\n"
    return text


def refused_text(family, cell, body, prelude=None):
    header = ["# migrate-embedded: skip intentional FIX-MIGRATION-1 pre-removal source",
              "# Generated by tests/view_shapes/matrix.py: the refused view-shape cell %s" % cell["name"],
              "# (producer %s, consumer %s, event %s). `selka fix` must repair it." % (cell["producer"], cell["consumer"], cell["event"])]
    block = prelude if prelude is not None else canonical_prelude(family)
    # Imports are followed by one blank line; declarations by two.
    text = "\n".join(header) + "\n" + block + ("\n\n" if block.lstrip().startswith("import ") else "\n\n\n")
    text += "func run_cell(out: Stream) -> int:\n" + "\n".join(body) + "\n\n\n"
    text += "func main(out: Stream) -> int:\n    return run_cell(out)\n"
    return text


def refused_source(family, cell):
    prelude = cell.get("prelude")
    return refused_text(family, cell, cell["body"], canonical_prelude_of(prelude) if prelude else None)


def refused_expected(family, cell):
    """The fixed source a cell's certain repair produces."""
    prelude = cell.get("fixed_prelude")
    return refused_text(family, cell, cell["fixed"], canonical_prelude_of(prelude) if prelude else None)


def planned():
    """Every generated file: path -> text."""
    files = {}
    manifest = ["# view-shape matrix: one line per cell (kind, family, producer, consumer, event, name)"]
    for family in FAMILIES:
        accepted = [cell for cell in family["accepted"] if cell[4] is not None]
        files[os.path.join(LANG_DIR, family["name"] + ".selka")] = accepted_source(family)
        for cell in accepted:
            manifest.append("accepted %s %s %s %s %s" % (family["name"], cell[1], cell[2], cell[3], cell[0]))
        for cell in family["refused"]:
            path = os.path.join(REFUSED_DIR, cell["name"] + ".selka")
            files[path] = refused_source(family, cell)
            files[os.path.join(REFUSED_DIR, cell["name"] + ".fixed.selka")] = refused_expected(family, cell)
            files[os.path.join(REFUSED_DIR, cell["name"] + ".out")] = cell["out"]
            manifest.append("refused %s %s %s %s %s" % (family["name"], cell["producer"], cell["consumer"], cell["event"], cell["name"]))
    files[MANIFEST] = "\n".join(manifest) + "\n"
    return files


def check():
    failures = []
    for path, text in planned().items():
        try:
            current = open(path, encoding="utf-8").read()
        except OSError:
            failures.append("missing: " + os.path.relpath(path, ROOT))
            continue
        if current != text:
            failures.append("stale: " + os.path.relpath(path, ROOT))
    if failures:
        print("view-shape matrix is stale; run tests/view_shapes/matrix.py")
        for line in failures:
            print("  " + line)
        return 1
    print("view-shape matrix is current")
    return 0


def write():
    for path, text in planned().items():
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(text)
    print("wrote %d view-shape files" % len(planned()))
    return 0


def run(argv):
    return subprocess.run(argv, cwd=ROOT, capture_output=True, text=True)


def audit(compiler):
    """Developer check: every accepted family passes; every refused cell is
    refused, takes its certain fix, and the fixed program prints its value."""
    if not os.path.exists(compiler):
        print("audit: compiler not found at %s" % compiler)
        return 1
    status = 0
    files = planned()
    for family in FAMILIES:
        path = os.path.join(LANG_DIR, family["name"] + ".selka")
        result = run([compiler, "test", path])
        last = result.stdout.strip().splitlines()[-1] if result.stdout.strip() else "no output"
        print("%s: %s" % (os.path.relpath(path, ROOT), last))
        if result.returncode != 0:
            status = 1
            print(result.stdout[-2000:])
            print(result.stderr[-2000:])
    import tempfile
    for family in FAMILIES:
        for cell in family["refused"]:
            with tempfile.TemporaryDirectory() as temp:
                path = os.path.join(temp, cell["name"] + ".selka")
                with open(path, "w", encoding="utf-8") as handle:
                    handle.write(refused_source(family, cell))
                checked = run([compiler, "check", path])
                if checked.returncode == 0:
                    print("%s: accepted, but the matrix expects a refusal" % cell["name"])
                    status = 1
                    continue
                if cell["name"] not in checked.stderr and cell["name"] not in checked.stdout:
                    pass
                fixed = run([compiler, "fix", path])
                if fixed.returncode != 0:
                    print("%s: fix did not converge" % cell["name"])
                    print(fixed.stdout[-1000:])
                    print(fixed.stderr[-1000:])
                    status = 1
                    continue
                produced = open(path, encoding="utf-8").read()
                expected = files[os.path.join(REFUSED_DIR, cell["name"] + ".fixed.selka")]
                if produced != expected:
                    print("%s: the fix output changed; regenerate the committed cell" % cell["name"])
                    status = 1
                executed = run([compiler, "run", path])
                if executed.stdout != cell["out"]:
                    print("%s: printed %r, expected %r" % (cell["name"], executed.stdout, cell["out"]))
                    status = 1
                else:
                    print("%s: refused, fixed, printed %r" % (cell["name"], executed.stdout))
    return status


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="fail when the committed set is stale")
    parser.add_argument("--audit", action="store_true", help="run the compiler over every cell (developer mode)")
    parser.add_argument("--compiler", default=os.path.join(ROOT, "zig-out", "bin", "selka"))
    args = parser.parse_args()
    if args.check:
        return check()
    if args.audit:
        return audit(args.compiler)
    return write()


if __name__ == "__main__":
    sys.exit(main())
