#!/usr/bin/env python3
"""The gate action `mode_differential`: generated programs must mean the same in every build mode.

The driver writes small valid programs from a seed, builds each one three ways with the compiler under test and requires
the three to agree:

* the plain build (`selka build`, the lean debug build `selka run` makes),
* the release build (`selka build --release`),
* `selka test` (its `--debug-o0` build, with the test runner's step, frame and memory limits).

A program holds `FUNCTIONS` generated functions `gen_K() -> T`. Its `main(args, out)` prints `gen_K()` for the `K` in
`args[0]`, so each built binary runs once per function, and each function's outcome is its printed text or its trap (code,
operands, line and column). The test file is the same source with one `test_gen_K` per function, written after the plain
run: it expects the plain build's text, `str(gen_K()) == "TEXT"`, or fails with the plain build's trap. An internal compiler
error in any mode (`E_FACT_VALIDATION`, `E_OWNERSHIP_VALIDATION`, `E_CORE_HIDDEN_COPY`, `E_CORE_UNSUPPORTED`, any build
failure that is not a diagnostic of the program, a signal) fails by itself; a program the checker refuses is a fault of
this generator and fails too.

    python3 tests/mode_differential.py --compiler zig-out/bin/selka             # the gate's fixed seeds
    python3 tests/mode_differential.py --compiler C --seeds 1000..1999 --keep DIR # a hunt outside the gate
    python3 tests/mode_differential.py --compiler C --reduce DIR/seed-1234/run/gen.selka
    python3 tests/mode_differential.py --print 17                                 # the program of seed 17

The random choices come from this file's own SplitMix64, so a seed names the same program on every machine and Python.
Every build uses private stores under a temporary directory (`--work`), removed at the end; a failing program is copied
to `--keep` (default `.selka-cache/mode-differential/kept`). Exit status: 0 when every program agrees, 1 when one does
not, 2 on a usage error.
"""
from __future__ import annotations

import argparse
import functools
import concurrent.futures
import json
import os
import re
import resource
import shutil
import subprocess
import sys
import tempfile
import time
from dataclasses import dataclass
from pathlib import Path

# The gate's fixed workload. Changing it changes the action's inputs (this file), so the verdict reruns.
GATE_SEEDS = range(1, 14)
FUNCTIONS = 24
INTERNAL_CODES = ("E_FACT_VALIDATION", "E_OWNERSHIP_VALIDATION", "E_CORE_HIDDEN_COPY", "E_CORE_UNSUPPORTED",
                  "E_ENGINE_VERIFY", "E_INTERNAL")
# Each mode: (is a `selka test` run, its flags). The plain build is the reference the test file is written from.
MODES = {
    "plain": (False, []),
    "release": (False, ["--release"]),
    "test": (True, []),
    "o0": (False, ["--debug-o0"]),
    "unopt": (False, ["--unoptimized"]),
    "test-unopt": (True, ["--unoptimized"]),
}
BASE_MODES = ("plain", "release", "test")
EXTRA_EVERY = 4  # one program in four is also built with `--debug-o0` and `--unoptimized`, and tested `--unoptimized`
ALL_MODES = tuple(MODES)
RUN_SECONDS = 20
BUILD_SECONDS = 600
GUEST_ADDRESS_SPACE = 8 * 1024 * 1024 * 1024

MASK64 = (1 << 64) - 1


class Rng:
    """SplitMix64: a fixed sequence for a seed, independent of Python's `random`."""

    def __init__(self, seed: int) -> None:
        self.state = seed & MASK64

    def next(self) -> int:
        self.state = (self.state + 0x9E3779B97F4A7C15) & MASK64
        z = self.state
        z = ((z ^ (z >> 30)) * 0xBF58476D1CE4E5B9) & MASK64
        z = ((z ^ (z >> 27)) * 0x94D049BB133111EB) & MASK64
        return z ^ (z >> 31)

    def below(self, n: int) -> int:
        return self.next() % n

    def randint(self, lo: int, hi: int) -> int:
        return lo + self.below(hi - lo + 1)

    def chance(self, per_mille: int) -> bool:
        return self.below(1000) < per_mille

    def choice(self, items):
        return items[self.below(len(items))]


def program_rng(seed: int) -> Rng:
    """The generator of one program: the seed mixed once, so neighbouring seeds start far apart."""
    return Rng(Rng(seed * 0x2545F4914F6CDD1D + 0x1D).next())


# Integer types with their bounds; `int` is the signed 64-bit default and takes unsuffixed literals.
WIDTHS = {
    "int": (-(1 << 63), (1 << 63) - 1, 64),
    "i8": (-(1 << 7), (1 << 7) - 1, 8),
    "i16": (-(1 << 15), (1 << 15) - 1, 16),
    "i32": (-(1 << 31), (1 << 31) - 1, 32),
    "u8": (0, (1 << 8) - 1, 8),
    "u16": (0, (1 << 16) - 1, 16),
    "u32": (0, (1 << 32) - 1, 32),
    "u64": (0, (1 << 64) - 1, 64),
}
FIXED = [t for t in WIDTHS if t != "int"]
FLOAT_LITERALS = ["0.0", "-0.0", "1.5", "0.1", "3.0", "-2.5", "100.0", "1.0e300", "1.0e-300", "0.5", "7.25"]
TEXT_LITERALS = ["", "a", "b", "ab", "ba", "abc", "zz", "hello", "x y", "-1", "0"]
KEYS = ['"a"', '"b"', '"c"', '"ab"', '"zz"']
RETURN_TYPES = ["int"] * 10 + FIXED + ["float", "float", "bool", "bool", "bool", "str", "str"]

HEADER = '''import dicts
import sets
import strings


record P:
    a: int
    b: int[]


record Q:
    x: int
    y: int


record R:
    n: i32
    t: str
    f: float


enum Sh:
    empty
    rad(value: int)
    pt(x: int, y: int)


enum Bx:
    none
    box(value: P)


func helper_mut(mut xs: int[], k: int):
    append(mut xs, k)
    if len(xs) > 1:
        xs[0] = xs[0] + k


func helper_rec(mut p: P, k: int):
    p.a = p.a + k
    append(mut p.b, k)


func pick(o: int?) -> int:
    match o:
        case Some(v):
            return v
        case None:
            return -1


func swapq(w: Q) -> Q:
    return Q(x=w.y, y=w.x)


func bump_first(mut rs: P[], k: int):
    if len(rs) > 0:
        rs[0].a = rs[0].a + k
        append(mut rs[0].b, k)


func total(xs: int[]) -> int:
    mut s = 0
    for x in xs:
        s = s + x
    return s


func bump(mut n: int, k: int):
    n = n + k


func score(s: Sh) -> int:
    match s:
        case empty:
            return 0
        case rad(value=r):
            return r * r
        case pt(x=a, y=b):
            return a - b


func grow(mut s: Sh, k: int):
    match mut s:
        case rad(value=r):
            r = r + k
        case pt(x=a, y=b):
            a = a - k
            b = b + a
        case empty:
            return


func chk(v: int) -> int fails int:
    if v < 0:
        fail v
    if v > 1000:
        fail 7
    return v + 1


func chain(a: int, b: int) -> int fails int:
    const x = try chk(a)
    const y = try chk(b)
    return x * y


func or_else(a: int, b: int, d: int) -> int:
    match chain(a, b):
        case Ok(v):
            return v
        case Err(e):
            return d - e


func fib(n: int) -> int:
    if n < 2:
        return n
    return fib(n - 1) + fib(n - 2)


func sum_to(n: int) -> int:
    if n <= 0:
        return 0
    return n + sum_to(n - 1)


func pick2[T](a: T, b: T, c: bool) -> T from a, b:
    if c:
        return a
    return b


func first_or[T: copy + storable](xs: T[], d: T) -> T:
    if len(xs) > 0:
        return copy(xs[0])
    return copy(d)


func rlen(r: R) -> int:
    return len(r.t) + int(r.n)


func bsum(b: Bx) -> int:
    match b:
        case box(value=pv):
            return pv.a + len(pv.b)
        case none:
            return -7


func yes() -> bool:
    return True


func no() -> bool:
    return False


func pos(x: int) -> bool:
    return x > 0


func key_sum(d: dict[str, int]) -> int:
    mut n = 0
    for k in d:
        n = n + d[k] + len(k)
    return n
'''


class Gen:
    """Writes one function in a typed subset: every expression has a known type, every name is in scope."""

    def __init__(self, rng: Rng) -> None:
        self.r = rng

    # ---- scope -------------------------------------------------------------------------------------------------
    def reset(self) -> None:
        self.n = 0
        self.vars: dict[str, list[str]] = {}
        self.readonly: set[str] = set()
        self.frozen: set[str] = set()  # collections a surrounding loop walks: the body must not change them

    def fresh(self, prefix: str) -> str:
        self.n += 1
        return f"{prefix}_{self.n}"

    def declare(self, name: str, ty: str, readonly: bool = False) -> None:
        self.vars.setdefault(ty, []).append(name)
        if readonly:
            self.readonly.add(name)

    def of(self, ty: str) -> list[str]:
        return self.vars.get(ty, [])

    def writable(self, ty: str) -> list[str]:
        return [v for v in self.of(ty) if v not in self.readonly and v not in self.frozen]

    def snapshot(self):
        return {k: list(v) for k, v in self.vars.items()}

    def restore(self, saved) -> None:
        self.vars = {k: list(v) for k, v in saved.items()}

    # ---- literals ----------------------------------------------------------------------------------------------
    def int_literal(self, ty: str) -> str:
        lo, hi, _ = WIDTHS[ty]
        if self.r.chance(130):
            v = self.r.choice([lo, lo + 1, hi, hi - 1, hi // 2, hi // 2 + 1, 0, 1, int(hi ** 0.5) + 1, -1, 2])
        else:
            v = self.r.randint(-20, 40)
        v = min(max(v, lo), hi)
        text = str(v)
        if ty != "int":
            text += ty
        return text

    def text_literal(self) -> str:
        return '"' + self.r.choice(TEXT_LITERALS) + '"'

    # ---- expressions -------------------------------------------------------------------------------------------
    def expr(self, ty: str, d: int = 0) -> str:
        if ty in WIDTHS:
            return self.int_expr(ty, d)
        if ty == "float":
            return self.float_expr(d)
        if ty == "bool":
            return self.bool_expr(d)
        if ty == "str":
            return self.str_expr(d)
        raise ValueError(ty)

    def value(self, ty: str, d: int = 0) -> str:
        """An expression to store: a text that only lends (a name, a field, a slice, `pick2`) is copied."""
        e = self.expr(ty, d)
        if ty == "str" and (re.fullmatch(r"\w+", e) or e.startswith("pick2(") or e.endswith(".t") or e.endswith("]")):
            return f"copy({e})"
        return e

    def leaf(self, ty: str) -> str:
        names = self.of(ty)
        if names and self.r.chance(600):
            return self.r.choice(names)
        if ty in WIDTHS:
            return self.int_literal(ty)
        if ty == "float":
            return self.r.choice(FLOAT_LITERALS)
        if ty == "bool":
            return self.r.choice(["True", "False"])
        return self.text_literal()

    def int_expr(self, ty: str, d: int) -> str:
        if self.r.chance(3):
            return self.edge(ty)
        if d > 2 or self.r.chance(250):
            return self.leaf(ty)
        r = self.r.below(1000)
        if ty == "int":
            special = self.int_only(d, r)
            if special:
                return special
        if r < 560:
            op = self.r.choice(["+", "-", "*", "+", "-", "//", "%"])
            if op in ("-", "*") and WIDTHS[ty][0] == 0 and self.r.chance(600):
                # small unsigned operands make `-` trap about half the time; the wrapping and saturating forms keep going
                f = self.r.choice(["wrapping_", "saturating_"]) + ("sub" if op == "-" else "mul")
                return f"{f}({self.int_expr(ty, d + 1)}, {self.int_expr(ty, d + 1)})"
            if op in ("//", "%") and self.r.chance(800):
                divisors = ["3", "7", "16", "1"] + (["-4", "-1"] if WIDTHS[ty][0] < 0 else [])
                div = self.r.choice(divisors) + ("" if ty == "int" else ty)
                return f"({self.int_expr(ty, d + 1)} {op} {div})"
            return f"({self.int_expr(ty, d + 1)} {op} {self.int_expr(ty, d + 1)})"
        if r < 640:
            f = self.r.choice(["wrapping_add", "wrapping_sub", "wrapping_mul", "saturating_add", "saturating_sub",
                               "saturating_mul", "bit_and", "bit_or", "bit_xor"])
            return f"{f}({self.int_expr(ty, d + 1)}, {self.int_expr(ty, d + 1)})"
        if r < 680:
            f = self.r.choice(["shift_left", "shift_right"])
            width = WIDTHS[ty][2]
            if self.r.chance(850):
                count = str(self.r.randint(0, width - 1)) + ("" if ty == "int" else ty)
            else:
                count = self.int_expr(ty, d + 1)
            return f"{f}({self.int_expr(ty, d + 1)}, {count})"
        if r < 700:
            return f"bit_not({self.int_expr(ty, d + 1)})"
        if r < 730 and WIDTHS[ty][0] < 0:
            return f"(-{self.int_expr(ty, d + 1)})"
        if r < 820:
            other = self.r.choice([t for t in WIDTHS if t != ty])
            return f"{ty}({self.int_expr(other, d + 1)})"
        if r < 840 and ty != "int":
            return f"{ty}(int({self.float_expr(d + 1)}))"
        if r < 860 and ty == "i32" and self.of("R"):
            return f"{self.r.choice(self.of('R'))}.n"
        return self.leaf(ty)

    def int_only(self, d: int, r: int) -> str | None:
        """The `int` expressions that read collections, records, unions and the helpers."""
        lists = self.of("int[]")
        if r < 30 and lists:
            return f"len({self.r.choice(lists)})"
        if r < 90 and lists:
            return f"{self.r.choice(lists)}[{self.index(d)}]"
        if r < 110 and self.of("P"):
            return f"{self.r.choice(self.of('P'))}.a"
        if r < 125 and self.of("P"):
            return f"len({self.r.choice(self.of('P'))}.b)"
        if r < 140 and self.of("opt"):
            return f"pick({self.r.choice(self.of('opt'))})"
        if r < 160 and lists:
            return f"total({self.r.choice(lists)})"
        if r < 180 and self.of("Sh"):
            return f"score({self.r.choice(self.of('Sh'))})"
        if r < 195:
            return f"fib({self.int_expr('int', d + 1)} % 11)"
        if r < 205:
            return f"sum_to({self.int_expr('int', d + 1)} % 40)"
        if r < 225:
            return f"or_else({self.int_expr('int', d + 1)}, {self.int_expr('int', d + 1)}, {self.leaf('int')})"
        if r < 245:
            return f"pick2({self.int_expr('int', d + 1)}, {self.int_expr('int', d + 1)}, {self.bool_expr(d + 1)})"
        if r < 260 and lists:
            return f"first_or({self.r.choice(lists)}, {self.leaf('int')})"
        if r < 285 and self.of("dict"):
            dd = self.r.choice(self.of("dict"))
            return self.r.choice([f"len({dd})", f"dicts.get({dd}, {self.r.choice(KEYS)}, {self.leaf('int')})",
                                  f"{dd}[{self.r.choice(KEYS)}]", f"key_sum({dd})"])
        if r < 300 and self.of("set"):
            return f"len({self.r.choice(self.of('set'))})"
        if r < 320 and self.of("str"):
            s = self.r.choice(self.of("str"))
            return self.r.choice([f"len({s})", f"int({s}[{self.r.randint(0, 2)}])"])
        if r < 330 and self.of("R"):
            return f"rlen({self.r.choice(self.of('R'))})"
        if r < 345 and self.of("Q"):
            q = self.r.choice(self.of("Q"))
            return f"({q}.x - {q}.y)"
        if r < 352 and self.of("Bx"):
            return f"bsum({self.r.choice(self.of('Bx'))})"
        if r < 360 and self.of("P[]"):
            rl = self.r.choice(self.of("P[]"))
            return f"({rl}[0].a + len({rl}[1].b) + total({rl}[0].b))"
        if r < 375 and self.of("str[]"):
            return f"len({self.r.choice(self.of('str[]'))})"
        if r < 390:
            return f"int({self.int_expr(self.r.choice(FIXED), d + 1)})"
        return None

    def index(self, d: int) -> str:
        if self.r.chance(700):
            return str(self.r.randint(0, 3))
        e = self.int_expr("int", d + 1)
        if not re.search(r"\b[a-z]+_\d+\b", e):  # a constant negative index is refused (`E_NEGATIVE_INDEX_REMOVED`)
            return str(self.r.randint(0, 3))
        return e

    def float_expr(self, d: int) -> str:
        if d > 2 or self.r.chance(300):
            return self.leaf("float")
        r = self.r.below(100)
        if r < 65:
            op = self.r.choice(["+", "-", "*", "/"])
            return f"({self.float_expr(d + 1)} {op} {self.float_expr(d + 1)})"
        if r < 85:
            return f"float({self.int_expr('int', d + 1)})"
        if r < 92 and self.of("R"):
            return f"{self.r.choice(self.of('R'))}.f"
        return self.leaf("float")

    def bool_expr(self, d: int) -> str:
        if d > 2 or self.r.chance(150):
            return self.leaf("bool")
        r = self.r.below(100)
        if r < 55:
            ty = self.r.choice(["int", "int", "int"] + FIXED[:3] + ["float", "str"])
            op = self.r.choice(["<", "<=", "==", "!=", ">", ">="])
            return f"({self.expr(ty, d + 1)} {op} {self.expr(ty, d + 1)})"
        if r < 75:
            op = self.r.choice(["and", "or"])
            return f"({self.bool_expr(d + 1)} {op} {self.bool_expr(d + 1)})"
        if r < 82:
            return f"(not {self.bool_expr(d + 1)})"
        if r < 90 and self.of("set"):
            return f"({self.int_expr('int', d + 1)} in {self.r.choice(self.of('set'))})"
        if r < 93 and self.of("dict"):
            return f"({self.r.choice(KEYS)} in {self.r.choice(self.of('dict'))})"
        if r < 97:
            return self.r.choice(["yes()", "no()", f"pos({self.int_expr('int', d + 1)})"])
        return self.leaf("bool")

    def flat_bool(self) -> str:
        """A chain of `and`, `or` and `not` without parentheses, read by precedence, over calls and comparisons."""
        terms = []
        for _ in range(self.r.randint(2, 4)):
            atom = self.r.choice(["yes()", "no()", "yes()", "no()", f"pos({self.int_expr('int', 2)})",
                                  f"{self.int_expr('int', 2)} < {self.int_expr('int', 2)}", "True", "False"])
            terms.append(("not " if self.r.chance(400) else "") + atom)
        out = terms[0]
        for t in terms[1:]:
            out += f" {self.r.choice(['and', 'or', 'and'])} {t}"
        return out

    def str_expr(self, d: int) -> str:
        if d > 2 or self.r.chance(300):
            return self.leaf("str")
        r = self.r.below(100)
        if r < 30:
            return f"({self.str_expr(d + 1)} + {self.str_expr(d + 1)})"
        if r < 55:
            ty = self.r.choice(["int", "int", "float", "bool"] + FIXED)
            return f"str({self.expr(ty, d + 1)})"
        if r < 70 and self.of("str"):
            a, b = self.r.randint(0, 3), self.r.randint(0, 6)
            return f"{self.r.choice(self.of('str'))}[{a}:{b}]"
        if r < 78:
            return f"pick2({self.str_expr(d + 1)}, {self.str_expr(d + 1)}, {self.bool_expr(d + 1)})"
        if r < 84 and self.of("str[]"):
            return f"first_or({self.r.choice(self.of('str[]'))}, {self.text_literal()})"
        if r < 90 and self.of("R"):
            return f"{self.r.choice(self.of('R'))}.t"
        return self.leaf("str")

    def edge(self, ty: str) -> str:
        """An operation at its type's limit, whose operands are constants or a name holding one: it may always trap."""
        lo, hi, bits = WIDTHS[ty]
        sfx = "" if ty == "int" else ty
        k = self.r.below(6)
        if k == 0:
            return f"({hi}{sfx} + {self.r.randint(0, 2)}{sfx})"
        if k == 1:
            return f"({lo}{sfx} - {self.r.randint(0, 2)}{sfx})" if lo < 0 else f"({self.r.randint(0, 2)}{sfx} - {self.r.randint(0, 3)}{sfx})"
        if k == 2:
            return f"({hi // 2 + 1}{sfx} * {self.r.randint(1, 3)}{sfx})"
        if k == 3 and ty != "int":
            v = self.r.choice([hi, hi + 1, lo - 1, lo, -1, 1 << 40])
            return f"{ty}({min(max(v, WIDTHS['int'][0]), WIDTHS['int'][1])})"  # an unsuffixed operand is an `int`
        if k == 4:
            return f"(({hi}{sfx} - {self.r.randint(0, 3)}{sfx}) + {self.r.randint(1, 4)}{sfx})"
        return self.int_literal(ty)

    def element(self, d: int) -> str:
        """A list element: sometimes an operation at its limit (lane FX3's class: lists hold their elements' facts)."""
        if self.r.chance(100):
            return self.edge("int") if self.r.chance(500) else f"int({self.edge(self.r.choice(FIXED))})"
        return self.int_expr("int", d)

    def list_literal(self, d: int = 1) -> str:
        return "[" + ", ".join(self.element(d) for _ in range(self.r.randint(0, 3))) + "]"

    # ---- statements --------------------------------------------------------------------------------------------
    def block(self, ind: int, depth: int, in_loop: bool) -> list[str]:
        saved = self.snapshot()
        lines: list[str] = []
        for _ in range(self.r.randint(1, 4 if depth == 0 else 3)):
            lines += self.stmt(ind, depth, in_loop)
        self.restore(saved)  # names declared in a block disappear at its end
        return lines

    def scalar_decl(self, p: str) -> list[str]:
        ty = self.r.choice(["int"] * 6 + FIXED + ["float", "bool", "str", "str"])
        v = self.fresh("v")
        line = f"{p}mut {v}: {ty} = {self.value(ty)}" if ty != "int" or self.r.chance(500) else f"{p}mut {v} = {self.value(ty)}"
        self.declare(v, ty)
        return [line]

    def stmt(self, ind: int, depth: int, in_loop: bool) -> list[str]:
        p = "    " * ind
        if not self.of("int"):
            return self.scalar_decl(p)
        r = self.r.below(1000)
        if r < 120:
            return self.scalar_decl(p)
        if r < 230:
            ty = self.r.choice(["int"] * 5 + FIXED + ["float", "bool", "str"])
            targets = self.writable(ty)
            if targets:
                return [f"{p}{self.r.choice(targets)} = {self.value(ty)}"]
            return self.scalar_decl(p)
        if r < 400:
            out = self.data_stmt(p)
            if out:
                return out
        if depth >= 2 or r < 450:
            return self.scalar_decl(p)
        if r < 560:
            out = [f"{p}if {self.bool_expr(1)}:"] + self.block(ind + 1, depth + 1, in_loop)
            if self.r.chance(500):
                out += [f"{p}else:"] + self.block(ind + 1, depth + 1, in_loop)
            return out
        if r < 650:
            i = self.fresh("i")
            a, b = self.r.randint(-2, 3), self.r.randint(0, 7)
            head = f"{p}for {i} in range({a}, {b}):" if self.r.chance(700) else f"{p}for {i} in range({b}, {a}, -1):"
            saved = self.snapshot()
            self.declare(i, "int", readonly=True)
            body = self.block(ind + 1, depth + 1, True) + self.exit(ind + 1)
            self.restore(saved)
            return [head] + body
        if r < 760:
            return self.walk(p, ind, depth)
        if r < 820:
            c = self.fresh("c")
            k = self.r.randint(0, 6)
            self.declare(c, "int", readonly=True)  # only the loop's own increment writes it
            body = [f"{p}    {c} = {c} + 1"] + self.block(ind + 1, depth + 1, True) + self.exit(ind + 1)
            return [f"{p}mut {c} = 0", f"{p}while {c} < {k}:"] + body
        if r < 880 and self.of("opt"):
            o = self.r.choice(self.of("opt"))
            v = self.fresh("m")
            saved = self.snapshot()
            self.declare(v, "int", readonly=True)
            some = self.block(ind + 2, depth + 1, in_loop)
            self.restore(saved)
            none = self.block(ind + 2, depth + 1, in_loop)
            return [f"{p}match {o}:", f"{p}    case Some({v}):"] + some + [f"{p}    case None:"] + none
        if r < 930:
            v, e = self.fresh("ok"), self.fresh("er")
            head = [f"{p}match chk({self.int_expr('int', 1)}):", f"{p}    case Ok({v}):"]
            saved = self.snapshot()
            self.declare(v, "int", readonly=True)
            ok = self.block(ind + 2, depth + 1, in_loop)
            self.restore(saved)
            self.declare(e, "int", readonly=True)
            er = self.block(ind + 2, depth + 1, in_loop)
            self.restore(saved)
            return head + ok + [f"{p}    case Err({e}):"] + er
        if r < 955 and self.of("Sh"):
            return self.match_shape(p, ind, depth, in_loop)
        if r < 980 and self.writable("Bx"):
            return self.match_box(p)
        if r < 990 and in_loop:
            return [f"{p}if {self.bool_expr(1)}:", f"{p}    {self.r.choice(['break', 'continue'])}"]
        return self.scalar_decl(p)

    def walk(self, p: str, ind: int, depth: int) -> list[str]:
        """A `for` over a collection, which must not change while the loop walks it."""
        kinds = [k for k in ("int[]", "set", "dict", "str[]", "str") if self.of(k)]
        if not kinds:
            return self.scalar_decl(p)
        kind = self.r.choice(kinds)
        xs = self.r.choice(self.of(kind))
        x = self.fresh("x")
        element = {"int[]": "int", "set": "int", "dict": "str", "str[]": "str", "str": "int"}[kind]
        saved, was = self.snapshot(), xs in self.frozen
        self.frozen.add(xs)
        self.declare(x, element, readonly=True)
        body = self.block(ind + 1, depth + 1, True) + self.exit(ind + 1)
        self.restore(saved)
        if not was:
            self.frozen.discard(xs)
        walked = f"strings.bytes({xs})" if kind == "str" else xs
        return [f"{p}for {x} in {walked}:"] + body

    def match_shape(self, p: str, ind: int, depth: int, in_loop: bool) -> list[str]:
        sh = self.r.choice(self.of("Sh"))
        v, a, b = self.fresh("m"), self.fresh("m"), self.fresh("m")
        saved = self.snapshot()
        self.declare(v, "int", readonly=True)
        arm1 = self.block(ind + 2, depth + 1, in_loop)
        self.restore(saved)
        self.declare(a, "int", readonly=True)
        self.declare(b, "int", readonly=True)
        arm2 = self.block(ind + 2, depth + 1, in_loop)
        self.restore(saved)
        return ([f"{p}match {sh}:", f"{p}    case rad(value={v}):"] + arm1 + [f"{p}    case pt(x={a}, y={b}):"] + arm2
                + [f"{p}    case empty:", f"{p}        pass"])

    def match_box(self, p: str) -> list[str]:
        """`match mut` on a local: the binding writes into the payload, and nothing else may name the local in the arm."""
        bx = self.r.choice(self.writable("Bx"))
        pv = self.fresh("pv")
        hidden = self.snapshot()
        self.vars = {k: [n for n in v if n != bx] for k, v in self.vars.items()}
        e1, e2 = self.int_expr("int", 1), self.int_expr("int", 1)
        self.restore(hidden)
        arm = self.r.choice([[f"{p}        {pv}.a = {pv}.a + {e1}"], [f"{p}        append(mut {pv}.b, {e1})"],
                             [f"{p}        {pv}.a = {e1}", f"{p}        append(mut {pv}.b, {e2})"]])
        return [f"{p}match mut {bx}:", f"{p}    case box(value={pv}):"] + arm + [f"{p}    case none:", f"{p}        pass"]

    def data_stmt(self, p: str) -> list[str] | None:
        """Declarations and changes of collections, records, options and unions."""
        k = self.r.below(30)
        lists, ml = self.of("int[]"), self.writable("int[]")
        if k == 0 or (k < 3 and not lists):
            v = self.fresh("l")
            line = f"{p}mut {v}: int[] = {self.list_literal()}"
            self.declare(v, "int[]")
            return [line]
        if k == 1 and ml:
            return [f"{p}append(mut {self.r.choice(ml)}, {self.element(0)})"]
        if k == 2 and ml:
            return [f"{p}{self.r.choice(ml)}[{self.index(1)}] = {self.int_expr('int', 0)}"]
        if k == 3 and ml:
            return [f"{p}helper_mut(mut {self.r.choice(ml)}, {self.int_expr('int', 0)})"]
        if k == 4 and ml:
            v = self.fresh("t")
            src = self.r.choice(ml)
            self.declare(v, "int[]", readonly=True)
            return [f"{p}const {v} = take(mut {src})"]
        if k == 5 and ml:
            v = self.fresh("t")
            src = self.r.choice(ml)
            line = f"{p}const {v} = exchange(mut {src}, {self.list_literal()})"
            self.declare(v, "int[]", readonly=True)
            return [line]
        if k == 6 and lists:
            v = self.fresh("r")
            line = f"{p}mut {v} = P(a={self.int_expr('int', 0)}, b=copy({self.r.choice(lists)}))"
            self.declare(v, "P")
            return [line]
        if k == 7 and self.writable("P"):
            x = self.r.choice(self.writable("P"))
            return self.r.choice([[f"{p}{x}.a = {self.int_expr('int', 0)}"], [f"{p}helper_rec(mut {x}, {self.int_expr('int', 0)})"],
                                  [f"{p}append(mut {x}.b, {self.element(0)})"]])
        if k == 8:
            v = self.fresh("o")
            value = f"Some({self.int_expr('int', 0)})" if self.r.chance(700) else "None"
            self.declare(v, "opt")
            return [f"{p}mut {v}: int? = {value}"]
        if k == 9 and self.writable("opt"):
            v = self.fresh("o")
            src = self.r.choice(self.writable("opt"))
            self.declare(v, "opt", readonly=True)
            return [f"{p}const {v} = take(mut {src})"]
        if k == 10:
            v = self.fresh("d")
            items = ", ".join(f"{key}: {self.int_expr('int', 1)}" for key in KEYS[: self.r.randint(0, 3)])
            self.declare(v, "dict")
            return [f"{p}mut {v}: dict[str, int] = {{{items}}}"]
        if k == 11 and self.writable("dict"):
            dd = self.r.choice(self.writable("dict"))
            return self.r.choice([[f"{p}{dd}[{self.r.choice(KEYS)}] = {self.int_expr('int', 0)}"],
                                  [f"{p}dicts.add(mut {dd}, {self.r.choice(KEYS)}, {self.int_expr('int', 1)})"]])
        if k == 12:
            v = self.fresh("s")
            items = ", ".join(self.int_expr("int", 1) for _ in range(self.r.randint(1, 3)))
            self.declare(v, "set")
            return [f"{p}mut {v}: set[int] = {{{items}}}"]
        if k == 13 and self.writable("set"):
            st = self.r.choice(self.writable("set"))
            f = self.r.choice(["add", "discard"])
            return [f"{p}sets.{f}(mut {st}, {self.int_expr('int', 1)})"]
        if k == 14:
            v = self.fresh("q")
            line = f"{p}mut {v} = Q(x={self.int_expr('int', 0)}, y={self.int_expr('int', 0)})"
            self.declare(v, "Q")
            return [line]
        if k == 15 and self.writable("Q"):
            q = self.r.choice(self.writable("Q"))
            return self.r.choice([[f"{p}{q} = Q(x={q}.y, y={q}.x + {self.int_expr('int', 2)})"], [f"{p}{q} = swapq({q})"]])
        if k == 16 and lists:
            v = self.fresh("rl")
            line = (f"{p}mut {v}: P[] = [P(a={self.int_expr('int', 1)}, b=copy({self.r.choice(lists)})), "
                    f"P(a={self.int_expr('int', 1)}, b=[])]")
            self.declare(v, "P[]")
            return [line]
        if k == 17 and self.writable("P[]"):
            rl = self.r.choice(self.writable("P[]"))
            c = self.r.below(3)
            if c == 0:
                return [f"{p}bump_first(mut {rl}, {self.int_expr('int', 1)})"]
            if c == 1:
                return [f"{p}{rl}[{self.r.randint(0, 1)}].a = {rl}[0].a + {self.int_expr('int', 2)}"]
            return [f"{p}append(mut {rl}[1].b, len({rl}[0].b))"]
        if k == 18:
            v = self.fresh("sh")
            c = self.r.below(3)
            value = ["Sh.empty", f"Sh.rad(value={self.int_expr('int', 1)})",
                     f"Sh.pt(x={self.int_expr('int', 1)}, y={self.int_expr('int', 1)})"][c]
            self.declare(v, "Sh")
            return [f"{p}mut {v}: Sh = {value}"]
        if k == 19 and self.writable("Sh"):
            return [f"{p}grow(mut {self.r.choice(self.writable('Sh'))}, {self.int_expr('int', 1)})"]
        if k == 20 and self.writable("int"):
            return [f"{p}bump(mut {self.r.choice(self.writable('int'))}, {self.int_expr('int', 1)})"]
        if k == 21:
            v = self.fresh("rr")
            line = f"{p}mut {v} = R(n={self.int_expr('i32', 1)}, t={self.value('str', 1)}, f={self.float_expr(1)})"
            self.declare(v, "R")
            return [line]
        if k == 22 and self.writable("R"):
            x = self.r.choice(self.writable("R"))
            return self.r.choice([[f"{p}{x}.n = {self.int_expr('i32', 1)}"], [f"{p}{x}.t = {self.value('str', 1)}"],
                                  [f"{p}{x}.f = {self.float_expr(1)}"]])
        if k == 23:
            v = self.fresh("sl")
            items = ", ".join(self.value("str", 1) for _ in range(self.r.randint(0, 3)))
            self.declare(v, "str[]")
            return [f"{p}mut {v}: str[] = [{items}]"]
        if k == 24 and self.writable("str[]"):
            return [f"{p}append(mut {self.r.choice(self.writable('str[]'))}, {self.value('str', 1)})"]
        if k == 25 and self.of("P"):
            v = self.fresh("t")
            src = self.r.choice(self.writable("P") or [""])
            if not src:
                return None
            self.declare(v, "int[]", readonly=True)
            return [f"{p}const {v} = take(mut {src}.b)"]
        if k == 26:
            return [f"{p}assert {self.bool_expr(1)}"] if self.r.chance(300) else None
        if k == 27 and lists:
            v = self.fresh("bx")
            value = f"Bx.box(value=P(a={self.int_expr('int', 1)}, b=copy({self.r.choice(lists)})))" if self.r.chance(800) else "Bx.none"
            self.declare(v, "Bx")
            return [f"{p}mut {v}: Bx = {value}"]
        return None

    def exit(self, ind: int) -> list[str]:
        if self.r.chance(300):
            p = "    " * ind
            return [f"{p}if {self.bool_expr(1)}:", f"{p}    {self.r.choice(['break', 'continue'])}"]
        return []

    def function(self, k: int) -> tuple[str, str]:
        """`gen_K` and its return type."""
        self.reset()
        ty = self.r.choice(RETURN_TYPES)
        if ty == "bool" and self.r.chance(500):
            # one expression, which the test writes again as its own result (the verdict must be what `main` prints)
            return f"func gen_{k}() -> bool:\n    return {self.flat_bool()}\n", ty
        body: list[str] = []
        for _ in range(self.r.randint(2, 7)):
            body += self.stmt(1, 0, False)
        if ty == "int":
            parts = list(self.of("int")[-3:]) + [f"len({x})" for x in self.of("int[]")[-2:]]
            parts += [f"{x}.a" for x in self.of("P")[-1:]] + [f"score({x})" for x in self.of("Sh")[-1:]]
            result = " + ".join(parts[-4:]) if parts else self.int_expr("int", 1)
        else:
            result = self.value(ty, 1)
        return f"func gen_{k}() -> {ty}:\n" + "\n".join(body) + f"\n    return {result}\n", ty


def program(seed: int, functions: int = FUNCTIONS) -> str:
    """The program of a seed: the helpers, `functions` generated functions and a `main` that prints the one `args[0]` names."""
    g = Gen(program_rng(seed))
    parts = [g.function(k)[0] for k in range(functions)]
    return HEADER + "\n\n" + "\n\n".join(parts) + "\n\n" + main_source(range(functions))


def main_source(ks) -> str:
    lines = ["func main(args: str[], out: Stream) -> int:", "    const which = args[0]"]
    for k in ks:
        lines += [f'    if which == "{k}":', f"        print(out, gen_{k}())"]
    lines.append("    return 0")
    return "\n".join(lines) + "\n"


# ---- outcomes ----------------------------------------------------------------------------------------------------------
@dataclass(frozen=True)
class Outcome:
    """What one mode made of one function: `value TEXT`, `trap CODE (DETAIL) at L:C`, `internal CODE`, `refused CODES`,
    `crash ...`, or `absent` (the mode produced nothing for it)."""

    kind: str
    detail: str

    def __str__(self) -> str:
        return f"{self.kind} {self.detail}".strip()

    @property
    def fault(self) -> bool:
        return self.kind in ("internal", "crash", "refused")


TRAP_LINE = re.compile(r"^\S*?:(\d+):(\d+): error\[(R_[A-Z0-9_]+)\]: native execution failed:? ?(.*)$", re.M)
TEST_TRAP = re.compile(r"^(R_[A-Z0-9_]+):? ?(.*?)\n\s+in \S+ at \S*?:(\d+):(\d+)", re.S)
ERROR_CODE = re.compile(r"error\[(E_[A-Z0-9_]+)\]")


PANIC = re.compile(r"panic: (.*)")
FRAME = re.compile(r"(src/[\w/]+\.zig:\d+):\d+: 0x[0-9a-f]+ in (\w+)")


def build_failure(text: str) -> Outcome:
    panic = PANIC.search(text)
    if panic:
        frame = FRAME.search(text)
        where = f" at {frame.group(1)} in {frame.group(2)}" if frame else ""
        return Outcome("crash", f"compiler-panic: {panic.group(1).strip()}{where}")
    if "Segmentation fault" in text or "General protection" in text:
        return Outcome("crash", f"compiler-fault: {first_line(text)}")
    codes = list(dict.fromkeys(ERROR_CODE.findall(text)))
    internal = [c for c in codes if c in INTERNAL_CODES]
    if internal or "internal compiler error" in text or not codes:
        return Outcome("internal", " ".join(internal) or first_line(text))
    return Outcome("refused", " ".join(codes))


def first_line(text: str) -> str:
    for line in text.splitlines():
        if line.strip():
            return line.strip()[:200]
    return "(no output)"


def run_outcome(proc: subprocess.CompletedProcess) -> Outcome:
    if proc.returncode == 0:
        return Outcome("value", proc.stdout.rstrip("\n"))
    if proc.returncode < 0:
        return Outcome("crash", f"signal {-proc.returncode}")
    m = TRAP_LINE.search(proc.stderr)
    if proc.returncode == 1 and m:
        line, col, code, detail = m.groups()
        return Outcome("trap", f"{code} {detail or ''} at {line}:{col}".replace("  ", " "))
    return Outcome("crash", f"exit {proc.returncode}: {first_line(proc.stderr)}")


def test_outcome(entry: dict | None, expected: Outcome, boolean: bool) -> Outcome:
    """A test's verdict as an outcome. A `bool` function's test returns its value, so its verdict is the value."""
    if entry is None:
        return Outcome("absent", "")
    status, reason = entry.get("status"), entry.get("reason", "")
    if status == "passed":
        if boolean:
            return Outcome("value", "True")
        return expected if expected.kind == "value" else Outcome("value", "(passed)")
    if status == "failed":
        if reason.startswith("build error"):
            return build_failure(reason)
        if reason.startswith("expected true, got false"):
            return Outcome("value", "False" if boolean else "(differs)")
        m = TEST_TRAP.match(reason)
        if m:
            code, detail, line, col = m.groups()
            return Outcome("trap", f"{code} {detail or ''} at {line}:{col}".replace("  ", " "))
        return Outcome("crash", first_line(reason))
    return Outcome("crash", f"{status}: {first_line(reason)}")


def text_literal(text: str) -> str:
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


FUNCTION = re.compile(r"^func gen_(\d+)\(\) -> (\S+):\n((?:    .*\n?)+)", re.M)


def signatures(source: str) -> dict[int, tuple[str, str | None]]:
    """Each `gen_K`'s return type and, when its body is one `return E`, the expression `E`."""
    out = {}
    for m in FUNCTION.finditer(source):
        body = m.group(3).rstrip("\n").split("\n")
        direct = body[0][len("    return "):] if len(body) == 1 and body[0].startswith("    return ") else None
        out[int(m.group(1))] = (m.group(2), direct)
    return out


def direct_lines(text: str) -> dict[int, tuple[int, int]]:
    """For each `bool` function whose test writes its expression again: (the function's line, the test's line)."""
    lines = text.split("\n")
    where: dict[str, int] = {}
    for i, line in enumerate(lines):
        m = re.match(r"(?:public )?func (test_)?gen_(\d+)\(\)", line)
        if m and i + 1 < len(lines) and lines[i + 1].startswith("    return ") and (i + 2 >= len(lines) or not lines[i + 2].strip()):
            where[("t" if m.group(1) else "g") + m.group(2)] = i + 2
    return {int(key[1:]): (where["g" + key[1:]], line) for key, line in where.items()
            if key[0] == "t" and "g" + key[1:] in where and lines[line - 1] == lines[where["g" + key[1:]] - 1]}


def test_source(source: str, functions: list[int], expected: dict[int, Outcome]) -> str:
    """The test file: the program and, per function, a test that expects the reference outcome. A `bool` function's test
    returns the value itself (`return gen_K()`, or the function's one expression written in the test), so the verdict
    must be what `main` printed."""
    tests = []
    kinds = signatures(source)
    for k in functions:
        want = expected.get(k)
        ty, direct = kinds.get(k, ("int", None))
        if ty == "bool":
            body = f"return {direct}" if direct else f"return gen_{k}()"
        elif want is not None and want.kind == "value":
            body = f"return str(gen_{k}()) == {text_literal(want.detail)}"
        elif want is not None and want.kind == "trap":
            body = f'return str(gen_{k}()) == "(a trap)"'
        else:
            body = f"return str(gen_{k}()) == str(gen_{k}())"
        tests.append(f"public func test_gen_{k}() -> bool:\n    {body}\n")
    return source + "\n\n" + "\n\n".join(tests)


# ---- one program, three modes ------------------------------------------------------------------------------------------
class Runner:
    """Builds and runs programs with one compiler and private stores under `work`."""

    def __init__(self, compiler: str, work: Path, runtime_store: Path) -> None:
        self.compiler = compiler
        self.work = work
        self.env = dict(os.environ)
        stores = work / "stores"
        for name, sub in (("XDG_CACHE_HOME", "xdg"), ("TMPDIR", "tmp")):
            (stores / sub).mkdir(parents=True, exist_ok=True)
            self.env[name] = str(stores / sub)
        runtime_store.mkdir(parents=True, exist_ok=True)
        self.env["SELKA_CORE_RUNTIME_CACHE"] = str(runtime_store)
        for name in ("SELKA_STAGE_SHARED_CACHE", "SELKA_TEST_SHARED_CACHE", "SELKA_COMPILER_SHARED_CACHE"):
            self.env[name] = ""
        for name in list(self.env):
            if name.startswith("SELKA_ENGINE_") or name in ("SELKA_OPTIONS", "SELKA_MEMORY_LIMIT"):
                del self.env[name]

    def compile(self, args: list[str]) -> subprocess.CompletedProcess:
        return subprocess.run([self.compiler, *args], capture_output=True, text=True, env=self.env, timeout=BUILD_SECONDS)

    def execute(self, binary: Path, k: int) -> Outcome:
        def limit() -> None:
            resource.setrlimit(resource.RLIMIT_AS, (GUEST_ADDRESS_SPACE, GUEST_ADDRESS_SPACE))
        try:
            proc = subprocess.run([str(binary), str(k)], capture_output=True, text=True, env=self.env,
                                  timeout=RUN_SECONDS, preexec_fn=limit)
        except subprocess.TimeoutExpired:
            return Outcome("crash", f"timeout after {RUN_SECONDS} s")
        return run_outcome(proc)

    def binary_mode(self, source: Path, mode: str, flags: list[str], ks: list[int]) -> dict[int, Outcome]:
        binary = source.parent / f"gen-{mode}"
        proc = self.compile(["build", str(source), "-o", str(binary), "--cache-dir", str(source.parent / f"cache-{mode}"), *flags])
        if proc.returncode != 0:
            failure = build_failure(proc.stdout + proc.stderr)
            return {k: failure for k in ks}
        return {k: self.execute(binary, k) for k in ks}

    def warm(self) -> None:
        """Compile the C runtime of each mode once, before programs build in parallel and would each compile it."""
        dir = self.work / "warm"
        dir.mkdir(parents=True, exist_ok=True)
        (dir / "warm.selka").write_text("func main() -> int:\n    return 0\n\n\npublic func test_warm() -> bool:\n    return True\n")
        for mode, (test, flags) in MODES.items():
            out = ["--cache-dir", str(dir / f"cache-{mode}")] if test else ["-o", str(dir / f"warm-{mode}"), "--cache-dir", str(dir / f"cache-{mode}")]
            self.compile(["test" if test else "build", str(dir / "warm.selka"), *out, *flags])

    def test_mode(self, tests: Path, mode: str, flags: list[str], ks: list[int], reference: dict[int, Outcome]):
        proc = self.compile(["test", str(tests), "--json", "--cache-dir", str(tests.parent / f"cache-{mode}"), *flags])
        try:
            entries = {t["name"].split("::")[-1]: t for t in json.loads(proc.stdout)["tests"]}
        except (ValueError, KeyError):
            failure = build_failure(proc.stdout + proc.stderr)
            return {k: failure for k in ks}
        text = tests.read_text()
        kinds = signatures(text)
        moved = direct_lines(text)
        out = {}
        for k in ks:
            o = test_outcome(entries.get(f"test_gen_{k}"), reference.get(k, Outcome("absent", "")),
                             kinds.get(k, ("int", None))[0] == "bool")
            if k in moved and o.kind == "trap":  # a trap in the test's copy of the expression is a trap at the original
                o = Outcome("trap", re.sub(rf" at {moved[k][1]}:(\d+)$", rf" at {moved[k][0]}:\1", o.detail))
            out[k] = o
        return out

    def judge(self, dir: Path, source_text: str, ks: list[int], modes=None) -> dict[str, dict[int, Outcome]]:
        """Each mode's outcomes for the functions `ks` of one program written to `dir`."""
        modes = modes or BASE_MODES
        run_dir, test_dir = dir / "run", dir / "test"
        run_dir.mkdir(parents=True, exist_ok=True)
        test_dir.mkdir(parents=True, exist_ok=True)
        source = run_dir / "gen.selka"
        source.write_text(source_text)
        binaries = [m for m in modes if not MODES[m][0]]
        with concurrent.futures.ThreadPoolExecutor(len(binaries)) as pool:
            futures = {m: pool.submit(self.binary_mode, source, m, MODES[m][1], ks) for m in binaries}
            outcomes = {m: f.result() for m, f in futures.items()}
        plain = outcomes["plain"]
        reference = plain if not any(o.fault for o in plain.values()) else outcomes.get("release", plain)
        tests = test_dir / "gen.selka"
        tests.write_text(test_source(source_text, ks, reference))
        testers = [m for m in modes if MODES[m][0]]
        if not testers:
            return outcomes
        with concurrent.futures.ThreadPoolExecutor(len(testers)) as pool:
            futures = {m: pool.submit(self.test_mode, tests, m, MODES[m][1], ks, reference) for m in testers}
            outcomes.update({m: f.result() for m, f in futures.items()})
        return outcomes


def disagreements(outcomes: dict[str, dict[int, Outcome]], ks: list[int]) -> list[tuple[int, dict[str, Outcome]]]:
    bad = []
    for k in ks:
        per = {mode: outcomes[mode][k] for mode in outcomes}
        if any(o.fault for o in per.values()) or len(set(per.values())) > 1:
            bad.append((k, per))
    return bad


def signature(per: dict[str, Outcome]) -> str:
    """What a disagreement is, for reduction: the faults, or which modes split from which."""
    faults = sorted(f"{mode}:{o.kind}:{o.detail if o.kind == 'crash' else o.detail.split(' ')[0]}"
                    for mode, o in per.items() if o.fault)
    if faults:
        return " ".join(faults)
    groups: dict[Outcome, list[str]] = {}
    for mode, o in per.items():
        groups.setdefault(o, []).append(mode)
    return " | ".join(sorted("+".join(sorted(m)) for m in groups.values()))


def modes_of(seed: int, choice: str) -> tuple[str, ...]:
    """The modes a seed's program is judged in: the three base modes always, every mode on one seed in `EXTRA_EVERY`."""
    if choice == "all" or (choice == "sampled" and seed % EXTRA_EVERY == 0):
        return ALL_MODES
    return BASE_MODES


def check_seed(runner: Runner, seed: int, functions: int, choice: str = "sampled") -> tuple[int, list, int]:
    ks = list(range(functions))
    outcomes = runner.judge(runner.work / f"seed-{seed}", program(seed, functions), ks, modes_of(seed, choice))
    return seed, disagreements(outcomes, ks), sum(1 for k in ks if outcomes["plain"][k].kind == "trap")


def describe(seed: int, kept: Path, bad: list, functions: int) -> list[str]:
    """The lines of one failing program: a mode whose whole build failed once, then each function's split."""
    whole = {}
    if len(bad) == functions:
        for mode in bad[0][1]:
            seen = {per[mode] for _, per in bad}
            if len(seen) == 1 and next(iter(seen)).fault:
                whole[mode] = next(iter(seen))
    lines = [f"seed {seed} ({kept}): {mode} fails for the whole program: {o}" for mode, o in whole.items()]
    for k, per in bad:
        rest = {m: o for m, o in per.items() if m not in whole}
        if whole and not any(o.fault for o in rest.values()) and len(set(rest.values())) <= 1:
            continue
        lines.append(f"seed {seed} gen_{k} ({kept}): {signature(per)}")
        lines += [f"    {mode:10} {o}" for mode, o in per.items()]
    return lines


# ---- reduction ---------------------------------------------------------------------------------------------------------
def split_functions(text: str) -> tuple[str, dict[int, str]]:
    """The header and each `gen_K` of a generated program (`main` and tests dropped)."""
    head, _, rest = text.partition("\n\nfunc gen_")
    funcs: dict[int, str] = {}
    for chunk in ("func gen_" + rest).split("\n\n\n"):
        m = re.match(r"func gen_(\d+)\(", chunk)
        if m:
            funcs[int(m.group(1))] = chunk.strip("\n") + "\n"
    return head, funcs


def statement_spans(lines: list[str]) -> list[tuple[int, int]]:
    """Each statement of a function body as a line range with its nested block, innermost last."""
    spans = []
    for i, line in enumerate(lines):
        if i == 0 or not line.strip() or line.lstrip().startswith("return "):
            continue
        ind = len(line) - len(line.lstrip())
        j = i + 1
        while j < len(lines) and lines[j].strip() and len(lines[j]) - len(lines[j].lstrip()) > ind:
            j += 1
        spans.append((i, j))
    return spans


def blank_block(candidate: list[str], start: int) -> list[str]:
    """`candidate` with `pass` in the block that removing the statement at `start` left empty."""
    if start == 0 or not candidate[start - 1].rstrip().endswith(":"):
        return candidate
    ind = len(candidate[start - 1]) - len(candidate[start - 1].lstrip())
    nxt = candidate[start] if start < len(candidate) else ""
    if nxt.strip() and len(nxt) - len(nxt.lstrip()) > ind:
        return candidate
    return candidate[:start] + [" " * (ind + 4) + "pass"] + candidate[start:]


def reduce(runner: Runner, path: Path, out: Path, jobs: int) -> int:
    """Shrink the first function of `path` that fails on its own, statement by statement and helper by helper."""
    head, funcs = split_functions(path.read_text())
    pool = concurrent.futures.ThreadPoolExecutor(max(1, jobs))
    tries = 0

    modes = ALL_MODES

    def verdict(text: str, k: int) -> str | None:
        nonlocal tries
        tries += 1
        bad = disagreements(runner.judge(runner.work / f"try-{tries}", text, [k], modes), [k])
        return signature(bad[0][1]) if bad else None

    alone = list(pool.map(lambda k: (k, verdict(head + "\n\n" + funcs[k] + "\n\n" + main_source([k]), k)), sorted(funcs)))
    cases = [(k, v) for k, v in alone if v]
    if not cases:
        print(f"{path}: no function disagrees on its own")
        return 1
    k, want = cases[0]
    if "plain:crash:" in want or "plain:internal:" in want:
        # the plain build alone shows a fault of the compiler: shrink with that one mode (the reference of the others)
        modes = ("plain",)
        want = verdict(head + "\n\n" + funcs[k] + "\n\n" + main_source([k]), k)
    print(f"reducing gen_{k}: {want} (modes {', '.join(modes)})")
    imports, _, decls = head.partition("\n\n\n")
    units = [imports] + decls.strip("\n").split("\n\n\n")
    lines = funcs[k].rstrip("\n").split("\n")

    def text_of(units: list[str], lines: list[str]) -> str:
        return "\n\n\n".join(u for u in units if u) + "\n\n\n" + "\n".join(lines) + "\n\n\n" + main_source([k])

    while True:
        candidates = []
        for start, end in sorted(statement_spans(lines), key=lambda span: span[0] - span[1]):
            candidates.append((units, blank_block(lines[:start] + lines[end:], start)))
        for i in range(len(units)):
            if units[i]:
                candidates.append((units[:i] + [""] + units[i + 1:], lines))
        found = None
        for b in range(0, len(candidates), max(1, jobs)):
            batch = candidates[b:b + max(1, jobs)]
            results = list(pool.map(lambda c: verdict(text_of(*c), k) == want, batch))
            if any(results):
                found = batch[results.index(True)]
                break
        if found is None:
            break
        units, lines = found
    text = text_of(units, lines)
    out.write_text(text)
    final = runner.judge(runner.work / "final", text, [k], ALL_MODES)
    print(f"reduced gen_{k} to {len(text.splitlines())} lines in {tries} builds of three modes: {out}")
    for mode in final:
        print(f"  {mode:10} {final[mode][k]}")
    return 0


# ---- the command ---------------------------------------------------------------------------------------------------
def parse_seeds(text: str) -> list[int]:
    seeds: list[int] = []
    for part in text.split(","):
        a, sep, b = part.partition("..")
        seeds += list(range(int(a), int(b) + 1)) if sep else [int(a)]
    return seeds


print = functools.partial(print, flush=True)  # noqa: A001  (a hunt's log is read while it runs)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--compiler")
    ap.add_argument("--seeds", help="seeds A..B or A,B,C (default: the gate's fixed seeds)")
    ap.add_argument("--functions", type=int, default=FUNCTIONS, help="generated functions per program")
    ap.add_argument("--jobs", type=int, default=int(os.environ.get("SELKA_JOBS") or min(os.cpu_count() or 4, 6)))
    ap.add_argument("--work", help="the directory for programs and private stores (default: a temporary one, removed)")
    ap.add_argument("--keep", default=".selka-cache/mode-differential/kept", help="where failing programs are copied")
    ap.add_argument("--runtime-store", default=".selka-cache/mode-differential/runtime",
                    help="this action's own content-keyed store of compiled C runtime objects, kept between runs")
    ap.add_argument("--modes", choices=("sampled", "base", "all"), default="sampled",
                    help="sampled: plain, release and test, and every mode on one seed in %d" % EXTRA_EVERY)
    ap.add_argument("--reduce", metavar="FILE", help="shrink a failing program while its disagreement stays")
    ap.add_argument("--print", type=int, metavar="SEED", help="print the program of SEED and exit")
    a = ap.parse_args()
    if a.print is not None:
        sys.stdout.write(program(a.print, a.functions))
        return 0
    if not a.compiler:
        ap.error("--compiler is required")
    work = Path(a.work) if a.work else Path(tempfile.mkdtemp(prefix="mode-differential-"))
    work.mkdir(parents=True, exist_ok=True)
    runner = Runner(os.path.abspath(a.compiler), work.resolve(), Path(a.runtime_store).resolve())
    started = time.monotonic()
    try:
        if a.reduce:
            return reduce(runner, Path(a.reduce), Path(a.reduce).with_name("reduced.selka"), a.jobs)
        seeds = parse_seeds(a.seeds) if a.seeds else list(GATE_SEEDS)
        runner.warm()
        failures, traps = [], 0
        with concurrent.futures.ThreadPoolExecutor(max(1, a.jobs)) as pool:
            for seed, bad, trapped in pool.map(lambda s: check_seed(runner, s, a.functions, a.modes), seeds):
                traps += trapped
                if bad:
                    failures.append((seed, bad))
                    kept = Path(a.keep) / f"seed-{seed}"
                    shutil.rmtree(kept, ignore_errors=True)
                    shutil.copytree(work / f"seed-{seed}", kept, ignore=shutil.ignore_patterns("cache*", "gen-*"))
                if not a.work:
                    shutil.rmtree(work / f"seed-{seed}", ignore_errors=True)
        usage = resource.getrusage(resource.RUSAGE_CHILDREN)
        total = len(seeds) * a.functions
        print(f"mode differential: {len(seeds)} programs ({seeds[0]}..{seeds[-1]}), {total} functions, {traps} trap in the "
              f"plain build; {sum(len(b) for _, b in failures)} disagree in {len(failures)} programs; "
              f"{usage.ru_utime + usage.ru_stime:.1f} CPU-s, {time.monotonic() - started:.1f} s")
        for seed, bad in failures:
            kept = Path(a.keep) / f"seed-{seed}" / "run" / "gen.selka"
            for line in describe(seed, kept, bad, a.functions):
                print(line)
            print(f"    reproduce: python3 tests/mode_differential.py --compiler {a.compiler} --seeds {seed}..{seed}; "
                  f"shrink: --reduce {kept}")
        return 1 if failures else 0
    finally:
        if not a.work:
            shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
