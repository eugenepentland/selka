#!/usr/bin/env python3
"""Pure-Python (stdlib only) sexpr benchmark driver.

A hand-rolled byte tokenizer feeding the shared parser/census/printer in
`sexpr_core.py`. No third-party module is imported, so this is the "what does
CPython cost on its own" column.

Usage:
  python3 sexpr_pure.py <input.sexp> [--loop|--scan|--tokens|--parse|--render]

Prints the same line as `zig-bench` for the chosen phase (census and render
match `main.my` too) and the read+work milliseconds on stderr.
"""

from __future__ import annotations

import sys

from sexpr_core import (
    IS_ATOM_CONT,
    IS_ATOM_START,
    IS_DIGIT,
    IS_OP,
    IS_SPACE,
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


def tokenize(src: bytes, collect: bool = True):
    """Tokenize `src`.

    With `collect=True` returns the token list ending in K_EOF (what the parser
    needs). With `collect=False` returns the count of non-EOF tokens without
    materialising them, mirroring zig-bench's streaming `--tokens` phase.
    """
    n = len(src)
    pos = 0
    tokens = [] if collect else None
    append = tokens.append if collect else None
    count = 0
    while True:
        # whitespace and `;` comments
        while pos < n:
            b = src[pos]
            if IS_SPACE[b]:
                pos += 1
            elif b == 59:  # ';'
                pos += 1
                while pos < n and src[pos] != 10:
                    pos += 1
            else:
                break
        if pos >= n:
            if collect:
                append((K_EOF, b"", pos))
            return tokens if collect else count

        start = pos
        b = src[pos]

        if b == 40:  # (
            pos += 1
            if collect:
                append((K_LPAREN, _LPAREN, start))
            count += 1
            continue
        if b == 41:  # )
            pos += 1
            if collect:
                append((K_RPAREN, _RPAREN, start))
            count += 1
            continue
        if b == 34:  # "
            pos += 1
            text_start = pos
            closed = False
            while pos < n:
                c = src[pos]
                if c == 92:      # backslash swallows the next byte
                    pos += 2
                elif c == 34:
                    closed = True
                    break
                else:
                    pos += 1
            if not closed:
                raise LexError("unterminated string", start)
            if collect:
                append((K_STRING, src[text_start:pos], start))
            count += 1
            pos += 1
            continue
        if IS_DIGIT[b] or (b == 45 and pos + 1 < n and IS_DIGIT[src[pos + 1]]):
            p = pos
            if src[p] == 45:
                p += 1
            while p < n and IS_DIGIT[src[p]]:
                p += 1
            is_float = False
            if p + 1 < n and src[p] == 46 and IS_DIGIT[src[p + 1]]:
                is_float = True
                p += 1
                while p < n and IS_DIGIT[src[p]]:
                    p += 1
            num_end = p
            # dimension units: the token text stops before the suffix
            if p < n and src[p] == 109:  # 'm'
                p1 = src[p + 1] if p + 1 < n else -1
                if p1 == 109:
                    p2 = src[p + 2] if p + 2 < n else -1
                    if p2 < 0 or not IS_ATOM_CONT[p2]:
                        pos = p + 2
                        if collect:
                            append((K_UNIT, src[start:num_end], start))
                        count += 1
                        continue
                elif p1 == 105:  # 'i'
                    p2 = src[p + 2] if p + 2 < n else -1
                    p3 = src[p + 3] if p + 3 < n else -1
                    if p2 == 108 and (p3 < 0 or not IS_ATOM_CONT[p3]):
                        pos = p + 3
                        if collect:
                            append((K_UNIT, src[start:num_end], start))
                        count += 1
                        continue
            suffix = si_suffix_len(src, n, p)
            if suffix:
                p += suffix
                pos = p
                if collect:
                    append((K_SI, src[start:p], start))
                count += 1
                continue
            if p < n and src[p] == 37:  # '%'
                p1 = src[p + 1] if p + 1 < n else -1
                if p1 < 0 or not IS_ATOM_CONT[p1]:
                    p += 1
                    pos = p
                    if collect:
                        append((K_SI, src[start:p], start))
                    count += 1
                    continue
            if p < n and IS_ATOM_CONT[src[p]]:
                while p < n and IS_ATOM_CONT[src[p]]:
                    p += 1
                pos = p
                if collect:
                    append((K_ATOM, src[start:p], start))
                count += 1
                continue
            pos = p
            if collect:
                append((K_FLOAT if is_float else K_INT, src[start:p], start))
            count += 1
            continue
        if IS_ATOM_START[b]:
            pos += 1
            while pos < n and IS_ATOM_CONT[src[pos]]:
                pos += 1
            if collect:
                append((K_ATOM, src[start:pos], start))
            count += 1
            continue
        if IS_OP[b]:
            pos += 1
            if pos < n and src[pos] == 61:  # '=' second char of >= <= == !=
                pos += 1
            if collect:
                append((K_ATOM, src[start:pos], start))
            count += 1
            continue
        raise LexError("unexpected character", start)


def main(argv: list) -> int:
    if len(argv) < 2:
        sys.stderr.write("usage: sexpr_pure.py <input.sexp> "
                         "[--loop|--scan|--tokens|--parse|--render]\n")
        return 2
    mode = argv[2] if len(argv) > 2 else ""
    return run_cli(argv[1], mode, tokenize)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
