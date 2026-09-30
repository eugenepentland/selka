#!/usr/bin/env python3
"""Differential edit oracle for per-symbol invalidation (MODULE-SYMBOL-CUTOFF-1..3).

Applies a scripted sequence of edits to a copy of a mylang project (by default
the Lox port) and, after every edit, checks that the incremental module-by-module
`mylang build main.my --project` executable is byte-identical to a from-scratch
`mylang build main.my --project --whole-program` one built in a fresh cache. It
records each incremental build's `module_build.compiled` count and wall time.

    oracle.py --compiler PATH --source DIR --work DIR [--gc-runtime] [--json OUT]

Exit status 0 when every edit matched the oracle, 1 otherwise.
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import time

# (name, kind of change, file, old text, new text): applied in order, each
# exactly once, cumulatively. `None` as old text appends `new` to the file.
EDITS = [
    ("private-add", "add a private function to the leaf", "value.my", None,
     "\ndef probe_edit() -> int:\n    return 0\n"),
    ("private-body", "body of a private function nobody reaches", "value.my",
     "def probe_edit() -> int:\n    return 0\n", "def probe_edit() -> int:\n    return 11\n"),
    ("private-mid-add", "add a private function mid-file", "value.my",
     "\n\n# Lox equality:", "\n\ndef probe_mid(n: int) -> int:\n    return n + 1\n\n\n# Lox equality:"),
    ("private-mid-body", "mid-file private body, same line count", "value.my",
     "    return n + 1\n", "    return n + 1000\n"),
    ("private-mid-lines", "mid-file private body, one line longer", "value.my",
     "    return n + 1000\n", "    m = n + 1000\n    return m\n"),
    ("private-helper-add", "public body now calls a new private helper", "value.my",
     "        return text[0:len(text) - 2]\n",
     "        return trim_tail(text)\n"),
    ("private-helper-add-def", "(the helper itself)", "value.my", None,
     "\ndef trim_tail(text: bytes) -> bytes:\n    return text[0:len(text) - 2]\n"),
    ("private-helper-body", "body of a private helper a public function reaches", "value.my",
     "    return text[0:len(text) - 2]\n", "    return text[0:len(text) - 1 - 1]\n"),
    ("public-body", "public non-inlined body (format_number)", "value.my",
     '    if text.endswith(b".0"):\n', '    if text.endswith(b".0") and len(text) > 1:\n'),
    ("public-inlined", "small public function inlined into callers (values_equal)", "value.my",
     "                case Value.boolean(right):\n                    return left == right\n",
     "                case Value.boolean(right):\n                    return not (left != right)\n"),
    ("signature", "signature change (table.capacity gains a defaulted parameter)", "table.my",
     "public def capacity(t: Table) -> int:\n    return len(t.entries)\n",
     "public def capacity(t: Table, extra: int = 0) -> int:\n    return len(t.entries) + extra\n"),
    ("public-add", "add a public function", "value.my", None,
     "\npublic def probe_public(n: int) -> int:\n    return n + 1\n"),
    ("public-remove", "remove that public function", "value.my",
     "\npublic def probe_public(n: int) -> int:\n    return n + 1\n", ""),
    ("record-field", "record field added (chunk.Chunk)", "chunk.my",
     "    constants: list[value.Value]\n", "    constants: list[value.Value]\n    spare: int = 0\n"),
    ("constant", "public constant changed (chunk.OP_METHOD)", "chunk.my",
     "public const OP_METHOD: int = 36\n", "public const OP_METHOD: int = 40\n"),
    ("rc-facts", "function starts allocating (table.capacity)", "table.my",
     "    return len(t.entries) + extra\n",
     "    return len(str(len(t.entries))) * 0 + len(t.entries) + extra\n"),
    ("table-private-reached", "private helper its callers reach (table.find_entry)", "table.my",
     "            if tombstone == -1:\n                tombstone = index\n",
     "            if tombstone < 0:\n                tombstone = index\n"),
    ("private-starts-allocating", "a reached private helper starts allocating (table.is_tombstone)", "table.my",
     "def is_tombstone(entry: Entry) -> bool:\n",
     "def is_tombstone(entry: Entry) -> bool:\n    if len(str(entry.key)) == 0:\n        return True\n"),
    ("value-add", "add a public function taken as a value", "value.my", None,
     "\npublic def probe_key(n: int) -> int:\n    values: list[int] = [n]\n    return values[0] % 3\n"),
    ("value-use", "entry takes it as a sort key", "main.my",
     "    if len(paths) != 1:\n",
     "    _ = sorted([2, 1], key=value.probe_key)\n    if len(paths) != 1:\n"),
    ("value-use-import", "(the entry imports value)", "main.my",
     "import driver\n", "import driver\nimport value\n"),
    ("value-body", "body of the function taken as a value", "value.my",
     "    return values[0] % 3\n", "    return values[0] % 5\n"),
    # Interface-level cutoff (MODULE-INTERFACE-CUTOFF-1..3).
    ("hazard-add", "add public value.count, a name other modules use for locals and fields", "value.my", None,
     "\npublic def count(n: int) -> int:\n    values: list[int] = [n]\n    return len(values)\n"),
    ("unused-public-add", "add a public function nobody calls (table.probe_unused)", "table.my", None,
     "\npublic def probe_unused(n: int) -> int:\n    values: list[int] = [n]\n    return len(values)\n"),
    ("unused-public-remove", "remove that public function", "table.my",
     "\npublic def probe_unused(n: int) -> int:\n    values: list[int] = [n]\n    return len(values)\n", ""),
    ("unused-signature", "signature change of a public function nobody calls (value.count)", "value.my",
     "public def count(n: int) -> int:\n    values: list[int] = [n]\n",
     "public def count(n: int, m: int = 0) -> int:\n    values: list[int] = [n + m]\n"),
    ("field-rename", "rename a record field nobody reads (chunk.Chunk.spare)", "chunk.my",
     "    spare: int = 0\n", "    spare_slot: int = 0\n"),
    ("constant-unused-add", "add a public constant nobody reads", "chunk.my", None,
     "\npublic const PROBE_LIMIT: int = 1\n"),
    ("constant-unused", "change that constant", "chunk.my",
     "public const PROBE_LIMIT: int = 1\n", "public const PROBE_LIMIT: int = 2\n"),
    ("template-add", "add a generic template to value", "value.my", None,
     "\npublic def probe_first[T: integer](items: list[T]) -> T:\n    return items[0]\n"),
    ("template-use", "table.new_table instantiates it", "table.my",
     "    return Table(entries=[], count=0)\n", "    return Table(entries=[], count=value.probe_first([0]))\n"),
    ("template-body", "generic template body edit", "value.my",
     "    return items[0]\n", "    return items[len(items) - 1]\n"),
    ("facade-add", "a facade module re-exporting value.is_falsey", "facade.my", None,
     "module facade\nimport value\nexport value.is_falsey\n"),
    ("facade-use-import", "(main imports it)", "main.my", "import value\n", "import value\nimport facade\n"),
    ("facade-use", "main calls through the facade", "main.my",
     "    if len(paths) != 1:\n", "    _ = facade.is_falsey(value.Value.nil)\n    if len(paths) != 1:\n"),
    ("facade-chain", "the facade re-exports one more name", "facade.my", None, "export value.values_equal\n"),
    ("facade-target-body", "body of the re-exported inlined function (is_falsey)", "value.my",
     "            return not flag\n", "            return flag == False\n"),
    ("noop", "no edit at all", None, None, None),
]

# Edits whose file text is only half of one logical change: the build runs
# after the second half.
PAIRED = {"private-helper-add", "value-use", "template-add", "facade-add", "facade-use-import"}


def apply(project, edit):
    name, _, path, old, new = edit
    if path is None:
        return
    full = os.path.join(project, path)
    text = ""
    if old is not None or os.path.exists(full):
        with open(full) as handle:
            text = handle.read()
    if old is None:
        text += new
    else:
        if text.count(old) != 1:
            raise SystemExit(f"edit {name}: expected exactly one match in {path}")
        text = text.replace(old, new)
    with open(full, "w") as handle:
        handle.write(text)


def build(compiler, project, output, cache, extra):
    args = [compiler, "build", "main.my", "--project", "-o", output, f"--cache-dir={cache}", "--report"] + extra
    start = time.monotonic()
    done = subprocess.run(args, cwd=project, capture_output=True, text=True)
    elapsed = time.monotonic() - start
    match = re.search(r'"module_build":(\{[^}]*\})', done.stdout)
    counts = json.loads(match.group(1)) if match else None
    return done, elapsed, counts


def same(left, right):
    with open(left, "rb") as one, open(right, "rb") as two:
        return one.read() == two.read()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--compiler", required=True)
    parser.add_argument("--source", required=True)
    parser.add_argument("--work", required=True)
    parser.add_argument("--gc-runtime", action="store_true")
    parser.add_argument("--json")
    options = parser.parse_args()
    compiler = os.path.abspath(options.compiler)
    work = os.path.abspath(options.work)
    shutil.rmtree(work, ignore_errors=True)
    project = os.path.join(work, "project")
    shutil.copytree(options.source, project, ignore=shutil.ignore_patterns(".mylang-cache"))
    extra = ["--gc-runtime"] if options.gc_runtime else []
    cache = os.path.join(work, "cache")
    rows = []
    ok = True
    steps = [("cold", "first build", None, None, None)] + EDITS
    for edit in steps:
        apply(project, edit)
        if edit[0] in PAIRED:
            continue
        incremental, elapsed, counts = build(compiler, project, "incremental", cache, extra)
        fresh = os.path.join(work, "whole-cache")
        shutil.rmtree(fresh, ignore_errors=True)
        whole, _, _ = build(compiler, project, "whole", fresh, extra + ["--whole-program"])
        shutil.rmtree(fresh, ignore_errors=True)
        built = incremental.returncode == 0 and whole.returncode == 0
        matched = built and same(os.path.join(project, "incremental"), os.path.join(project, "whole"))
        ok = ok and matched
        row = {
            "edit": edit[0],
            "kind": edit[1],
            "matched": matched,
            "compiled": counts["compiled"] if counts else None,
            "modules": counts["modules"] if counts else None,
            "seconds": round(elapsed, 3),
        }
        if not built:
            row["error"] = (incremental.stderr + whole.stderr)[-2000:]
        rows.append(row)
        print(json.dumps(row), flush=True)
        if not built:
            break
    if options.json:
        with open(options.json, "w") as handle:
            json.dump({"compiler": compiler, "gc_runtime": options.gc_runtime, "rows": rows, "ok": ok}, handle, indent=1)
    print("ALL MATCHED" if ok else "MISMATCH", flush=True)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
