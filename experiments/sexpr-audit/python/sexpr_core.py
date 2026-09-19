#!/usr/bin/env python3
"""Shared, stdlib-only core for the Python sexpr benchmark ports.

`sexpr_pure.py` (hand-rolled byte tokenizer) and `sexpr_np.py` (numpy + regex
tokenizer) both feed this module, so the parser, census and printer are
byte-for-byte the same code and any measured difference between the two ports
comes from the tokenizer alone.

Semantics are a faithful port of `experiments/sexpr-port/sexpr/*.my`, which is
itself a port of the Zig reader in `experiments/sexpr-port/zig-bench/src/sexpr`.
Deliberate representation differences are documented in
`evidence/runtime-compare.md`; the load-bearing one is that a token carries
`(kind, text_bytes, offset)` and no line/column, because no line/column ever
reaches the output.

Token kinds and node tags are small ints rather than objects: tuple compares and
integer dispatch are the cheap paths in CPython.
"""

from __future__ import annotations

import sys
import time

# ── token kinds ───────────────────────────────────────────────────────
K_LPAREN = 0
K_RPAREN = 1
K_ATOM = 2
K_STRING = 3
K_INT = 4
K_FLOAT = 5
K_UNIT = 6
K_SI = 7
K_EOF = 8

# ── node tags ─────────────────────────────────────────────────────────
N_FORM = 0
N_ATOM = 1
N_STRING = 2
N_INT = 3
N_DEC = 4
N_MEASURE = 5

MIL_TO_MM = 0.0254
MAX_PARSE_DEPTH = 10000
_INF = float("inf")
_NEG_INF = float("-inf")

# ── byte classification tables (shared by both tokenizers) ────────────
IS_SPACE = bytearray(256)
for _b in (32, 10, 13, 9):
    IS_SPACE[_b] = 1

IS_DIGIT = bytearray(1 if 48 <= i <= 57 else 0 for i in range(256))

IS_ATOM_START = bytearray(256)
for _b in range(97, 123):        # a-z
    IS_ATOM_START[_b] = 1
for _b in range(65, 91):         # A-Z
    IS_ATOM_START[_b] = 1
for _b in (95, 126, 42):         # _ ~ *
    IS_ATOM_START[_b] = 1

# atom_continue = atom_start | digit | - / . * # @ : + , $
IS_ATOM_CONT = bytearray(IS_ATOM_START)
for _i in range(256):
    if IS_DIGIT[_i]:
        IS_ATOM_CONT[_i] = 1
for _b in (45, 47, 46, 42, 35, 64, 58, 43, 44, 36):
    IS_ATOM_CONT[_b] = 1

# Standalone operators; '*' is absent because it is an atom start.
IS_OP = bytearray(256)
for _b in (43, 45, 47, 37, 62, 60, 61, 33):
    IS_OP[_b] = 1

# SI unit letters "VAFHR".
IS_UNIT = bytearray(256)
for _b in (86, 65, 70, 72, 82):
    IS_UNIT[_b] = 1

# SI scale letters k M G u n p (bare scales) plus m (unit-required scale).
IS_SCALE = bytearray(256)
for _b in (107, 77, 71, 117, 110, 112):
    IS_SCALE[_b] = 1

# A byte's value, or -1 past the end, so predicates read `not IS_ATOM_CONT[c]`.
NO_BYTE = -1


def si_suffix_len(src: bytes, n: int, p: int) -> int:
    """Length (0/1/2) of an SI value suffix at `p`, mirroring tokenizer.my."""
    if p >= n:
        return 0
    c0 = src[p]
    if IS_SCALE[c0]:
        c1 = src[p + 1] if p + 1 < n else NO_BYTE
        if c1 < 0 or not IS_ATOM_CONT[c1]:
            return 1
        if c1 >= 0 and IS_UNIT[c1]:
            c2 = src[p + 2] if p + 2 < n else NO_BYTE
            if c2 < 0 or not IS_ATOM_CONT[c2]:
                return 2
        return 0
    if c0 == 109:  # 'm': a scale only when a unit letter follows
        c1 = src[p + 1] if p + 1 < n else NO_BYTE
        if c1 >= 0 and IS_UNIT[c1]:
            c2 = src[p + 2] if p + 2 < n else NO_BYTE
            if c2 < 0 or not IS_ATOM_CONT[c2]:
                return 2
        return 0
    if IS_UNIT[c0]:
        c1 = src[p + 1] if p + 1 < n else NO_BYTE
        if c1 < 0 or not IS_ATOM_CONT[c1]:
            return 1
    return 0


class LexError(Exception):
    """A tokenizer rejection. Carries the offending byte offset."""

    def __init__(self, message: str, offset: int) -> None:
        super().__init__(message)
        self.message = message
        self.offset = offset


class ParseError(Exception):
    """A parser rejection with the offending token's offset."""

    def __init__(self, message: str, offset: int) -> None:
        super().__init__(message)
        self.message = message
        self.offset = offset


def decode(text: bytes) -> str:
    """A token's text as `str`; invalid UTF-8 becomes "" like mylang's lexeme."""
    try:
        return text.decode()
    except UnicodeDecodeError:
        return ""


# ── parser over a token list ──────────────────────────────────────────

def parse_tokens(src: bytes, tokens: list) -> list:
    """Parse a token list (ending in K_EOF) into top-level nodes."""
    pos = 0
    nodes = []
    append = nodes.append
    while True:
        if tokens[pos][0] == K_EOF:
            return nodes
        node, pos = _parse_node(src, tokens, pos, 0)
        append(node)


def _parse_node(src: bytes, tokens: list, pos: int, depth: int):
    kind, text, offset = tokens[pos]
    nxt = pos + 1
    if kind == K_ATOM:
        return (N_ATOM, decode(text)), nxt
    if kind == K_STRING:
        return (N_STRING, decode(text)), nxt
    if kind == K_INT:
        return (N_INT, int(text)), nxt
    if kind == K_FLOAT:
        return (N_DEC, float(text), None), nxt
    if kind == K_UNIT:
        return _parse_unit(src, text, offset), nxt
    if kind == K_SI:
        return _parse_si(text), nxt
    if kind == K_LPAREN:
        return _parse_list(src, tokens, nxt, depth)
    if kind == K_RPAREN:
        raise ParseError("unexpected ')' — no matching '(' is open here", offset)
    raise ParseError("unexpected end of input — a '(' was never closed", offset)


def _parse_list(src: bytes, tokens: list, pos: int, depth: int):
    if depth >= MAX_PARSE_DEPTH:
        raise ParseError("s-expression nesting is too deep", pos)
    entries = []
    append = entries.append
    while True:
        kind = tokens[pos][0]
        if kind == K_EOF:
            raise ParseError("unexpected end of input — a '(' was never closed", pos)
        if kind == K_RPAREN:
            return (N_FORM, entries), pos + 1
        node, pos = _parse_node(src, tokens, pos, depth + 1)
        append(node)


def _parse_unit(src: bytes, text: bytes, offset: int):
    """Normalise a `mm`/`mil` measure to millimetres.

    The landed tokenizer strips the suffix from a unit token's text, so the
    suffix is recovered from the source bytes, exactly as parser.my does.
    """
    if text.endswith(b"mil"):
        number_text = text[:-3]
        is_mil = True
    elif text.endswith(b"mm"):
        number_text = text[:-2]
        is_mil = False
    else:
        number_text = text
        after = offset + len(text)
        is_mil = src[after:after + 3] == b"mil"
    value = float(number_text)
    if is_mil:
        value = value * MIL_TO_MM
    return (N_MEASURE, value)


def _parse_si(text: bytes):
    """Apply an SI scale from the literal's first suffix letter."""
    end = 0
    size = len(text)
    while end < size:
        ch = text[end]
        if 48 <= ch <= 57 or ch == 46 or (ch == 45 and end == 0):
            end += 1
        else:
            break
    if end == 0 or end == size:
        raise ParseError("invalid number literal", 0)
    value = float(text[:end])
    suffix = text[end]
    if suffix == 107:      # k
        value = value * 1e3
    elif suffix == 77:     # M
        value = value * 1e6
    elif suffix == 71:     # G
        value = value * 1e9
    elif suffix == 109:    # m
        value = value * 1e-3
    elif suffix == 117:    # u
        value = value * 1e-6
    elif suffix == 110:    # n
        value = value * 1e-9
    elif suffix == 112:    # p
        value = value * 1e-12
    return (N_DEC, value, decode(text))


def zig_decimal(value: float) -> str:
    """The shortest round-trip spelling in positional notation, like Zig `{d}`.

    Zig's decimal float mode (std.fmt.float.formatDecimal) never uses an
    exponent and never forces a trailing ".0": 1e-5 is "0.00001", 4.0 is "4",
    1e16 is "10000000000000000". Python's repr picks the same shortest digits but
    switches to scientific notation for small and large magnitudes, so the digit
    string is re-laid-out positionally here. mylang's `str(float)` is this plus a
    forced ".0" (native_format.zig); the printer relies on the distinction.
    """
    if value != value:
        return "nan"
    if value == _INF:
        return "inf"
    if value == _NEG_INF:
        return "-inf"
    if value == 0.0:
        return "-0" if str(value)[0] == "-" else "0"
    text = repr(value)
    sign = ""
    if text[0] == "-":
        sign = "-"
        text = text[1:]
    if "e" in text:
        mantissa, _, exponent_text = text.partition("e")
        exponent = int(exponent_text)
    else:
        mantissa = text
        exponent = 0
    if "." in mantissa:
        int_part, _, frac_part = mantissa.partition(".")
    else:
        int_part, frac_part = mantissa, ""
    digits = int_part + frac_part
    point = len(int_part) + exponent
    stripped = digits.lstrip("0")
    point -= len(digits) - len(stripped)
    digits = stripped.rstrip("0") or "0"
    if point <= 0:
        return f"{sign}0.{'0' * -point}{digits}"
    if point >= len(digits):
        return f"{sign}{digits}{'0' * (point - len(digits))}"
    return f"{sign}{digits[:point]}.{digits[point:]}"


def float_text(value: float) -> str:
    """mylang's `str(float)`: Zig `{d}`, with ".0" forced on a whole value."""
    text = zig_decimal(value)
    if "." not in text and "e" not in text and "E" not in text:
        return text + ".0"
    return text


# ── census (parse + walk) ─────────────────────────────────────────────

def census(nodes: list) -> str:
    """The census line, field-for-field the one zig-bench and main.my print.

    The walk is an explicit pre-order stack rather than recursion: it visits
    nodes in exactly the same order, so the f64 `value_sum` accumulates the
    same additions in the same sequence and the printed line is identical.
    """
    forms = 0
    node_count = 0
    atoms = 0
    strings = 0
    ints = 0
    floats = 0
    measures = 0
    max_depth = 0
    values = 0.0
    stack = [(node, 0) for node in reversed(nodes)]
    pop = stack.pop
    push = stack.append
    while stack:
        node, depth = pop()
        node_count += 1
        if depth > max_depth:
            max_depth = depth
        tag = node[0]
        if tag == N_FORM:
            forms += 1
            children = node[1]
            for child in reversed(children):
                push((child, depth + 1))
        elif tag == N_ATOM:
            atoms += 1
        elif tag == N_STRING:
            strings += 1
        elif tag == N_INT:
            ints += 1
            values += float(node[1])
        elif tag == N_DEC:
            floats += 1
            values += node[1]
        else:
            measures += 1
            values += node[1]
    return (f"forms={forms} nodes={node_count} atoms={atoms} strings={strings} "
            f"ints={ints} floats={floats} measures={measures} max_depth={max_depth} "
            f"value_sum={zig_decimal(values)}")


# ── printer (parse + render) ──────────────────────────────────────────

SHORT_LIST_MAX_WIDTH = 72
FALLBACK_INT_WIDTH = 12
FALLBACK_FLOAT_WIDTH = 12
FALLBACK_UNIT_VAL_WIDTH = 14


def render_float(value: float) -> str:
    """Zig printFloat: shortest round-trip decimal, ".0" if whole."""
    text = float_text(value)
    if "." not in text and "e" not in text and "n" not in text:
        return text + ".0"
    return text


def _estimate_width(node, depth: int):
    """The one-line width, or None past four levels (Zig's estimateWidth)."""
    if depth > 3:
        return None
    tag = node[0]
    if tag == N_FORM:
        total = 2
        first = True
        for child in node[1]:
            if not first:
                total += 1
            width = _estimate_width(child, depth + 1)
            if width is None:
                return None
            total += width
            first = False
        return total
    if tag == N_ATOM:
        return len(node[1])
    if tag == N_STRING:
        return len(node[1]) + 2
    if tag == N_INT:
        text = str(node[1])
        return len(text) if text else FALLBACK_INT_WIDTH
    if tag == N_DEC:
        literal = node[2]
        if literal is not None:
            return len(literal) if literal else FALLBACK_FLOAT_WIDTH
        text = float_text(node[1])
        if text.endswith(".0"):
            text = text[:-2]
        return len(text) if text else FALLBACK_FLOAT_WIDTH
    text = float_text(node[1])
    if text.endswith(".0"):
        text = text[:-2]
    return (len(text) if text else FALLBACK_UNIT_VAL_WIDTH) + 2


def _is_short_list(entries: list) -> bool:
    total = 2
    first = True
    for child in entries:
        if not first:
            total += 1
        width = _estimate_width(child, 0)
        if width is None:
            return False
        total += width
        if total > SHORT_LIST_MAX_WIDTH:
            return False
        first = False
    return True


def _push_indent(parts: list, indent: int) -> None:
    for _ in range(indent):
        parts.append(" ")


def _push_node(parts: list, node, indent: int) -> None:
    tag = node[0]
    if tag == N_FORM:
        entries = node[1]
        if not entries:
            parts.append("()")
            return
        if _is_short_list(entries):
            parts.append("(")
            first = True
            for child in entries:
                if not first:
                    parts.append(" ")
                _push_node(parts, child, indent + 2)
                first = False
            parts.append(")")
            return
        parts.append("(")
        _push_node(parts, entries[0], indent + 2)
        for child in entries[1:]:
            parts.append("\n")
            _push_indent(parts, indent + 2)
            _push_node(parts, child, indent + 2)
        parts.append(")")
        return
    if tag == N_ATOM:
        parts.append(node[1])
        return
    if tag == N_STRING:
        parts.append('"')
        parts.append(node[1])
        parts.append('"')
        return
    if tag == N_INT:
        parts.append(str(node[1]))
        return
    if tag == N_DEC:
        literal = node[2]
        if literal is not None:
            parts.append(literal)
        else:
            parts.append(render_float(node[1]))
        return
    parts.append(render_float(node[1]))
    parts.append("mm")


def render(nodes: list) -> str:
    """Canonical document text: one '\\n' between top-level nodes, none after."""
    parts = []
    first = True
    for node in nodes:
        if not first:
            parts.append("\n")
        _push_node(parts, node, 0)
        first = False
    return "".join(parts)


# ── shared CLI driver ─────────────────────────────────────────────────

def run_cli(path: str, mode: str, tokenize, scan=None, timings=None) -> int:
    """Run one phase over `path` using the given tokenizer and byte scan.

    Output lines match `zig-bench` exactly (including trailing newline), so the
    Python stdout digest can be compared with the Zig one for every phase.
    `work_ms` on stderr is the read-plus-work time only: interpreter start-up,
    module import and the final stdout write are excluded. `scan` defaults to a
    hand-rolled byte loop; sexpr_np passes a numpy one, which reports its own
    lazy import under `import_ms` so a one-shot scan is not conflated with the
    cost of loading the library.
    """
    sys.setrecursionlimit(30000)
    start = time.perf_counter()
    with open(path, "rb") as handle:
        data = handle.read()
    if mode == "--loop":
        size = len(data)
        index = 0
        while index < size:
            index += 1
        out = f"bytes={size} index={index}"
        render_out = False
    elif mode == "--scan":
        if scan is None:
            count = 0
            for byte in data:
                if byte == 40 or byte == 41:
                    count += 1
        else:
            count = scan(data, timings)
        out = f"bytes={len(data)} delims={count}"
        render_out = False
    elif mode == "--tokens":
        out = f"tokens={tokenize(data, False)}"
        render_out = False
    elif mode == "--parse":
        nodes = parse_tokens(data, tokenize(data, True))
        out = f"roots={len(nodes)}"
        render_out = False
    elif mode == "--render":
        nodes = parse_tokens(data, tokenize(data, True))
        out = render(nodes)
        render_out = True
    else:
        nodes = parse_tokens(data, tokenize(data, True))
        out = census(nodes)
        render_out = False
    work_ms = (time.perf_counter() - start) * 1000.0
    import_ms = 0.0
    if timings:
        import_ms = timings.get("import_ms", 0.0)
    sys.stderr.write(f"work_ms={work_ms - import_ms:.3f} import_ms={import_ms:.3f}\n")
    if render_out:
        sys.stdout.buffer.write(out.encode("utf-8") + b"\n")
    else:
        sys.stdout.write(out + "\n")
    return 0

