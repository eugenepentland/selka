#!/usr/bin/env python3
"""S5-C3: delete the retired arena tests from tests/lang (plan S5-D3).

The set is the one conformance excluded since S1 (experiments/new-core-s1-20261005/
conformance.py): the five arena files, and every test whose qualified name
`module::test` matches `*arena*`, in tests/lang and tests/value_semantics. A deleted
test takes its leading comment block (including its `# spec:` / `# spec-case:` lines)
with it. Writes the list of deleted tests and the spec tags they carried to
arena-tests-deleted.json beside this script.

DEFERRED files stay: each holds the only primary `# spec:` tag of an ARENA-MANAGED
bullet that still has `spec-case` tags in src/arena_managed_test.zig (lane C1) or
test/integration.zig (lane C2), so the bullet and its last tests go together in S5-D.
They pass on the new core, where `with arena():` is a plain block.

usage: retire_arena_tests.py [--dry-run]
"""
import fnmatch, json, re, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
FILES = ["arena_class_escape", "rc_arena_values"]
DEFERRED = ["arena_managed", "arena_scopes", "arena_regions"]
DIRS = ["tests/lang", "tests/value_semantics"]
TEST = re.compile(r"^(?:public )?def (test_\w+)\(")
TAG = re.compile(r"^#\s*(spec|spec-case):\s*(\S+)")


def blocks(lines):
    """Yield (start, end, name) for each top-level public test, start including its comment block."""
    starts = [i for i, line in enumerate(lines) if TEST.match(line)]
    for i in starts:
        start = i
        while start > 0 and lines[start - 1].startswith("#"):
            start -= 1
        end = i + 1
        while end < len(lines) and (lines[end].strip() == "" or lines[end][0] in " \t"):
            end += 1
        # Trailing blank lines belong to the gap, not the test; keep one gap.
        while end > i + 1 and lines[end - 1].strip() == "":
            end -= 1
        yield start, end, TEST.match(lines[i]).group(1)


def drop_calls(lines, names):
    """Remove a file's own calls of deleted tests (from its `main`): `assert NAME()`,
    `out.print(NAME())`, a list element `NAME(),`, and `if not NAME():` with its `return`."""
    kept, skip = [], False
    for line in lines:
        if skip:
            skip = False
            if line.strip().startswith("return"):
                continue
        body = line.strip()
        called = re.fullmatch(r"(?:assert |out\.print\()?(test_\w+)\(\)\)?,?", body)
        guarded = re.fullmatch(r"if not (test_\w+)\(\):", body)
        if called and called.group(1) in names:
            continue
        if guarded and guarded.group(1) in names:
            skip = True
            continue
        kept.append(line)
    return kept


def tags(lines):
    return [m.groups() for m in (TAG.match(line) for line in lines) if m]


def main():
    dry = "--dry-run" in sys.argv
    deleted = []
    for path in sorted(p for d in DIRS for p in (ROOT / d).glob("*.my")):
        module = path.stem
        if module in DEFERRED:
            continue
        lines = path.read_text().split("\n")
        if module in FILES or fnmatch.fnmatchcase(module + "::", "*arena*"):
            for _, _, name in blocks(lines):
                deleted.append({"file": path.relative_to(ROOT).as_posix(), "test": f"{module}::{name}", "tags": [], "whole_file": True})
            deleted[-1]["tags"] = tags(lines)
            if not dry:
                path.unlink()
            continue
        doomed = [(s, e, n) for s, e, n in blocks(lines) if fnmatch.fnmatchcase(f"{module}::{n}", "*arena*")]
        if not doomed:
            continue
        keep = []
        cursor = 0
        for start, end, name in doomed:
            deleted.append({"file": path.relative_to(ROOT).as_posix(), "test": f"{module}::{name}", "tags": tags(lines[start:end]), "whole_file": False})
            keep.extend(lines[cursor:start])
            cursor = end
            # Drop the blank gap after the removed block.
            while cursor < len(lines) and lines[cursor].strip() == "" and cursor < len(lines) - 1:
                cursor += 1
        keep.extend(lines[cursor:])
        keep = drop_calls(keep, {name for _, _, name in doomed})
        text = "\n".join(keep)
        text = re.sub(r"\n{4,}", "\n\n\n", text).rstrip("\n") + "\n"
        if not dry:
            path.write_text(text)
    out = Path(__file__).with_name("arena-tests-deleted.json")
    out.write_text(json.dumps({"count": len(deleted), "tests": deleted}, indent=1) + "\n")
    print(len(deleted), "tests;", len({d["file"] for d in deleted}), "files")


if __name__ == "__main__":
    main()
