#!/usr/bin/env python3
"""Dynamic repetition, nested aliases, mut loop returns and numeric buffers."""
import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def main():
    spec = importlib.util.spec_from_file_location("s1", ROOT / "experiments/new-core-s1-20261005/fuzz.py")
    harness = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(harness)

    class Gen:
        def __init__(self, rng, features):
            self.rng = rng

        def program(self):
            r = self.rng
            rows, width = r.randrange(1, 5), r.randrange(1, 6)
            value, number = r.randrange(-100, 101), r.randrange(-10**18, 10**18)
            decimal = r.choice(("-0.0", "1.5", "1e-30", "1e30", "-13.25"))
            return f'''def changed(w: int, n: int) -> int:
    grid = [[j for j in range(w)] for i in range(n)]
    saved = grid
    child = grid[0]
    _ = child.pop()
    _ = grid[n - 1].pop()
    grid[0].append({value})
    total = 0
    for j in range(w):
        total += saved[n - 1][j]
    return total + sum(grid[0]) + sum(grid[n - 1]) + sum(child)


def walk(xs: mut list[int], n: int) -> int:
    if n == 0:
        xs[0] = {value}
        return xs[0]
    while n > 0:
        xs[0] += n
        n -= 1
    return xs[0]


def main(args: list[str], out: Stream) -> int:
    width = {width} + (len(args[0]) % 3 if len(args) > 0 else 0)
    row = [0] * width
    repeated = [row] * {rows}
    saved = repeated
    saved_row = row
    repeated[{rows - 1}][width - 1] = {value}
    unique = [[j for j in range(width)] for i in range({rows})]
    unique[{rows - 1}][width - 1] += {value}
    cube = [[row], [row]]
    cube_saved = cube
    cube[1][0][0] = {value + 1}
    values = [0] * width
    values_saved = values
    result = walk(mut values, len(args))
    bytes_out = byte_buffer([])
    bytes_saved = bytes_out
    _ = bytes_out.append_int({number})
    _ = bytes_out.append_float({decimal})
    text = str({number}) + str({decimal})
    spelling = bytes(bytes_out) == text.encode()
    out.print(sum(repeated[{rows - 1}]), sum(saved[{rows - 1}]), sum(saved_row), sum(unique[{rows - 1}]), cube[1][0][0], cube_saved[1][0][0], result, values_saved[0], spelling, len(bytes(bytes_saved)), changed(width, {rows}))
    return 0
'''

    harness.Gen = Gen
    return harness.main()


if __name__ == "__main__":
    raise SystemExit(main())
