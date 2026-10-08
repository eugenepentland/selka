#!/usr/bin/env python3
"""S1 differential fuzz: the new core against the old core, with the S1 language features.

The S0 fuzz (experiments/new-core-s0-20261005/fuzz.py) generates integer/list programs. This one
adds the features S1 brings, each behind a flag, so they switch on as lanes V and O land:

  records    records with list fields: construction, field and element writes (`b.items[i] = v`),
             copies (`c = b`), field aliasing (`b.items = c.items`), loops over a field, helpers
             returning modified copies
  unions     `list[Item]` of a union with scalar, record and managed-record payloads, `match` over
             its elements, element replacement, snapshots (`snap = items`) then appends
  propagate  `Result[int, E]` helpers chained with `?` (also inside loops and branches), matched
             in the caller; the error type varies (`str`, `int`)
  mut        `mut list[int]` and `mut Bucket` helpers, a `mut` field argument (`mut b.items`), nested
             `mut` calls, `mut` helpers that append, rebind and swap elements
  alias      `ys = xs` then writes to either one (append, element write), aliases passed to one
             helper, record and union snapshots taken before writes
  scalar     the S0 vocabulary, for checking this harness against what the new core supports today

Every program is built by

  old      `mylang build --release`                (the oracle)
  debug    `mylang-core build`                     (every check exact)
  release  `mylang-core build --release`           (facts drop checks)
  verify   `mylang-core build --release --verify-facts`

and run with several argument sets; every build must give the oracle's stdout, exit status and
trap code, and a verify build must never report `R_CORE_FACT`. A program the new core refuses
(`E_CORE_UNSUPPORTED`) is counted as a refusal, with its reason, and never as a mismatch; a
program the old core rejects is a generator bug and is counted apart too.

usage: fuzz.py --cases N [--seed S] [--features records,unions,... | all | each]
               [--keep DIR] [--mylang P] [--core P] [--jobs J]
"""
import argparse, collections, importlib.util, os, random, re, shutil, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))

# The S0 generator, reused for the scalar vocabulary and its expression grammar.
_spec = importlib.util.spec_from_file_location("fuzz_s0", os.path.join(ROOT, "experiments", "new-core-s0-20261005", "fuzz.py"))
fuzz_s0 = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(fuzz_s0)
ARGS = fuzz_s0.ARGS
run, build = fuzz_s0.run, fuzz_s0.build

FEATURES = ["records", "unions", "propagate", "mut", "alias"]

HEAD = """def number(text: str, fallback: int) -> int:
    match int(text):
        case Some(value):
            return value
        case None:
            return fallback


def fold(values: list[int]) -> int:
    total = 0
    for value in values:
        total = (total * 31 + value) % 1000003
    return total
"""

RECORDS = """

record Bucket:
    count: int
    items: list[int]


def bucket_total(b: Bucket) -> int:
    t = b.count
    for x in b.items:
        t = (t * 7 + x) % 1000003
    return t


def grow(b: Bucket, v: int) -> Bucket:
    items = b.items
    items.append(v)
    return Bucket(b.count + 1, items)
"""

UNIONS = """

record Pair:
    a: int
    b: int


union Item:
    empty,
    num: int,
    pair: Pair,
    bag: Bucket


def weigh(item: Item) -> int:
    match item:
        case Item.num(v):
            return v
        case Item.pair(p):
            return p.a * 3 + p.b
        case Item.bag(g):
            return len(g.items) + g.count
        case _:
            return 1


def sum_items(items: list[Item]) -> int:
    t = 0
    for i in range(len(items)):
        t = (t * 5 + weigh(items[i])) % 1000003
    return t
"""

MUT = """

def bump(xs: mut list[int], k: int):
    xs.append(k)
    xs[0] = (xs[0] + k) % 1009


def fill(xs: mut list[int], k: int):
    for j in range(k % 4):
        xs.append(j * 3 + k)


def swap_ends(xs: mut list[int]):
    last = len(xs) - 1
    first = xs[0]
    xs[0] = xs[last]
    xs[last] = first


def twice(xs: mut list[int], k: int):
    bump(mut xs, k)
    bump(mut xs, k + 1)
"""

MUT_RECORDS = """

def touch(b: mut Bucket, v: int):
    b.items[0] = v
    b.count = b.count + 1
    b.items.append(v)


def touch_items(b: mut Bucket, v: int):
    bump(mut b.items, v)
    b.count = b.count + 2


def rebuild(b: mut Bucket, v: int):
    b = Bucket(v % 5, [v, v + 1])
"""

ALIAS = """

def both(xs: list[int], ys: list[int]) -> int:
    return len(xs) * 100 + len(ys) + xs[0] + ys[0]
"""


def propagate_helpers(rng):
    """Result helpers chained with `?`: step_k fails on a data-dependent condition."""
    err_type = rng.choice(["str", "int"])
    fail = '"bad"' if err_type == "str" else "7"
    lines = []
    steps = rng.randint(2, 4)
    for k in range(steps):
        lines += ["", "", "def step%d(x: int) -> Result[int, %s]:" % (k, err_type),
                  "    if x %% %d == %d:" % (rng.choice([3, 5, 7, 11]), rng.randint(0, 2)),
                  "        return Err(%s)" % fail,
                  "    return Ok((x * %d + %d) %% 1009)" % (rng.randint(2, 9), rng.randint(0, 9))]
    for c in range(rng.randint(1, 2)):
        lines += ["", "", "def chain%d(x: int) -> Result[int, %s]:" % (c, err_type)]
        count = rng.randint(1, steps)
        names = []
        prev = "x"
        for j in range(count):
            names.append("v%d" % j)
            lines.append("    v%d = step%d(%s)?" % (j, rng.randrange(steps), prev))
            if rng.random() < 0.3:
                lines += ["    if v%d > %d:" % (j, rng.randint(100, 900)), "        return Ok(v%d)" % j]
            prev = "v%d + 1" % j
        lines.append("    return Ok(%s)" % " + ".join(names))
    lines += ["", "", "def sum_checked(xs: list[int]) -> Result[int, %s]:" % err_type,
              "    t = 0", "    for x in xs:", "        t = (t + step%d(x)?) %% 1000003" % rng.randrange(steps), "    return Ok(t)"]
    return "\n".join(lines) + "\n", err_type


class Gen:
    """One program: declarations for the enabled features, then a `main` of random operations."""

    def __init__(self, rng, features):
        self.r = rng
        self.f = set(features)
        self.e = fuzz_s0.Gen(rng)
        self.err_type = "str"

    def expr(self, names=("seed", "n", "acc")):
        return "(%s) %% 1009" % self.e.expr(list(names), 2)

    def index(self, name, safe_chance=0.85):
        """An index into `name`: `% len` keeps it in range; otherwise it can hit the bounds trap."""
        raw = self.expr()
        if self.r.random() < safe_chance:
            return "(%s) %% len(%s)" % (raw, name)
        return "(%s) %% (len(%s) + 1)" % (raw, name)

    # --- operations: each returns the statements (unindented) of one step ---------------------

    def ops_records(self):
        b, c = self.r.choice([("b", "c"), ("c", "b")])
        return [
            ["%s = Bucket(%s.count + 1, %s.items)" % (b, b, b)],
            ["%s = %s" % (c, b)],
            ["%s.items.append(%s)" % (b, self.expr())],
            ["%s.items[%s] = %s" % (b, self.index(b + ".items"), self.expr())],
            ["%s.count = %s.count + %s" % (b, b, self.expr())],
            ["acc = (acc + %s.items[%s]) %% 1000003" % (b, self.index(b + ".items"))],
            ["for x in %s.items:" % c, "    acc = (acc + x) % 1000003"],
            ["%s.items = %s.items" % (b, c)],
            ["%s = grow(%s, %s)" % (c, b, self.expr())],
            ["acc = (acc + bucket_total(%s)) %% 1000003" % b],
        ]

    def ops_unions(self):
        new = self.r.choice([
            "Item.num(%s)" % self.expr(), "Item.empty", "Item.pair(Pair(%s, %s))" % (self.expr(), self.expr()),
            "Item.bag(Bucket(%s, [%s, %s]))" % (self.expr(), self.expr(), self.expr())])
        return [
            ["items.append(%s)" % new],
            ["for i in range(len(items)):", "    match items[i]:", "        case Item.num(v):", "            acc = (acc + v) % 1000003",
             "        case Item.pair(p):", "            acc = (acc + p.a * p.b) % 1000003", "        case _:", "            acc = (acc + 1) % 1000003"],
            ["if len(items) > 0:", "    items[%s] = %s" % (self.index("items"), new)],
            ["if len(items) > 0:", "    match items[%s]:" % self.index("items"), "        case Item.bag(g):",
             "            acc = (acc + len(g.items) + g.count) % 1000003", "        case _:", "            acc = (acc + 2) % 1000003"],
            ["acc = (acc + sum_items(items)) % 1000003"],
        ]

    def ops_propagate(self):
        chain = "chain%d" % self.r.randrange(self.chains)
        on_err = "len(e)" if self.err_type == "str" else "e"
        return [
            ["match %s(%s):" % (chain, self.expr()), "    case Ok(v):", "        acc = (acc + v) % 1000003", "    case Err(e):", "        acc = (acc + %s) %% 1000003" % on_err],
            ["match sum_checked(%s):" % self.r.choice(["xs", "ys"]), "    case Ok(v):", "        acc = (acc + v) % 1000003", "    case Err(e):", "        acc = (acc + %s + 1) %% 1000003" % on_err],
            ["if acc %% %d == 0:" % self.r.randint(2, 5), "    match %s(acc):" % chain, "        case Ok(v):", "            acc = v", "        case Err(e):", "            acc = %s" % on_err],
        ]

    def ops_mut(self):
        xs = self.r.choice(["xs", "ys"])
        ops = [
            ["bump(mut %s, %s)" % (xs, self.expr())],
            ["fill(mut %s, %s)" % (xs, self.expr())],
            ["swap_ends(mut %s)" % xs],
            ["twice(mut %s, %s)" % (xs, self.expr())],
        ]
        if "records" in self.f:
            b = self.r.choice(["b", "c"])
            ops += [
                ["touch(mut %s, %s)" % (b, self.expr())],
                ["touch_items(mut %s, %s)" % (b, self.expr())],
                ["rebuild(mut %s, %s)" % (b, self.expr())],
                ["bump(mut %s.items, %s)" % (b, self.expr())],
            ]
        return ops

    def ops_alias(self):
        a, b = self.r.choice([("xs", "ys"), ("ys", "xs")])
        ops = [
            ["%s = %s" % (b, a)],
            ["%s.append(%s)" % (a, self.expr())],
            ["%s[%s] = %s" % (b, self.index(b), self.expr())],
            ["acc = (acc + both(xs, ys)) % 1000003"],
            ["acc = (acc + len(%s) * 3 + %s[0]) %% 1000003" % (a, b)],
        ]
        if "records" in self.f:
            ops += [["snap = b", "b.items.append(%s)" % self.expr(), "acc = (acc + len(snap.items) * 5 + len(b.items)) % 1000003"]]
        if "unions" in self.f:
            ops += [["snap_items = items", "items.append(Item.num(%s))" % self.expr(), "acc = (acc + len(snap_items) * 7 + len(items)) % 1000003"]]
        return ops

    # --- the program ---------------------------------------------------------------------------

    def program(self):
        r, f = self.r, self.f
        if "scalar" in f:
            return fuzz_s0.Gen(r).program()
        text = HEAD
        if "records" in f or "unions" in f:
            text += RECORDS
        if "unions" in f:
            text += UNIONS
        if "mut" in f:
            text += MUT
            if "records" in f or "unions" in f:
                text += MUT_RECORDS
        if "alias" in f:
            text += ALIAS
        self.chains = 1
        if "propagate" in f:
            helpers, self.err_type = propagate_helpers(r)
            self.chains = helpers.count("def chain")
            text += helpers
        lines = [
            "", "", "def main(args: list[str], out: Stream) -> int:",
            "    if len(args) != 3:", "        return 2",
            "    n = number(args[0], 3)", "    rounds = number(args[1], 2)", "    seed = number(args[2], 7)",
            "    if n < 1 or n > 100 or rounds < 0 or rounds > 5:", "        return 3",
            "    acc = 0",
            "    xs = [(j * %d + seed) %% 1009 for j in range(n)]" % r.randint(1, 30),
            "    ys = [(j * %d + 1) %% 997 for j in range(n)]" % r.randint(1, 30),
        ]
        if "records" in f or "unions" in f:
            lines += ["    b = Bucket(n, xs)", "    c = Bucket(1, [seed])"]
        if "unions" in f:
            lines += ["    items: list[Item] = []", "    items.append(Item.num(seed))"]
        count = r.randint(5, 12)
        steps = []
        for _ in range(count):
            # Draw the pool again for every step so no two steps share their random operands.
            fresh = []
            for name in ("records", "unions", "propagate", "mut", "alias"):
                if name in f:
                    fresh += getattr(self, "ops_" + name)()
            steps.append(r.choice(fresh) if fresh else ["acc = acc + 1"])
        looped = r.random() < 0.5 and count > 2
        start = r.randrange(count - 1) if looped else -1
        stop = min(count, start + r.randint(2, 4)) if looped else -1
        for index, step in enumerate(steps):
            if looped and index == start:
                lines += ["    for r in range(rounds):", "        acc = (acc + r) % 1000003"]
            pad = "        " if looped and start <= index < stop else "    "
            lines += [pad + line for line in step]
        tail = ["acc", "fold(xs)", "fold(ys)"]
        if "records" in f or "unions" in f:
            tail += ["b.count", "fold(b.items)", "c.count", "fold(c.items)"]
        if "unions" in f:
            tail += ["sum_items(items)", "len(items)"]
        lines += ["    out.print(%s)" % ", ".join(tail), "    return acc % 7", ""]
        return text + "\n".join(lines) + "\n"


def refusal_reason(stderr):
    found = re.search(r"does not support (.*?) yet", stderr)
    return found.group(1) if found else "other"


def fuzz(args, features, label, rng, work):
    stats = collections.Counter()
    reasons = collections.Counter()
    sabotage = "--sabotage-facts" + ("=" + args.rule if args.rule else "")
    for case in range(args.cases):
        source = Gen(rng, features).program()
        path = os.path.join(work, "%s%d.my" % (label.replace(",", "_"), case))
        with open(path, "w") as out:
            out.write(source)
        stats["cases"] += 1
        old = path[:-3] + ".old"
        ok, err = build([args.mylang, "build", path, "-o", old, "--release", "--cache-dir", os.path.join(work, "cache-old")])
        if not ok:
            stats["old_rejected"] += 1
            if args.verbose or stats["old_rejected"] <= 2:
                print("%s case %d: the old core rejected the program (a generator bug):\n%s" % (label, case, err[:1500]))
            if args.keep:
                os.makedirs(args.keep, exist_ok=True)
                shutil.copy(path, args.keep)
            continue
        builds = {}
        modes = {"debug": [], "release": ["--release"], "verify": ["--release", sabotage if args.sabotage else "--verify-facts"]}
        refused = False
        for mode, flags in modes.items():
            exe = path[:-3] + "." + mode
            ok, err = build([args.core, "build", path, "-o", exe, "--cache-dir", os.path.join(work, "cache-core")] + flags)
            if not ok:
                if "E_CORE_UNSUPPORTED" in err:
                    reasons[refusal_reason(err)] += 1
                else:
                    print("%s case %d: new core build failed (%s):\n%s" % (label, case, mode, err[:1500]))
                    stats["mismatch"] += 1
                    stats["build_failed"] += 1
                    if args.keep:
                        os.makedirs(args.keep, exist_ok=True)
                        shutil.copy(path, args.keep)
                refused = True
                break
            builds[mode] = exe
        if refused:
            stats["refused"] += 1
            continue
        caught = False
        for argv in ARGS:
            expected = run([old] + argv)
            if expected[2]:
                stats["traps"] += 1
            for mode, exe in builds.items():
                got = run([exe] + argv)
                if got[2] == "R_CORE_FACT":
                    caught = True
                    if not args.sabotage:
                        stats["fact"] += 1
                        print("%s case %d %s %s: R_CORE_FACT" % (label, case, mode, argv))
                    continue
                stats["compared"] += 1
                if got != expected and not (args.sabotage and mode == "verify"):
                    stats["mismatch"] += 1
                    print("%s case %d %s %s: expected %r got %r" % (label, case, mode, argv, expected, got))
                    if args.keep:
                        os.makedirs(args.keep, exist_ok=True)
                        shutil.copy(path, args.keep)
        stats["caught"] += caught
    return stats, reasons


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--cases", type=int, default=30)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--features", default="all", help="comma list of %s, or scalar; `all` = every S1 feature together; `each` = every feature alone, then all" % ",".join(FEATURES))
    ap.add_argument("--keep", default=None)
    ap.add_argument("--sabotage", action="store_true")
    ap.add_argument("--rule", default="")
    ap.add_argument("--verbose", action="store_true")
    ap.add_argument("--mylang", default=os.path.join(ROOT, "zig-out/bin/mylang"))
    ap.add_argument("--core", default=os.path.join(ROOT, "zig-out/bin/mylang-core"))
    args = ap.parse_args()
    if args.features == "all":
        runs = [FEATURES]
    elif args.features == "each":
        runs = [[f] for f in FEATURES] + [FEATURES]
    else:
        runs = [args.features.split(",")]
    work = tempfile.mkdtemp(prefix="core-fuzz-s1.", dir=os.environ.get("TMPDIR"))
    bad = False
    try:
        for features in runs:
            label = ",".join(features)
            stats, reasons = fuzz(args, features, label, random.Random(args.seed), work)
            keys = ["cases", "old_rejected", "refused", "compared", "mismatch", "fact", "traps", "caught"]
            print("%-34s %s" % (label, " ".join("%s=%d" % (k, stats[k]) for k in keys)))
            if reasons:
                print("  refused for: " + ", ".join("%s x%d" % kv for kv in reasons.most_common(8)))
            bad = bad or stats["mismatch"] or (stats["fact"] and not args.sabotage)
    finally:
        shutil.rmtree(work, ignore_errors=True)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
