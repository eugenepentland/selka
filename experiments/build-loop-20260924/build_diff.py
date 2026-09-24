#!/usr/bin/env python3
"""Differential test: incremental `mylang build --project` vs a clean build.

Warms a persistent cache on the pristine project, applies one or two random edits that
usually still compile (literal changes, operator flips, record field reordering, constant
changes, added functions, body no-ops), then builds with the persistent cache and with a
fresh cache. Compares build exit status and diagnostics; when both succeed, runs both
executables on a fixed set of Lox scripts (both engines) and compares stdout, stderr and
exit status. Any difference is a stale-build bug.

usage: build_diff.py MYLANG PROJECT_DIR STEPS SEED WORKDIR
"""
import os
import random
import re
import shutil
import subprocess
import sys

MYLANG, SRC, STEPS, SEED, WORK = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4]), sys.argv[5]
CORPUS = "/home/epentland/ai/trials/devspeed-20260923-private/probe/benchmarks/lox/corpus/test"
rng = random.Random(SEED)
TREE = os.path.join(WORK, "tree")
CACHE = os.path.join(WORK, "cache")
shutil.rmtree(WORK, ignore_errors=True)
shutil.copytree(SRC, TREE)
PRISTINE = {f: open(os.path.join(TREE, f)).read() for f in os.listdir(TREE) if f.endswith(".my") and not f.endswith("_test.my") and not f.endswith("_tests.my")}
SCRIPTS = []
for sub in ["assignment", "closure", "class", "for", "function", "inheritance", "string", "operator", "super", "while", "return", "field", "method", "logical_operator", "number", "regression"]:
    files = sorted(f for f in os.listdir(os.path.join(CORPUS, sub)) if f.endswith(".lox"))
    SCRIPTS += [os.path.join(CORPUS, sub, f) for f in random.Random(sub).sample(files, min(2, len(files)))]
SCRIPTS.append("/home/epentland/ai/trials/devspeed-20260923-private/probe/benchmarks/lox/corpus/test/precedence.lox")


def build(cache, out):
    args = [MYLANG, "build", "main.my", "--project", "-o", out, f"--cache-dir={cache}"]
    p = subprocess.run(args, cwd=TREE, capture_output=True, timeout=900)
    return p.returncode, p.stderr.decode(errors="replace")


def behaviour(exe):
    """Run every script on both engines; after 3 timeouts (an edit that makes the
    interpreter loop) the remaining runs are recorded as skipped for both binaries."""
    results = []
    timeouts = 0
    for s in SCRIPTS:
        for engine in ("--engine=vm", "--engine=tree"):
            if timeouts >= 3:
                results.append((s, engine, "skipped", b"", b""))
                continue
            try:
                p = subprocess.run([exe, engine, s], capture_output=True, timeout=2)
                results.append((s, engine, p.returncode, p.stdout, p.stderr))
            except subprocess.TimeoutExpired:
                timeouts += 1
                results.append((s, engine, "timeout", b"", b""))
    return results


def mutations(text):
    out = []
    # Integer literal changes (constants, initial values, loop bounds, opcodes).
    for m in re.finditer(r"(?<![\w.])(\d+)(?![\w.])", text):
        out.append(("int literal", text[:m.start()] + str(int(m.group(1)) + rng.choice([1, 2, 7])) + text[m.end():]))
    # Comparison and arithmetic operator flips.
    for pat, rep in [(" < ", " <= "), (" <= ", " < "), (" > ", " >= "), (" + 1", " + 2"), (" - 1", " - 2"), (" == ", " != ")]:
        idx = [m.start() for m in re.finditer(re.escape(pat), text)]
        if idx:
            i = rng.choice(idx)
            out.append((f"op {pat.strip()}->{rep.strip()}", text[:i] + rep + text[i + len(pat):]))
    # Byte-string literal edits (messages the scripts print).
    for m in re.finditer(r'b"([^"\\]{2,})"', text):
        out.append(("bytes literal", text[:m.start()] + 'b"' + m.group(1)[::-1] + '"' + text[m.end():]))
    # Swap two adjacent field lines of a class/record: layout changes, source still compiles.
    lines = text.split("\n")
    for i in range(len(lines) - 1):
        a, b = lines[i], lines[i + 1]
        if re.match(r"^    \w+: [\w\[\]., ]+$", a) and re.match(r"^    \w+: [\w\[\]., ]+$", b):
            swapped = lines[:i] + [b, a] + lines[i + 2:]
            out.append(("swap fields", "\n".join(swapped)))
    # A new public function (interface change nothing calls).
    out.append(("add function", text + "\n\npublic def zz_added_fn(n: int) -> int:\n    return n + 1\n"))
    # A no-op statement at the top of a function body.
    for m in re.finditer(r"^(public )?def \w+\(.*\)( -> [^:]+)?:\n", text, re.M):
        out.append(("body no-op", text[:m.end()] + "    zz_ok: int = 1\n" + text[m.end():]))
    return out


def main():
    files = sorted(PRISTINE)
    stats = {"built": 0, "rejected": 0, "compared": 0}
    bad = 0
    for step in range(1, STEPS + 1):
        for f, t in PRISTINE.items():
            open(os.path.join(TREE, f), "w").write(t)
        warm = build(CACHE, os.path.join(WORK, "warm.bin"))
        if warm[0] != 0:
            print(f"pristine warm build failed at step {step}: {warm[1][:400]}", flush=True)
        whats = []
        for _ in range(1 if rng.random() < 0.7 else 2):
            f = rng.choice(files)
            path = os.path.join(TREE, f)
            cands = mutations(open(path).read())
            name, new = rng.choice(cands)
            open(path, "w").write(new)
            whats.append(f"{f}: {name}")
        what = "; ".join(whats)
        fresh_cache = os.path.join(WORK, "fresh")
        shutil.rmtree(fresh_cache, ignore_errors=True)
        inc = build(CACHE, os.path.join(WORK, "inc.bin"))
        cold = build(fresh_cache, os.path.join(WORK, "cold.bin"))
        if inc[0] != cold[0] or (inc[0] != 0 and inc[1] != cold[1]):
            bad += 1
            print(f"MISMATCH(build) step {step} ({what}): inc rc={inc[0]} cold rc={cold[0]}\n  inc: {inc[1][:500]}\n  cold: {cold[1][:500]}", flush=True)
            shutil.copytree(TREE, os.path.join(WORK, f"mismatch-{step}"))
            continue
        if cold[0] != 0:
            stats["rejected"] += 1
            print(f"ok step {step} ({what}) both rejected", flush=True)
            continue
        stats["built"] += 1
        bi, bc = behaviour(os.path.join(WORK, "inc.bin")), behaviour(os.path.join(WORK, "cold.bin"))
        stats["compared"] += len(bc)
        diffs = [(a[0], a[1]) for a, b in zip(bi, bc) if a != b]
        if diffs:
            bad += 1
            print(f"MISMATCH(run) step {step} ({what}): {len(diffs)} script runs differ, e.g. {diffs[:3]}", flush=True)
            shutil.copytree(TREE, os.path.join(WORK, f"mismatch-{step}"))
        else:
            print(f"ok step {step} ({what}) built, {len(bc)} runs agree", flush=True)
    print(f"DONE steps={STEPS} mismatches={bad} built={stats['built']} rejected={stats['rejected']} runs_compared={stats['compared']}")
    sys.exit(1 if bad else 0)


main()
