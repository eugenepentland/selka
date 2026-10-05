#!/usr/bin/env python3
"""Whole-program differential fuzz: the new core against the old core.

Each case is a random program inside the S0 vocabulary (integers, booleans,
lists built by comprehensions, counted and while loops, branches, floor
division and remainder with constant, variable and zero divisors, helper
calls, `int(text)`, short-circuit operators). It is built by

  old      `mylang build --release`                (the oracle)
  debug    `mylang-core build`                     (every check exact)
  release  `mylang-core build --release`           (facts drop checks)
  verify   `mylang-core build --release --verify-facts`

and run with several argument sets. Every build must give the oracle's stdout,
exit status and trap code (`error[R_...]` on stderr); a verify build must
never report `R_CORE_FACT`. With `--sabotage`, the verify build is made with
`--sabotage-facts` (one deliberately wrong interval rule) and the run reports
how many cases caught it.

usage: fuzz.py --cases N [--seed S] [--keep DIR] [--sabotage] [--mylang P] [--core P]
"""
import argparse, os, random, re, shutil, subprocess, sys, tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ARGS = [["5", "3", "7"], ["0", "2", "1"], ["37", "4", "999983"], ["1", "1", "-12"], ["64", "2", "42"]]


class Gen:
    def __init__(self, rng):
        self.r = rng

    def const(self):
        r = self.r.random()
        if r < 0.6:
            return str(self.r.randint(0, 50))
        if r < 0.8:
            return str(self.r.choice([7, 13, 17, 101, 1009, 65536, 1000003]))
        if r < 0.9:
            return "(0 - %d)" % self.r.randint(1, 40)
        return str(self.r.choice([4611686018427387904, 3037000500, 9223372036854775807]))

    def expr(self, names, depth):
        if depth <= 0 or self.r.random() < 0.25:
            return self.r.choice(names) if self.r.random() < 0.7 else self.const()
        op = self.r.choice(["+", "-", "*", "//", "%", "+", "*", "%"])
        left = self.expr(names, depth - 1)
        if op in ("//", "%"):
            r = self.r.random()
            if r < 0.6:
                right = str(self.r.choice([1, 2, 3, 7, 16, 17, 1009, 1000000007]))
            elif r < 0.7:
                right = "(0 - %d)" % self.r.randint(1, 9)
            else:
                right = self.expr(names, depth - 1)
        else:
            right = self.expr(names, depth - 1)
        return "(%s %s %s)" % (left, op, right)

    def lane_expr(self, names, depth):
        """A non-negative expression of the shape the vector lowering takes."""
        if depth <= 0 or self.r.random() < 0.25:
            return self.r.choice(names) if self.r.random() < 0.7 else str(self.r.randint(0, 40))
        op = self.r.choice(["+", "*", "//", "%", "+"])
        left = self.lane_expr(names, depth - 1)
        if op in ("//", "%"):
            return "(%s %s %d)" % (left, op, self.r.choice([1, 2, 3, 7, 16, 17, 101, 1009]))
        return "(%s %s %s)" % (left, op, self.lane_expr(names, depth - 1))

    def cond(self, names, depth):
        a = self.expr(names, depth)
        b = self.expr(names, depth)
        c = "%s %s %s" % (a, self.r.choice(["<", "<=", ">", ">=", "==", "!="]), b)
        if self.r.random() < 0.3:
            d = "%s %s %s" % (self.r.choice(names), self.r.choice(["<", ">", "=="]), self.const())
            c = "%s %s %s" % (c, self.r.choice(["and", "or"]), d)
        return c

    def program(self):
        r = self.r
        lines = []
        helpers = r.randint(0, 2)
        for h in range(helpers):
            lines += ["def helper%d(a: int, b: int) -> int:" % h]
            if r.random() < 0.5:
                lines += ["    if %s:" % self.cond(["a", "b"], 1), "        return %s" % self.expr(["a", "b"], 2)]
            lines += ["    return %s" % self.expr(["a", "b"], 2), "", ""]
        lines += [
            "def number(text: str, fallback: int) -> int:",
            "    match int(text):",
            "        case Some(value):",
            "            return value",
            "        case None:",
            "            return fallback",
            "",
            "",
            "def main(args: list[str], out: Stream) -> int:",
            "    if len(args) != 3:",
            "        return 2",
            "    n = number(args[0], 3)",
            "    rounds = number(args[1], 2)",
            "    seed = number(args[2], 7)",
            "    if n < 0 or n > 100 or rounds < 0 or rounds > 5:",
            "        return 3",
        ]
        lane_shaped = r.random() < 0.5
        element = self.expr(["j", "seed"], 2)
        modulus = r.choice(["1009", "17", "4000", "7"]) if lane_shaped else r.choice(["1009", "17", "65536", "7", "1000000007", None])
        if modulus:
            element = "(%s) %% %s" % (element, modulus)
        lines.append("    values = [%s for j in range(n)]" % element)
        lines.append("    second = [(j * %d + 3) %% %d for j in range(n)]" % (r.randint(1, 50), r.choice([7, 64, 1009, 4000])))
        if r.random() < 0.4:
            flag = "(%s) %% %d < %d" % (self.expr(["j", "seed"], 1), r.choice([2, 3, 101]), r.randint(0, 60)) if lane_shaped else self.cond(["j", "seed"], 1)
            lines.append("    flags = [%s for j in range(n)]" % flag)
        else:
            lines.append("    flags = [j % 3 != 0 for j in range(n)]")
        lines += ["    acc = 0", "    for b in range(rounds):", "        phase = b %% %d" % r.randint(1, 20), "        total = 0"]
        bound = r.choice(["n", "n", "len(values)", "n - 1", "n + %d" % r.randint(0, 2)])
        lines.append("        for j in range(%s):" % bound)
        index = "j" if lane_shaped else r.choice(["j", "j", "j", "j + 1", "n - 1 - j", "0 - 1 - j"])
        lines.append("            x = values[%s]" % index)
        lines.append("            y = second[j % n]" if bound not in ("n", "len(values)", "n - 1") else "            y = second[j]")
        names = ["x", "phase", "j", "seed", "y"]
        if lane_shaped:
            lines.append("            v = %s" % self.lane_expr(["x", "phase", "y"], 3))
        else:
            lines.append("            v = %s" % self.expr(names, 3))
        if r.random() < 0.5:
            lines.append("            if flags[%s]:" % ("j" if bound in ("n", "len(values)", "n - 1") else "j % n"))
            if lane_shaped:
                lines += ["                v = %s" % self.lane_expr(["x", "phase", "v"], 2), "            else:", "                v = v + %d" % r.randint(0, 30)]
            else:
                lines += ["                v = %s" % self.expr(names + ["v"], 2), "            else:", "                v = v + %s" % self.const()]
        if helpers and r.random() < 0.6 and not lane_shaped:
            lines.append("            v = helper%d(v, %s)" % (r.randrange(helpers), self.expr(names, 1)))
        if r.random() < 0.3 and not lane_shaped:
            lines += ["            if %s:" % self.cond(names, 1), "                continue"]
        if r.random() < 0.2 and not lane_shaped:
            lines += ["            if %s:" % self.cond(names, 1), "                break"]
        lines.append("            total += v")
        if r.random() < 0.8:
            lines.append("        acc = (acc + total) % 1000000007")
        else:
            lines.append("        acc = acc + total")
        if r.random() < 0.5:
            lines += ["    k = seed % 1000 + 2", "    steps = 0", "    while k != 1 and steps < 200:",
                      "        if k % 2 == 0:", "            k = k // 2", "        else:", "            k = 3 * k + 1",
                      "        steps += 1", "    acc = acc + steps"]
        lines += ["    out.print(acc, len(values))", "    return acc % 7", ""]
        return "\n".join(lines) + "\n"


def run(argv, timeout=20):
    try:
        done = subprocess.run(argv, capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        return ("TIMEOUT", 124, "")
    trap = re.search(r"error\[(R_[A-Z_]+)\]", done.stderr)
    return (done.stdout, done.returncode, trap.group(1) if trap else "")


def build(argv):
    done = subprocess.run(argv, capture_output=True, text=True)
    return done.returncode == 0, done.stderr


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cases", type=int, default=50)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--keep", default=None)
    ap.add_argument("--sabotage", action="store_true")
    ap.add_argument("--mylang", default=os.path.join(ROOT, "zig-out/bin/mylang"))
    ap.add_argument("--core", default=os.path.join(ROOT, "zig-out/bin/mylang-core"))
    args = ap.parse_args()
    work = tempfile.mkdtemp(prefix="core-fuzz.", dir=os.environ.get("TMPDIR"))
    stats = {"cases": 0, "old_rejected": 0, "new_refused": 0, "compared": 0, "mismatch": 0, "fact": 0, "traps": 0, "caught": 0, "vectorized": 0, "versioned": 0}
    rng = random.Random(args.seed)
    for case in range(args.cases):
        source = Gen(rng).program()
        path = os.path.join(work, "case%d.my" % case)
        with open(path, "w") as f:
            f.write(source)
        stats["cases"] += 1
        old = os.path.join(work, "old%d" % case)
        ok, err = build([args.mylang, "build", path, "-o", old, "--release", "--cache-dir", os.path.join(work, "cache-old")])
        if not ok:
            stats["old_rejected"] += 1
            continue
        builds = {}
        modes = {"debug": [], "release": ["--release", "--stats"], "verify": ["--release", "--sabotage-facts" if args.sabotage else "--verify-facts"]}
        refused = False
        for mode, flags in modes.items():
            out = os.path.join(work, "%s%d" % (mode, case))
            ok, err = build([args.core, "build", path, "-o", out, "--cache-dir", os.path.join(work, "cache-core")] + flags)
            if not ok:
                if "E_CORE_UNSUPPORTED" in err:
                    refused = True
                    break
                print("case %d: new core build failed (%s):\n%s" % (case, mode, err[:2000]))
                stats["mismatch"] += 1
                if args.keep:
                    os.makedirs(args.keep, exist_ok=True)
                    shutil.copy(path, args.keep)
                refused = True
                break
            builds[mode] = out
            if mode == "release":
                found = re.search(r"versioned (\d+) loops, proved \d+ checks, vectorized (\d+) loops", err)
                if found and int(found.group(2)):
                    stats["vectorized"] += 1
                if found and int(found.group(1)):
                    stats["versioned"] += 1
        if refused:
            stats["new_refused"] += 1
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
                        print("case %d %s %s: R_CORE_FACT" % (case, mode, argv))
                    continue
                stats["compared"] += 1
                if got != expected and not (args.sabotage and mode == "verify"):
                    stats["mismatch"] += 1
                    print("case %d %s %s: expected %r got %r" % (case, mode, argv, expected, got))
                    if args.keep:
                        os.makedirs(args.keep, exist_ok=True)
                        shutil.copy(path, args.keep)
        if caught:
            stats["caught"] += 1
    print(" ".join("%s=%d" % kv for kv in stats.items()))
    shutil.rmtree(work, ignore_errors=True)
    return 1 if stats["mismatch"] or (stats["fact"] and not args.sabotage) else 0


if __name__ == "__main__":
    sys.exit(main())
