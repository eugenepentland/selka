#!/usr/bin/env python3
"""Library-accelerated Python sexpr benchmark driver.

The same shared parser/census/printer as `sexpr_pure.py`, but the byte-level
work is pushed into C:

  * `--scan`   numpy: `np.frombuffer` + a vectorised comparison, no Python loop
  * tokenize   `re`: one compiled alternation scanned at C speed; the only
               per-token Python work left is classification and tuple creation
  * numpy is imported only for `--scan`, so the other phases are not charged an
    import they do not use (its cost is reported separately in the notes).

Usage:
  python3 sexpr_np.py <input.sexp> [--loop|--scan|--tokens|--parse|--render]
"""

from __future__ import annotations

import re
import sys
import time

from sexpr_core import (
    IS_ATOM_CONT,
    K_ATOM,
    K_EOF,
    K_FLOAT,
    K_INT,
    K_LPAREN,
    K_RPAREN,
    K_SI,
    K_STRING,
    K_UNIT,
    LexError,
    run_cli,
    si_suffix_len,
)

_LPAREN = b"("
_RPAREN = b")"
_QUOTE = 34

# One alternation, alternatives in tokenizer priority order. Groups 1-2 are
# skipped (whitespace, `;` comment); 3-8 are the token forms; 9 is a catch-all
# so every position matches something and the loop always advances.
_PATTERN = re.compile(
    rb"(\s+)"
    rb"|(;[^\n]*)"
    rb"|(\()"
    rb"|(\))"
    rb'|("(?:\\.|[^"\\])*")'
    rb"|(-?\d+(?:\.\d+)?)"
    rb"|([A-Za-z_~*][A-Za-z0-9_~*\-/.#@:+,$]*)"
    rb"|([+\-/%><=!]=?)"
    rb"|(.)",
    re.DOTALL,
)


def _number_tail(src: bytes, n: int, start: int, p: int):
    """Classify the text after the matched numeric prefix `[start, p)`.

    Returns `(kind, end, text_end)`: `end` is where scanning resumes (past any
    suffix) and `text_end` bounds the token's text (which, for a `mm`/`mil`
    measure, stops before the suffix, exactly as tokenizer.my does).
    """
    is_float = False
    for index in range(start, p):
        if src[index] == 46:  # '.'
            is_float = True
            break
    num_end = p
    if p < n and src[p] == 109:  # 'm'
        p1 = src[p + 1] if p + 1 < n else -1
        if p1 == 109:  # mm
            p2 = src[p + 2] if p + 2 < n else -1
            if p2 < 0 or not IS_ATOM_CONT[p2]:
                return K_UNIT, p + 2, num_end
        elif p1 == 105:  # mi...
            p2 = src[p + 2] if p + 2 < n else -1
            p3 = src[p + 3] if p + 3 < n else -1
            if p2 == 108 and (p3 < 0 or not IS_ATOM_CONT[p3]):  # mil
                return K_UNIT, p + 3, num_end
    suffix = si_suffix_len(src, n, p)
    if suffix:
        return K_SI, p + suffix, p + suffix
    if p < n and src[p] == 37:  # '%'
        p1 = src[p + 1] if p + 1 < n else -1
        if p1 < 0 or not IS_ATOM_CONT[p1]:
            return K_SI, p + 1, p + 1
    if p < n and IS_ATOM_CONT[src[p]]:
        while p < n and IS_ATOM_CONT[src[p]]:
            p += 1
        return K_ATOM, p, p
    return (K_FLOAT if is_float else K_INT), p, p


def tokenize(src: bytes, collect: bool = True):
    """Regex tokenizer; `collect=False` returns a streaming count like Zig."""
    n = len(src)
    pos = 0
    tokens = [] if collect else None
    append = tokens.append if collect else None
    count = 0
    match = _PATTERN.match
    while pos < n:
        found = match(src, pos)
        which = found.lastindex
        start = found.start()
        end = found.end()
        if which <= 2:
            pos = end
            continue
        if which == 3:
            kind = K_LPAREN
            text = _LPAREN
        elif which == 4:
            kind = K_RPAREN
            text = _RPAREN
        elif which == 5:
            kind = K_STRING
            text = src[start + 1:end - 1]
        elif which == 7 or which == 8:
            kind = K_ATOM
            text = src[start:end]
        elif which == 6:
            kind, end, text_end = _number_tail(src, n, start, end)
            text = src[start:text_end]
        else:
            if src[start] == _QUOTE:
                raise LexError("unterminated string", start)
            raise LexError("unexpected character", start)
        pos = end
        if collect:
            append((kind, text, start))
        count += 1
    if collect:
        append((K_EOF, b"", n))
    return tokens if collect else count


def numpy_scan(data: bytes, timings=None) -> int:
    """Vectorised delimiter count.

    numpy is imported here so only --scan pays for it, and the import time is
    reported separately: for a one-shot scan of a sub-megabyte buffer the import
    can cost more than the scan, and conflating the two would hide that.
    """
    start = time.perf_counter()
    import numpy as np

    if timings is not None:
        timings["import_ms"] = (time.perf_counter() - start) * 1000.0
    array = np.frombuffer(data, dtype=np.uint8)
    return int(np.count_nonzero((array == 40) | (array == 41)))


def main(argv: list) -> int:
    if len(argv) < 2:
        sys.stderr.write("usage: sexpr_np.py <input.sexp> "
                         "[--loop|--scan|--tokens|--parse|--render]\n")
        return 2
    mode = argv[2] if len(argv) > 2 else ""
    return run_cli(argv[1], mode, tokenize, scan=numpy_scan, timings={})


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
