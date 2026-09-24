#!/usr/bin/env python3
"""Write one content manifest per list of declared test inputs.

    python3 tests/input_manifest.py OUT_DIR --list NAME ENTRY... [--list NAME ENTRY...]
    python3 tests/input_manifest.py --self-test

`zig build` runs this on every invocation, before any cached test step, from the
lists in `build_test_inputs.zig`. For each list it writes `OUT_DIR/NAME.txt`: one
`sha256  path` line per file the entries name, sorted. A cached test step
declares that file as its input, so the step re-runs exactly when a file it
reads is edited, added, removed or renamed, and keeps its verdict otherwise.
The walk happens here, at make time, because this Zig version does not re-run
the configure phase when a directory gains a file (`dependOnDirectory` is not
implemented), so a list expanded in `build.zig` would never see a new fixture.

Entry syntax, relative to the working directory:
- `dir/` — every file under `dir`, recursively;
- `dir/*.ext` — the files directly in `dir` whose names end in `.ext`;
- `dir/**/*.ext` — every file under `dir`, recursively, ending in `.ext`;
- anything else — one file, which must exist.
Hidden entries, `__pycache__` and `*.pyc` are never inputs.
"""
from __future__ import annotations

import hashlib
import os
from pathlib import Path
import sys
import tempfile


def expand(entry: str) -> list[str]:
    """The repository files one entry names, sorted."""
    if entry.endswith("/"):
        base, suffix, recursive = entry[:-1], "", True
    elif "/**/*" in entry:
        base, suffix = entry.split("/**/*", 1)
        recursive = True
    elif "/*" in entry:
        base, suffix = entry.split("/*", 1)
        recursive = False
    else:
        if not os.path.isfile(entry):
            raise SystemExit("input_manifest: declared test input {} does not exist; update build_test_inputs.zig".format(entry))
        return [entry]
    if not os.path.isdir(base):
        raise SystemExit("input_manifest: declared test input {} names no directory; update build_test_inputs.zig".format(entry))
    found = []
    for directory, dirs, files in os.walk(base):
        dirs[:] = sorted(d for d in dirs if not d.startswith(".") and d != "__pycache__") if recursive else []
        for name in files:
            if name.startswith(".") or name.endswith(".pyc") or not name.endswith(suffix):
                continue
            found.append(os.path.join(directory, name))
    return sorted(found)


def digest(path: str, memo: dict[str, str]) -> str:
    """The SHA-256 of one file's bytes, computed once per run."""
    if path not in memo:
        with open(path, "rb") as handle:
            memo[path] = hashlib.sha256(handle.read()).hexdigest()
    return memo[path]


def manifest(entries: list[str], memo: dict[str, str]) -> str:
    """The manifest text for one list of entries."""
    paths = sorted({path for entry in entries for path in expand(entry)})
    return "".join("{}  {}\n".format(digest(path, memo), path) for path in paths)


def parse(argv: list[str]) -> tuple[str, dict[str, list[str]]]:
    """OUT_DIR and the named entry lists from the command line."""
    if len(argv) < 1:
        raise SystemExit(__doc__)
    out, lists, current = argv[0], {}, None
    index = 1
    while index < len(argv):
        if argv[index] == "--list":
            current = argv[index + 1]
            lists[current] = []
            index += 2
            continue
        if current is None:
            raise SystemExit("input_manifest: an entry before any --list")
        lists[current].append(argv[index])
        index += 1
    return out, lists


def write(out: str, lists: dict[str, list[str]]) -> None:
    """Write every manifest, leaving an unchanged one byte-identical."""
    os.makedirs(out, exist_ok=True)
    memo: dict[str, str] = {}
    for name, entries in lists.items():
        Path(out, name + ".txt").write_text(manifest(entries, memo))


def self_test() -> int:
    """Pin the entry syntax and the manifest's response to edits and new files."""
    previous = os.getcwd()
    with tempfile.TemporaryDirectory(prefix="input-manifest-") as root:
        os.chdir(root)
        try:
            for path in ("a/x.md", "a/deep/y.md", "a/deep/z.txt", "a/__pycache__/m.pyc", "a/.hidden", "b.txt"):
                os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
                Path(path).write_text(path)
            assert expand("a/") == ["a/deep/y.md", "a/deep/z.txt", "a/x.md"], expand("a/")
            assert expand("a/*.md") == ["a/x.md"]
            assert expand("a/**/*.md") == ["a/deep/y.md", "a/x.md"]
            assert expand("b.txt") == ["b.txt"]
            first = manifest(["a/**/*.md", "b.txt"], {})
            Path("a/deep/new.md").write_text("new")
            added = manifest(["a/**/*.md", "b.txt"], {})
            assert added != first and "a/deep/new.md" in added
            Path("a/x.md").write_text("edited")
            assert manifest(["a/**/*.md", "b.txt"], {}) != added
            assert manifest(["a/**/*.md"], {}) == manifest(["a/**/*.md"], {})
            try:
                expand("missing.txt")
            except SystemExit:
                pass
            else:
                raise AssertionError("a missing file entry must fail")
        finally:
            os.chdir(previous)
    print("input manifest self-test: passed")
    return 0


def main(argv: list[str]) -> int:
    if argv[:1] == ["--self-test"]:
        return self_test()
    out, lists = parse(argv)
    write(out, lists)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
