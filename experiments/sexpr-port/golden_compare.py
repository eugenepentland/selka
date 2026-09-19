#!/usr/bin/env python3
"""Byte-for-byte golden comparison: mylang sexpr printer vs the real Zig printer.

For every entry in ``experiments/sexpr-port/golden/manifest.tsv`` this script
runs, from the repository root::

    ./zig-out/bin/mylang run experiments/sexpr-port/main.my -- <input> --render

and compares the captured stdout against ``golden/<name>.txt`` byte for byte.
Each mismatch reports the first differing line and column (1-based) plus a few
lines of unified context; the run ends with a pass/fail summary and exits
non-zero if anything differs.

Trailing-newline contract (important): ``main.my`` prints through
``out.print``, which appends exactly one '\\n' itself. The Zig printer does not.
So this script strips EXACTLY ONE trailing newline from the captured mylang
stdout before diffing, and nothing else. A golden that ends in a newline would
therefore not be comparable, which is why the generator writes the printer's
bytes verbatim (no trailing newline).

This script NEVER writes goldens. ``--update`` is accepted for compatibility
and prints that reminder; regenerate with::

    bash experiments/sexpr-port/golden/generate_zig_goldens.sh

Environment:
    EDA_ROOT   sibling Zig checkout used to relocate out-of-repo input paths
               (default: /home/epentland/ai/canopy/eda)
"""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO_ROOT = HERE.parent.parent
DEFAULT_EDA_ROOT = Path("/home/epentland/ai/canopy/eda")

MYLANG = REPO_ROOT / "zig-out" / "bin" / "mylang"
MAIN = "experiments/sexpr-port/main.my"
GOLDEN_DIR = HERE / "golden"
MANIFEST = GOLDEN_DIR / "manifest.tsv"

CONTEXT_LINES = 2
MAX_CONTEXT_WIDTH = 200


def resolve_input(raw: str, eda_root: Path) -> Path:
    """Resolve a manifest path: repo-relative, or absolute (EDA_ROOT-relocatable)."""
    p = Path(raw)
    if not p.is_absolute():
        return REPO_ROOT / p
    if p.exists():
        return p
    # A golden generated on another machine still compares if EDA_ROOT moved.
    try:
        rel = p.relative_to(DEFAULT_EDA_ROOT)
    except ValueError:
        return p
    candidate = eda_root / rel
    return candidate if candidate.exists() else p


def load_manifest(path: Path) -> list[tuple[str, str]]:
    """Read ``name<TAB>path`` lines, ignoring blanks and '#' comments."""
    entries: list[tuple[str, str]] = []
    for lineno, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = line.rstrip("\n")
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) != 2 or not parts[0] or not parts[1]:
            raise SystemExit(f"{path}:{lineno}: expected 'name<TAB>path', got {line!r}")
        entries.append((parts[0], parts[1]))
    return entries


def strip_one_trailing_newline(data: bytes) -> bytes:
    """Drop exactly one trailing '\\n' (main.my's out.print adds it)."""
    if data.endswith(b"\n"):
        return data[:-1]
    return data


def first_difference(golden: bytes, actual: bytes):
    """Return (line_index, byte_column, golden_line, actual_line) or None.

    Lines are 0-based here; the display layer converts to 1-based. ``None`` for a
    side means that side has no such line (one output is shorter).
    """
    g = golden.split(b"\n")
    a = actual.split(b"\n")
    for i in range(max(len(g), len(a))):
        gl = g[i] if i < len(g) else None
        al = a[i] if i < len(a) else None
        if gl == al:
            continue
        if gl is None or al is None:
            return i, 0, gl, al
        col = 0
        limit = min(len(gl), len(al))
        while col < limit and gl[col] == al[col]:
            col += 1
        return i, col, gl, al
    return None


def _decode(data: bytes) -> str:
    return data.decode("utf-8", "replace")


def _left_truncated(line: bytes | None) -> str:
    if line is None:
        return "<no such line>"
    text = _decode(line)
    if len(text) > MAX_CONTEXT_WIDTH:
        return text[:MAX_CONTEXT_WIDTH] + "..."
    return text


def _centered_snippet(line: bytes | None, col: int) -> tuple[str, int]:
    """Return (snippet_text, caret_offset) around byte column ``col``."""
    if line is None:
        return "<no such line>", 0
    lo = max(0, col - 40)
    hi = min(len(line), col + 80)
    prefix = "..." if lo > 0 else ""
    suffix = "..." if hi < len(line) else ""
    caret_offset = len(prefix) + len(_decode(line[lo:col]))
    return prefix + _decode(line[lo:hi]) + suffix, caret_offset


def report_mismatch(name: str, golden: bytes, actual: bytes) -> None:
    """Print the first differing line/column with a little unified context."""
    diff = first_difference(golden, actual)
    if diff is None:
        return
    line_idx, col, g_line, a_line = diff
    print(f"    first difference: line {line_idx + 1}, column {col + 1} (1-based)")

    g_lines = golden.split(b"\n")
    a_lines = actual.split(b"\n")
    total = max(len(g_lines), len(a_lines))
    start = max(0, line_idx - CONTEXT_LINES)
    end = min(total, line_idx + CONTEXT_LINES + 1)

    for j in range(start, end):
        gl = g_lines[j] if j < len(g_lines) else None
        al = a_lines[j] if j < len(a_lines) else None
        if j == line_idx:
            for sign, line in (("-", gl), ("+", al)):
                snippet, caret = _centered_snippet(line, col)
                print(f"      {sign} {j + 1:>5} | {snippet}")
                print(f"      {' ' * 7}| {' ' * caret}^")
        elif gl == al and gl is not None:
            print(f"        {j + 1:>5} | {_left_truncated(gl)}")
        else:
            print(f"      - {j + 1:>5} | {_left_truncated(gl)}")
            print(f"      + {j + 1:>5} | {_left_truncated(al)}")


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(
        description="Diff the mylang sexpr printer against the Zig golden bytes.",
    )
    ap.add_argument(
        "--update",
        action="store_true",
        help="accepted for compatibility; this script never writes goldens",
    )
    ap.add_argument(
        "--filter",
        default=None,
        metavar="SUBSTR",
        help="only compare goldens whose name contains SUBSTR",
    )
    args = ap.parse_args(argv)

    if args.update:
        print(
            "--update: golden_compare.py never writes goldens.\n"
            "          regenerate them with:\n"
            "            bash experiments/sexpr-port/golden/generate_zig_goldens.sh\n"
        )

    if not MYLANG.is_file():
        print(f"error: no mylang binary at {MYLANG}", file=sys.stderr)
        print("       build it with: zig build", file=sys.stderr)
        return 2
    if not MANIFEST.is_file():
        print(f"error: no manifest at {MANIFEST}", file=sys.stderr)
        print(
            "       generate goldens with: "
            "bash experiments/sexpr-port/golden/generate_zig_goldens.sh",
            file=sys.stderr,
        )
        return 2

    eda_root = Path(os.environ.get("EDA_ROOT", DEFAULT_EDA_ROOT))
    entries = load_manifest(MANIFEST)
    if args.filter:
        entries = [e for e in entries if args.filter in e[0]]

    if not entries:
        print("error: no goldens selected", file=sys.stderr)
        return 2

    passed = 0
    failures: list[tuple[str, str, bytes, bytes]] = []

    print(f"golden_compare: {len(entries)} fixture(s), cwd={REPO_ROOT}")
    for name, raw_path in entries:
        golden_path = GOLDEN_DIR / f"{name}.txt"
        input_path = resolve_input(raw_path, eda_root)

        if not golden_path.is_file():
            print(f"FAIL  {name:<26} missing golden {golden_path}")
            failures.append((name, f"missing golden {golden_path}", b"", b""))
            continue
        if not input_path.is_file():
            print(f"FAIL  {name:<26} missing input {input_path}")
            failures.append((name, f"missing input {input_path}", b"", b""))
            continue

        proc = subprocess.run(
            [str(MYLANG), "run", MAIN, "--", str(input_path), "--render"],
            cwd=REPO_ROOT,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        actual = strip_one_trailing_newline(proc.stdout)

        if proc.returncode != 0:
            err = _decode(proc.stderr).strip()
            print(f"FAIL  {name:<26} mylang exit {proc.returncode}: {err}")
            failures.append((name, f"mylang exit {proc.returncode}: {err}", b"", b""))
            continue

        golden = golden_path.read_bytes()
        if golden == actual:
            passed += 1
            print(f"PASS  {name:<26} {len(golden)} bytes")
        else:
            print(
                f"FAIL  {name:<26} {len(golden)} golden bytes vs "
                f"{len(actual)} mylang bytes"
            )
            failures.append((name, "byte mismatch", golden, actual))

    if failures:
        print("\nfirst differences:")
        for name, reason, golden, actual in failures:
            print(f"\n  --- {name} ({reason}) ---")
            if reason == "byte mismatch":
                report_mismatch(name, golden, actual)
            else:
                print(f"    {reason}")

    total = passed + len(failures)
    print(f"\nsummary: {passed}/{total} passed, {len(failures)} failed")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
