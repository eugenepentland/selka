#!/usr/bin/env python3
"""Tuned Python sexpr benchmark driver.

Same shared parser/census/printer and numpy scan as `sexpr_np.py`, but the
tokenizer is roughly twice as fast, and it produces a *token-for-token identical*
list. The win is entirely in the regular expression:

  * the obvious escape-aware string subpattern, `"(?:\\\\.|[^"\\\\])*"`, makes
    CPython's regex engine test every byte twice; the unrolled form,
    `"[^"\\\\]*(?:\\\\.[^"\\\\]*)*"`, finds the next quote with a character-class
    scan and only pays for a backslash when one occurs (~10x on this input).
  * one `finditer` over the whole source lets the C engine skip whitespace, so
    the 17,920 whitespace runs are not turned into Python-level matches.
  * the number grammar is folded into the pattern (with possessive quantifiers on
    the fallback-atom arm so a plain `12.063` cannot be mistaken for an atom),
    which removes the per-number `match` + tail-extension step.

Everything else — including the deliberate representation differences noted in
`evidence/runtime-compare.md` — is shared with `sexpr_np.py`.

Usage:
  python3 sexpr_tuned.py <input.sexp> [--loop|--scan|--tokens|--parse|--render]
"""

from __future__ import annotations

import re
import sys
import time

from sexpr_core import (
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
)

# Alternatives in tokenizer priority order. Groups:
#   1 `(`  2 `)`  3 string  4 number+SI/measure suffix  5 number-fallback atom
#   6 plain number  7 atom  8 operator  9 `;` comment  10 unexpected byte
# Whitespace is deliberately unmatched: finditer skips it in C. The catch-all at
# the end excludes the four whitespace bytes so a stray one is never a token.
_PATTERN = re.compile(
    rb"(\()"
    rb"|(\))"
    rb'|("[^"\\]*(?:\\.[^"\\]*)*")'
    rb"|(-?\d+(?:\.\d+)?(?:mm|mil|[kMGunp][VAFHR]?|m[VAFHR]|[VAFHR]|%)"
    rb"(?![A-Za-z0-9_~*\-/.#@:+,$]))"
    rb"|(-?\d++(?:\.\d+)?+(?=[A-Za-z0-9_~*\-/.#@:+,$])[A-Za-z0-9_~*\-/.#@:+,$]+)"
    rb"|(-?\d+(?:\.\d+)?)"
    rb"|([A-Za-z_~*][A-Za-z0-9_~*\-/.#@:+,$]*)"
    rb"|([+\-/%><=!]=?)"
    rb"|(;[^\n]*)"
    rb"|([^ \t\n\r])",
    re.DOTALL,
)


def tokenize(src: bytes, collect: bool = True):
    """Tokenize with one C-level `finditer` pass.

    With `collect=True` returns the same token list as `sexpr_np.tokenize` (the
    shared parser, census and printer are unchanged); with `collect=False`
    returns the streaming non-EOF count.
    """
    n = len(src)
    tokens = [] if collect else None
    append = tokens.append if collect else None
    count = 0
    for found in _PATTERN.finditer(src):
        which = found.lastindex
        if which == 9:  # `;` comment
            continue
        if which == 1:
            kind = K_LPAREN
            text = b"("
        elif which == 2:
            kind = K_RPAREN
            text = b")"
        elif which == 3:
            kind = K_STRING
            text = found.group()[1:-1]
        elif which == 6:
            group = found.group()
            kind = K_FLOAT if b"." in group else K_INT
            text = group
        elif which == 4:
            group = found.group()
            if group.endswith(b"mm"):
                kind = K_UNIT
                text = group[:-2]
            elif group.endswith(b"mil"):
                kind = K_UNIT
                text = group[:-3]
            else:
                kind = K_SI
                text = group
        elif which == 5 or which == 7 or which == 8:
            kind = K_ATOM
            text = found.group()
        else:  # 10: a byte no alternative accepts
            if src[found.start()] == 34:
                raise LexError("unterminated string", found.start())
            raise LexError("unexpected character", found.start())
        if collect:
            append((kind, text, found.start()))
        count += 1
    if collect:
        append((K_EOF, b"", n))
        return tokens
    return count


def numpy_scan(data: bytes, timings=None) -> int:
    """Vectorised delimiter count, with the lazy import reported separately."""
    start = time.perf_counter()
    import numpy as np

    if timings is not None:
        timings["import_ms"] = (time.perf_counter() - start) * 1000.0
    array = np.frombuffer(data, dtype=np.uint8)
    return int(np.count_nonzero((array == 40) | (array == 41)))


def main(argv: list) -> int:
    if len(argv) < 2:
        sys.stderr.write("usage: sexpr_tuned.py <input.sexp> "
                         "[--loop|--scan|--tokens|--parse|--render]\n")
        return 2
    mode = argv[2] if len(argv) > 2 else ""
    return run_cli(argv[1], mode, tokenize, scan=numpy_scan, timings={})


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
