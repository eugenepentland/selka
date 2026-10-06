#!/usr/bin/env python3
"""Ownership fuzz: random programs that alias, append to and pass around lists of
`int`, `str` and `list[int]` (with early returns, branches and loops), built by the
old core (the oracle) and by the new core at debug, release and verify. Every new
build must print the oracle's stdout and exit status and, run with
MYL_CORE_LEAKCHECK=1, report no block live at exit.

Element writes and pops are left out until the values lane lowers them.

usage: rc_fuzz.py --cases N [--seed S] [--keep DIR] --mylang OLD --core NEW
"""
import argparse, os, random, subprocess, sys, tempfile

KINDS = ["int", "str", "row"]  # list[int], list[str], list[list[int]]
TYPE = {"int": "list[int]", "str": "list[str]", "row": "list[list[int]]"}


class Gen:
    def __init__(self, r):
        self.r = r
        self.n = 0

    def fresh(self, base):
        self.n += 1
        return "%s%d" % (base, self.n)

    def element(self, kind, ints):
        if kind == "int":
            return self.r.choice(ints + [str(self.r.randint(0, 9))])
        if kind == "str":
            return self.r.choice(['"a"', '"bc"', '"xyz"'])
        return "make_ints(%s)" % self.r.choice(ints + ["2", "3"])

    def block(self, lists, ints, depth, indent, out):
        pad = "    " * indent
        for _ in range(self.r.randint(2, 6)):
            choice = self.r.random()
            name, kind = self.r.choice(lists)
            if choice < 0.25:
                alias = self.fresh(kind[0] + "a")
                out.append(f"{pad}{alias} = {name}")
                lists.append((alias, kind))
            elif choice < 0.55:
                out.append(f"{pad}{name}.append({self.element(kind, ints)})")
            elif choice < 0.65:
                other = self.fresh(kind[0] + "g")
                out.append(f"{pad}{other} = grow_{kind}({name}, {self.r.choice(ints + ['1'])})")
                lists.append((other, kind))
            elif choice < 0.75 and kind == "row":
                inner = self.fresh("inner")
                out.append(f"{pad}if len({name}) > 0:")
                out.append(f"{pad}    {inner} = {name}[0]")
                out.append(f"{pad}    {inner}.append(5)")
                out.append(f"{pad}    acc = acc + len({inner}) + len({name}[0])")
            elif choice < 0.85 and depth > 0:
                out.append(f"{pad}for i{depth} in range({self.r.randint(0, 3)}):")
                self.block(list(lists), ints + [f"i{depth}"], depth - 1, indent + 1, out)
            elif choice < 0.92 and depth > 0:
                out.append(f"{pad}if len({name}) > {self.r.randint(0, 3)}:")
                self.block(list(lists), ints, depth - 1, indent + 1, out)
                if self.r.random() < 0.3:
                    out.append(f"{pad}    return acc + len({name})")
            else:
                out.append(f"{pad}acc = acc + len({name})" + (f" + len({name}[0])" if kind == "row" and False else ""))

    def program(self):
        lines = [
            "def make_ints(n: int) -> list[int]:",
            "    out: list[int] = []",
            "    for i in range(n):",
            "        out.append(i)",
            "    return out",
            "",
        ]
        for kind in KINDS:
            lines += [
                f"def grow_{kind}(xs: {TYPE[kind]}, n: int) -> {TYPE[kind]}:",
                "    ys = xs",
                "    if n > 1:",
                "        return xs",
                f"    ys.append({self.element(kind, ['n'])})",
                "    return ys",
                "",
            ]
        lines += ["def body(seed: int, out: Stream) -> int:", "    acc = 0"]
        lists = []
        for kind in KINDS:
            name = self.fresh(kind[0] + "l")
            lines.append(f"    {name}: {TYPE[kind]} = []")
            lines.append(f"    {name}.append({self.element(kind, ['seed'])})")
            lists.append((name, kind))
        self.block(lists, ["seed"], 2, 1, lines)
        for name, kind in lists:
            if kind == "str":
                lines.append(f"    if len({name}) > 0:")
                lines.append(f"        out.print({name}[len({name}) - 1])")
            lines.append(f"    acc = acc + len({name})")
        lines += ["    return acc", "", "def main(args: list[str], out: Stream) -> int:",
                  "    out.print(body(len(args), out))", "    return 0", ""]
        return "\n".join(lines)


def run(argv, env=None):
    done = subprocess.run(argv, capture_output=True, text=True, env=env, timeout=30)
    return done.stdout, done.returncode, done.stderr


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cases", type=int, default=50)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--keep")
    ap.add_argument("--mylang", required=True)
    ap.add_argument("--core", required=True)
    args = ap.parse_args()
    work = args.keep or tempfile.mkdtemp(prefix="rc-fuzz.", dir=os.environ.get("TMPDIR"))
    os.makedirs(work, exist_ok=True)
    env = dict(os.environ, MYL_CORE_LEAKCHECK="1")
    rng = random.Random(args.seed)
    stats = {"cases": 0, "refused": 0, "rejected": 0, "compared": 0, "mismatch": 0}
    for case in range(args.cases):
        source = os.path.join(work, f"case{case}.my")
        with open(source, "w") as f:
            f.write(Gen(rng).program())
        stats["cases"] += 1
        old = os.path.join(work, f"case{case}-old")
        built = subprocess.run([args.mylang, "build", source, "-o", old, "--release"], capture_output=True, text=True)
        if built.returncode != 0:
            stats["rejected"] += 1
            print(f"case {case}: old core rejects it:\n{built.stderr[:400]}")
            continue
        for mode, flags in (("debug", []), ("release", ["--release"]), ("verify", ["--release", "--verify-facts"])):
            exe = os.path.join(work, f"case{case}-{mode}")
            made = subprocess.run([args.core, "build", source, "-o", exe, "--cache-dir", os.path.join(work, "cache")] + flags, capture_output=True, text=True)
            if made.returncode != 0:
                stats["refused"] += 1
                print(f"case {case} {mode}: new core refuses: {made.stderr.strip()[:300]}")
                break
            for argv in ([], ["x"], ["x", "y", "z"]):
                want = run([old] + argv)
                got = run([exe] + argv, env)
                stats["compared"] += 1
                if got[0] != want[0] or got[1] != want[1] or "leakcheck" in got[2] or "R_CORE_FACT" in got[2]:
                    stats["mismatch"] += 1
                    print(f"MISMATCH case {case} {mode} {argv}: old {want[1]} {want[0]!r} new {got[1]} {got[0]!r} {got[2].strip()[:300]}")
    print(" ".join(f"{k}={v}" for k, v in stats.items()))
    return 1 if stats["mismatch"] else 0


if __name__ == "__main__":
    sys.exit(main())
