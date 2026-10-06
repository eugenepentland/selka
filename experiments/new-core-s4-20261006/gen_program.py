#!/usr/bin/env python3
"""Generate a synthetic multi-file mylang project for the S4 caching spike.

`gen_program.py N DIR` writes DIR/main.my plus DIR/p<k>.my files of 100 "modules"
each. A module is one record type and six functions named m<i>_*, using only
constructs the new core accepts at S3 Wave A: integer loops, lists, a str-keyed dict,
records, text concatenation and split. Every module calls the next one's helper, and
the last module of a file calls into the next file, so the whole-program passes see
cross-file inlining and caller-derived parameter ranges.
`--edit K` changes one constant in module K's `build` body, and `--grow K` adds a
statement with a new checked operation to module K's `score`; `--helper K` changes
module K's small public helper, which its caller (in the previous file, for the first
module of a file) inlines. These are the ripple test's edits.
"""
import argparse
import os

PER_FILE = 100

MODULE = """
record R{i}:
    id: int
    name: str
    values: list[int]

def m{i}_score(xs: list[int], bias: int) -> int:
    total = 0
    for x in xs:
        if x % 3 == 0:
            total += x * bias
        else:
            total -= x{grow}
    return total

def m{i}_build(n: int) -> list[int]:
    out: list[int] = []
    for j in range(n):
        out.append((j * {mul}) % 101)
    return out

def m{i}_count(words: list[str]) -> dict[str, int]:
    counts: dict[str, int] = {{}}
    for w in words:
        counts[w] = counts.get(w, 0) + 1
    return counts

def m{i}_label(r: R{i}) -> str:
    return r.name + ":" + str(r.id) + ":" + r.name

public def m{i}_helper(x: int) -> int:
    return x % {modulus} + {i}

def m{i}_run(seed: int) -> int:
    xs = m{i}_build(seed % 50 + 10)
    r = R{i}(seed, "m{i}", xs)
    s = m{i}_score(r.values, {bias})
    c = m{i}_count(m{i}_label(r).split(":"))
    return s + len(c) + {next}(s)
"""


def part(k: int, modules: int, edit: int | None, grow: int | None = None, helper: int | None = None) -> str:
    first, last = k * PER_FILE, min(modules, (k + 1) * PER_FILE)
    more = last < modules
    lines = [f"module p{k}\n"] + ([f"import p{k + 1}\n"] if more else [])
    for i in range(first, last):
        mul = 7 + i % 13 + (1000 if edit == i else 0)
        if i + 1 < last:
            target = f"m{i + 1}_helper"
        elif more:
            target = f"p{k + 1}.m{i + 1}_helper"
        else:
            target = f"m{i}_helper"
        extra = "\n        total += x // 7" if grow == i else ""
        lines.append(MODULE.format(i=i, mul=mul, bias=i % 5 + 1, next=target, grow=extra, modulus=999 if helper == i else 1000))
    body = [f"public def group{k}(seed: int) -> int:", "    total = 0"]
    body += [f"    total += m{i}_run(seed + {i}) % 1000" for i in range(first, last)]
    body.append("    return total")
    lines.append("\n" + "\n".join(body) + "\n")
    return "".join(lines)


def generate(modules: int, directory: str, edit: int | None, grow: int | None = None, helper: int | None = None) -> None:
    os.makedirs(directory, exist_ok=True)
    files = (modules + PER_FILE - 1) // PER_FILE
    for k in range(files):
        with open(os.path.join(directory, f"p{k}.my"), "w") as handle:
            handle.write(part(k, modules, edit, grow, helper))
    main = ["module main"] + [f"import p{k}" for k in range(files)]
    main += ["", "def main(out: Stream) -> int:", "    total = 0"]
    main += [f"    total += p{k}.group{k}({k + 1})" for k in range(files)]
    main += ["    out.print(total)", "    return 0", ""]
    with open(os.path.join(directory, "main.my"), "w") as handle:
        handle.write("\n".join(main))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("modules", type=int)
    parser.add_argument("directory")
    parser.add_argument("--edit", type=int)
    parser.add_argument("--grow", type=int, help="add a statement (a new checked operation) to module K")
    parser.add_argument("--helper", type=int, help="change module K's small public helper, which callers inline")
    args = parser.parse_args()
    generate(args.modules, args.directory, args.edit, args.grow, args.helper)
