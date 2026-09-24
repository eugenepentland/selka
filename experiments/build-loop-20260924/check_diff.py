#!/usr/bin/env python3
"""Differential test: incremental `mylang check` (persistent cache) vs `--no-cache`.

Applies random source mutations to a copy of a project, one after another (sometimes
reverting to the pristine tree), and after every step compares exit status, stdout and
stderr of a cached check against a cold check. Any difference is a stale-cache bug.

usage: check_diff.py MYLANG PROJECT_DIR ENTRY STEPS SEED WORKDIR
"""
import os
import random
import re
import shutil
import subprocess
import sys

MYLANG, SRC, ENTRY, STEPS, SEED, WORK = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4]), int(sys.argv[5]), sys.argv[6]
rng = random.Random(SEED)
TREE = os.path.join(WORK, "tree")
CACHE = os.path.join(WORK, "cache")
shutil.rmtree(WORK, ignore_errors=True)
shutil.copytree(SRC, TREE)
PRISTINE = {f: open(os.path.join(TREE, f)).read() for f in os.listdir(TREE) if f.endswith(".my") and not f.endswith("_test.my") and not f.endswith("_tests.my")}
ENV = dict(os.environ, TMPDIR=os.environ.get("TMPDIR", "/tmp"))


def check(cached):
    args = [MYLANG, "check", ENTRY] + ([f"--cache-dir={CACHE}"] if cached else ["--no-cache"])
    p = subprocess.run(args, cwd=TREE, capture_output=True, env=ENV, timeout=300)
    return p.returncode, p.stdout.decode(errors="replace"), p.stderr.decode(errors="replace")


DEF = re.compile(r"^(public )?def (\w+)\((.*)\)( -> [^:]+)?:$", re.M)
FIELD = re.compile(r"^    (\w+): ([\w\[\]., ]+)$", re.M)


def mutations(text):
    """Yield (name, new_text) candidates for one file."""
    out = []
    defs = list(DEF.finditer(text))
    for m in defs:
        line = m.group(0)
        if m.group(4) and "-> int" in m.group(4):
            out.append(("ret int->bool", text.replace(line, line.replace("-> int", "-> bool"), 1)))
        if m.group(4) and "-> bool" in m.group(4):
            out.append(("ret bool->int", text.replace(line, line.replace("-> bool", "-> int"), 1)))
        if ": int" in m.group(3):
            out.append(("param int->float", text.replace(line, line.replace(": int", ": float", 1), 1)))
        if ": mut " in m.group(3):
            out.append(("drop mut", text.replace(line, line.replace(": mut ", ": ", 1), 1)))
        if m.group(3):
            out.append(("add param", text.replace(line, line.replace(")", ", extra_param: int)", 1) if ")" in line else line, 1)))
        out.append(("rename def", text.replace(line, line.replace(f"def {m.group(2)}(", f"def {m.group(2)}_renamed(", 1), 1)))
        if m.group(1):
            out.append(("unpublic", text.replace(line, line[len("public "):], 1)))
        # A type error at the top of the body.
        out.append(("body type error", text.replace(line + "\n", line + "\n    zz_bad: int = \"x\"\n", 1)))
        # A body edit that changes nothing observable.
        out.append(("body no-op", text.replace(line + "\n", line + "\n    zz_ok: int = 1\n", 1)))
    for m in FIELD.finditer(text):
        line = m.group(0)
        out.append(("rename field", text.replace(line, f"    {m.group(1)}_x: {m.group(2)}", 1)))
        if m.group(2) == "int":
            out.append(("field int->float", text.replace(line, f"    {m.group(1)}: float", 1)))
    for m in re.finditer(r"(?<![\w.])(\d+)(?![\w.])", text):
        if rng.random() < 0.02:
            out.append(("int literal", text[:m.start()] + str(int(m.group(1)) + 7) + text[m.end():]))
    return out


def main():
    files = sorted(PRISTINE)
    rc, _, err = check(False)
    print(f"pristine cold check rc={rc}", flush=True)
    bad = 0
    stats = {"clean": 0, "errors": 0}
    for step in range(1, STEPS + 1):
        # Warm the cache on the pristine tree, then apply one or two edits to it: the
        # risky case is an edit the cached check could wrongly skip in a clean project.
        for f, t in PRISTINE.items():
            open(os.path.join(TREE, f), "w").write(t)
        warm = check(True)
        if warm[0] != 0:
            print(f"pristine warm check failed at step {step}: {warm[2][:300]}")
        whats = []
        for _ in range(1 if rng.random() < 0.7 else 2):
            f = rng.choice(files)
            path = os.path.join(TREE, f)
            cands = mutations(open(path).read())
            if not cands:
                continue
            name, new = rng.choice(cands)
            open(path, "w").write(new)
            whats.append(f"{f}: {name}")
        what = "; ".join(whats)
        inc = check(True)
        cold = check(False)
        stats["clean" if cold[0] == 0 else "errors"] += 1
        if inc != cold:
            bad += 1
            print(f"MISMATCH step {step} ({what}): cached rc={inc[0]} cold rc={cold[0]}", flush=True)
            print("  cached stderr:", inc[2][:600].replace("\n", "\n    "))
            print("  cold   stderr:", cold[2][:600].replace("\n", "\n    "))
            snap = os.path.join(WORK, f"mismatch-{step}")
            shutil.copytree(TREE, snap)
        else:
            print(f"ok step {step} ({what}) rc={cold[0]}", flush=True)
    print(f"DONE steps={STEPS} mismatches={bad} cold-clean={stats['clean']} cold-errors={stats['errors']}")
    sys.exit(1 if bad else 0)


main()
