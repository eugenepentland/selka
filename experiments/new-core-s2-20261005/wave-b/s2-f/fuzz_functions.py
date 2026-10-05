#!/usr/bin/env python3
"""Differential S2-F array/callback/stable-sort cases, using S1's qualified runner."""
import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]


def main():
    spec = importlib.util.spec_from_file_location("s1", ROOT / "experiments/new-core-s1-20261005/fuzz.py")
    harness = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(harness)

    class Gen:
        def __init__(self, rng, features):
            self.rng = rng

        def program(self):
            r = self.rng
            n = r.randrange(1, 10)
            values = ", ".join(str(r.randrange(-50, 51)) for _ in range(n))
            index = r.randrange(n)
            reverse = r.choice(["True", "False"])
            key = r.choice(["row_key", "lambda row: (row.key, row.text)", "lambda row: row.text"])
            scale, offset = r.randrange(1, 5), r.randrange(-9, 10)
            return f'''def first(x: int) -> int:
    return x * {scale} + {offset}


def second(x: int) -> int:
    return x * {scale + 1} - {offset}


def invoke(f: def(int) -> int, x: int) -> int:
    return f(x)


record Row:
    key: int
    ordinal: int
    text: str


def row_key(row: Row) -> int:
    return row.key


def replace(xs: mut [2]str, text: str):
    xs[-1] = text


def rewrite_last(xs: mut list[str], text: str):
    xs[-1] = text


def rewrite_first(xs: mut list[str], text: str):
    xs[0] = text


def main(args: list[str], out: Stream) -> int:
    seed = len(args[0]) if len(args) > 0 else 3
    f = first if seed % 2 == 0 else second
    fixed: [{n}]int = [{values}]
    saved = fixed
    fixed[{index - n}] = invoke(f, seed)
    words: [2]str = [str(seed), str(seed + 1)]
    words_saved = words
    replace(mut words, "gamma" + str(seed))
    listed = [words[0], words[1]]
    listed_saved = listed
    rewrite = rewrite_last if seed % 2 == 0 else rewrite_first
    rewrite(mut listed, "delta" + str(seed))
    rows: list[Row] = []
    for i in range({n}):
        rows.append(Row(key=fixed[i] % 4, ordinal=i, text=words[i % 2]))
    snapshot = rows
    rows.sort(key={key}, reverse={reverse})
    plain = [saved[i] for i in range({n})]
    plain.sort()
    total = 0
    for i in range({n}):
        total += rows[i].ordinal * (i + 1) + plain[i] + snapshot[i].key + fixed[i]
    out.print(total, words_saved[-1], words[-1], listed_saved[-1], listed[-1])
    return 0
'''

    harness.Gen = Gen
    return harness.main()


if __name__ == "__main__":
    raise SystemExit(main())
