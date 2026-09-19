#!/usr/bin/env python3
"""Independent reference reader for the `.sexp` fixtures.

A small, dependency-free Python S-expression reader that mirrors the intended
grammar (comments, quoted strings with escapes, atoms, ints, floats, SI-scaled
numbers, mm/mil dimensions, `%` literals). It dumps per-file node statistics so
the mylang port can be diffed against it:

  python3 experiments/sexpr-port/reference_parse.py fixtures/*.sexp --json

The mylang CLI prints the same statistics with `--stats`; `compare.py` diffs
the two.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

SI_SCALES = {
    "k": 1e3,
    "M": 1e6,
    "G": 1e9,
    "m": 1e-3,
    "u": 1e-6,
    "n": 1e-9,
    "p": 1e-12,
}
UNIT_LETTERS = "VAFHR"
MIL_TO_MM = 0.0254
DELIMS = set("()\t\n\r ")

# A whole numeric token: sign, digits, optional fraction, optional suffix.
# `m` is a scale only with a following unit letter, so bare `3m` stays an atom;
# `k`/`M`/`G`/`u`/`n`/`p` may be bare or carry one V/A/F/H/R letter.
NUM_RE = re.compile(r"^(-?\d+)(\.\d+)?(mm|mil|%|[kMGunp][VAFHR]?|m[VAFHR]|[VAFHR])?$")


class ParseFailure(Exception):
    pass


class Stats:
    def __init__(self) -> None:
        self.forms = 0
        self.nodes = 0
        self.atoms = 0
        self.strings = 0
        self.ints = 0
        self.floats = 0
        self.measures = 0
        self.max_depth = 0
        self.value_sum = 0.0

    def as_dict(self) -> dict:
        return {
            "forms": self.forms,
            "nodes": self.nodes,
            "atoms": self.atoms,
            "strings": self.strings,
            "ints": self.ints,
            "floats": self.floats,
            "measures": self.measures,
            "max_depth": self.max_depth,
            "value_sum": self.value_sum,
        }


def scan_number(text: str) -> str | None:
    """Classify a numeric token: 'int', 'float', 'unit', 'si' or None."""
    match = NUM_RE.match(text)
    if match is None:
        return None
    suffix = match.group(3) or ""
    if suffix in ("mm", "mil"):
        return "unit"
    if suffix == "%":
        return "si"
    if suffix:
        return "si"
    return "float" if match.group(2) else "int"


def number_value(text: str) -> float:
    match = NUM_RE.match(text)
    assert match is not None
    base = float((match.group(1) or "") + (match.group(2) or ""))
    suffix = match.group(3) or ""
    if suffix == "mm":
        return base
    if suffix == "mil":
        return base * MIL_TO_MM
    if suffix in ("", "%"):
        return base
    return base * SI_SCALES.get(suffix[0], 1.0)


class Reader:
    def __init__(self, src: bytes) -> None:
        self.src = src
        self.pos = 0
        self.line = 1
        self.stats = Stats()

    def fail(self, message: str) -> ParseFailure:
        return ParseFailure(f"{message} at line {self.line}")

    def skip(self) -> None:
        while self.pos < len(self.src):
            ch = self.src[self.pos]
            if ch in b" \t\r\n":
                if ch == 0x0A:
                    self.line += 1
                self.pos += 1
            elif ch == ord(";"):
                while self.pos < len(self.src) and self.src[self.pos] != 0x0A:
                    self.pos += 1
            else:
                return

    def read(self, depth: int = 0) -> str:
        self.skip()
        if self.pos >= len(self.src):
            raise self.fail("unexpected end of input")
        self.stats.max_depth = max(self.stats.max_depth, depth)
        ch = self.src[self.pos]
        if ch == ord("("):
            self.pos += 1
            self.stats.nodes += 1
            self.stats.forms += 1
            while True:
                self.skip()
                if self.pos >= len(self.src):
                    raise self.fail("unclosed list")
                if self.src[self.pos] == ord(")"):
                    self.pos += 1
                    return "form"
                self.read(depth + 1)
        if ch == ord(")"):
            raise self.fail("unexpected )")
        if ch == ord('"'):
            self.pos += 1
            while self.pos < len(self.src):
                c = self.src[self.pos]
                if c == ord("\\"):
                    self.pos += 2
                    continue
                if c == ord('"'):
                    self.pos += 1
                    self.stats.nodes += 1
                    self.stats.strings += 1
                    return "string"
                if c == 0x0A:
                    self.line += 1
                self.pos += 1
            raise self.fail("unterminated string")
        start = self.pos
        while (
            self.pos < len(self.src)
            and chr(self.src[self.pos]) not in DELIMS
            and self.src[self.pos] not in b'";'
        ):
            self.pos += 1
        text = self.src[start : self.pos].decode("utf-8", "replace")
        kind = scan_number(text)
        self.stats.nodes += 1
        if kind == "int":
            self.stats.ints += 1
            self.stats.value_sum += number_value(text)
        elif kind == "float":
            self.stats.floats += 1
            self.stats.value_sum += number_value(text)
        elif kind == "unit":
            self.stats.measures += 1
            self.stats.value_sum += number_value(text)
        elif kind == "si":
            self.stats.floats += 1
            self.stats.value_sum += number_value(text)
        else:
            self.stats.atoms += 1
        return kind or "atom"

    def read_all(self) -> Stats:
        while True:
            self.skip()
            if self.pos >= len(self.src):
                return self.stats
            self.read(0)


def parse_file(path: Path) -> dict:
    reader = Reader(path.read_bytes())
    try:
        stats = reader.read_all()
        return {"path": str(path), "ok": True, **stats.as_dict()}
    except ParseFailure as problem:
        return {"path": str(path), "ok": False, "error": str(problem)}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("paths", nargs="+")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()
    results = [parse_file(Path(p)) for p in args.paths]
    for result in results:
        if args.json:
            print(json.dumps(result))
        else:
            print(result)
    return 0 if all(r["ok"] for r in results) else 1


if __name__ == "__main__":
    sys.exit(main())
