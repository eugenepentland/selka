#!/usr/bin/env python3
"""Write the loop-range-facts trap corpus: one program per trap class, each
trap inside (or right at) a loop the lane versions, every loop running at
least 16 iterations so the guard is reached. Each prints a line first, so
stdout before the trap is compared too."""
import os

HERE = os.path.dirname(os.path.abspath(__file__))
PROGRAMS = {
    # The guard cannot prove xs[i + 1]: the original loop traps at i = 19.
    "index_past_end": """
def shifted(xs: list[int]) -> int:
    t = 0
    for i in range(len(xs)):
        t += xs[i + 1]
    return t


def main(out: Stream) -> int:
    out.print("start")
    return shifted([i for i in range(20)])
""",
    # Indices proven, the unbounded sum is not: it traps inside the copy.
    "sum_overflow_in_copy": """
def total(xs: list[int]) -> int:
    t = 0
    for i in range(len(xs)):
        t += xs[i]
    return t


def main(out: Stream) -> int:
    xs = [0 for _ in range(20)]
    xs[17] = 9223372036854775000
    xs[18] = 500
    xs[19] = 500
    out.print("start")
    return total(xs)
""",
    # Division by zero at i = 12, inside the copy.
    "division_in_copy": """
def ratio(xs: list[int]) -> int:
    t = 0
    for i in range(len(xs)):
        t += xs[i] // (i - 12)
    return t


def main(out: Stream) -> int:
    out.print("start")
    return ratio([i for i in range(20)])
""",
    # The counter's start is past the magnitude bound: the original counts
    # to the overflow.
    "accumulator_start_rejected": """
def count(xs: list[int], start: int) -> int:
    c = start
    for x in xs:
        if x > 0:
            c += 1
    return c


def main(out: Stream) -> int:
    out.print("start")
    return count([1 for _ in range(20)], 9223372036854775805)
""",
    # The row is one element short: the original loop traps at j = 19.
    "short_row": """
def kernel(c: mut list[list[float]], n: int) -> None:
    for j in range(n):
        c[1][j] = c[1][j] + 1.0


def main(out: Stream) -> int:
    c = [[0.0 for _ in range(20)], [0.0 for _ in range(19)]]
    out.print("start")
    kernel(mut c, 20)
    return 0
""",
    # A fixed array written at k - i with k past the end.
    "array_from_end_past_end": """
def reverse(values: mut [32]int, k: int) -> int:
    for i in range(20):
        values[k - i] = i
    return values[0]


def main(out: Stream) -> int:
    values: [32]int = [9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9]
    out.print(reverse(mut values, 31))
    out.print(reverse(mut values, 10))
    return reverse(mut values, 40)
""",
    # A product of counters whose leaf bound the guard rejects: the original
    # traps on the first product past 64 bits.
    "product_bound_rejected": """
def a(i: int, j: int) -> int:
    return (i + j) * (i + j + 1) // 2 + i + 1


def row(v: list[int], i: int) -> int:
    s = 0
    for j in range(len(v)):
        s = s + a(i, j) % 7 * v[j]
    return s


def main(out: Stream) -> int:
    v = [1 for _ in range(20)]
    out.print(row(v, 1000))
    return row(v, 3037000490)
""",
    # A comprehension fill whose element computation traps at i = 17.
    "fill_element_traps": """
def reciprocal(n: int) -> list[int]:
    return [100 // (i - 17) for i in range(n)]


def main(out: Stream) -> int:
    out.print(len(reciprocal(16)))
    return len(reciprocal(20))
""",
    # A float conversion inlined into the loop traps on an out-of-range value.
    "inlined_conversion": """
def scaled(x: int, factor: float) -> int:
    return int(float(x) * factor)


def total(xs: list[int], factor: float) -> int:
    t = 0
    for i in range(len(xs)):
        t += scaled(xs[i], factor)
    return t


def main(out: Stream) -> int:
    xs = [i for i in range(20)]
    out.print(total(xs, 2.5))
    return total(xs, 1e300)
""",
    # A while loop with a negative start and a step in a local: Python's
    # negative indices, no trap; then the step overflows.
    "while_step_overflow": """
def mark(flags: mut list[bool], j0: int, step: int, n: int) -> int:
    j = j0
    marked = 0
    while j <= n:
        flags[j % 40] = False
        marked += 1
        j = j + step
    return marked


def main(out: Stream) -> int:
    flags = [True for _ in range(40)]
    out.print(mark(mut flags, -9, 1, 30))
    return mark(mut flags, 9223372036854775000, 100, 9223372036854775800)
""",
}

for name, text in PROGRAMS.items():
    with open(os.path.join(HERE, name + ".my"), "w") as handle:
        handle.write(text.lstrip("\n"))
print(len(PROGRAMS), "programs")
