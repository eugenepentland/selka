#!/usr/bin/env python3
"""Differential check of incremental `selka check` against a cold check.

A seeded sequence of source mutations is applied to a copy of a small project
(`tests/fixtures/incremental/`: records nested in lists, dictionaries, Options,
tuples, unions and record fields, an enum, a recursive record and a facade
re-export). Before every step the cache is warmed on the unmutated project; the
step then applies one or two mutations and runs `check` twice, once with the
persistent cache and once with `--no-cache`. Exit status, stdout and stderr
must be byte-identical: any difference means the cache served a stale answer.
The one exception is the cache count in the success line `check: ok (N modules,
M cached)` (FR-011), which reports reuse by design; the module count still
has to agree.

A step that edits a module declaring a constant a function computes
(`limits.selka`: `const STEP: int = scale(4)`) also runs the entry, built once on
the unmutated project and then again after the edit, with the cache and with
`--no-cache`: a reader folds the constant's value, so a cached build that kept
the old value exits with another status although every check agrees
(CONSTSTALE). The `evaluated body` mutation edits such a function's body.

usage: incremental_diff.py [--steps N] [--seed S] [--project DIR] [--keep DIR] COMPILER

Exits 0 when every step agrees, 1 on a mismatch (the mutated sources of the
first mismatches are copied under --keep when given), 2 on a harness error.
"""
import argparse
import os
import random
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
import differential_corpus as corpus

# The success line of a clean check counts reused modules, which differs between a
# warm cache and --no-cache by design (FR-011); everything else must match.
CACHED_COUNT = re.compile(rb"(check: ok \([0-9]+ modules?, )[0-9]+ cached\)")

DEF = re.compile(r"^(public )?func (\w+)\((.*)\)( -> [^:]+)?:$", re.M)
FIELD = re.compile(r"^    (\w+): ([\w\[\]., ?]+)$", re.M)
CASE = re.compile(r"^    (\w+)(\(.*\)|: [\w\[\]., ?]+)?(,?)$", re.M)
LITERAL = re.compile(r"(?<![\w.])(\d+)(?![\w.])")
# A constant whose value a function computes, and the step a constant's function body takes (`limits.selka`).
COMPUTED = re.compile(r"^(public )?const \w+: [\w\[\]]+ = [\w.]+\(", re.M)
EVALUATED = re.compile(r"(?<=index \* )(\d+)")


def mutations(text, rng):
    """Every candidate (name, new_text) for one file."""
    out = []
    for m in DEF.finditer(text):
        line = m.group(0)
        if m.group(4) and "-> int" in m.group(4):
            out.append(("return int->bool", text.replace(line, line.replace("-> int", "-> bool"), 1)))
        if ": int" in m.group(3):
            out.append(("param int->float", text.replace(line, line.replace(": int", ": float", 1), 1)))
        if "mut " in m.group(3):
            out.append(("drop mut", text.replace(line, line.replace("mut ", "", 1), 1)))
        if m.group(3):
            out.append(("add param", text.replace(line, line.replace(")", ", extra_param: int)", 1), 1)))
        out.append(("rename def", text.replace(line, line.replace(f"func {m.group(2)}(", f"func {m.group(2)}_renamed(", 1), 1)))
        if m.group(1):
            out.append(("unpublic", text.replace(line, line[len("public "):], 1)))
        out.append(("body type error", text.replace(line + "\n", line + '\n    const zz_bad: int = "x"\n', 1)))
        out.append(("body no-op", text.replace(line + "\n", line + "\n    const zz_ok: int = 1\n", 1)))
    for m in FIELD.finditer(text):
        line = m.group(0)
        out.append(("rename field", text.replace(line, f"    {m.group(1)}_x: {m.group(2)}", 1)))
        if m.group(2) == "int":
            out.append(("field int->float", text.replace(line, f"    {m.group(1)}: float", 1)))
            out.append(("field int->bool", text.replace(line, f"    {m.group(1)}: bool", 1)))
        if m.group(2).endswith("[]"):
            out.append(("field list->Option", text.replace(line, f"    {m.group(1)}: {m.group(2)[:-2]}?", 1)))
    for m in CASE.finditer(text):
        line = m.group(0)
        if FIELD.fullmatch(line):
            continue
        out.append(("rename case", text.replace(line, f"    {m.group(1)}_x{m.group(2) or ''}{m.group(3)}", 1)))
        if m.group(2) and m.group(2).startswith(": "):
            out.append(("case payload -> int", text.replace(line, f"    {m.group(1)}: int{m.group(3)}", 1)))
    for m in EVALUATED.finditer(text):
        out.append(("evaluated body", text[: m.start()] + str(int(m.group(1)) + 1) + text[m.end():]))
    for m in LITERAL.finditer(text):
        if rng.random() < 0.1:
            out.append(("int literal", text[: m.start()] + str(int(m.group(1)) + 7) + text[m.end():]))
    return out


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("compiler")
    parser.add_argument("--steps", type=int, default=60)
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--project", default=str(Path(__file__).resolve().parent / "fixtures" / "incremental"))
    parser.add_argument("--entry", default="main.selka")
    parser.add_argument("--keep", default=None)
    parser.add_argument("--corpus-out", type=Path)
    parser.add_argument("--replay-corpus", type=Path)
    parser.add_argument("--strict-campaign", action="store_true")
    args = parser.parse_args()
    if args.strict_campaign and not 0 <= args.steps <= corpus.MAX_CASES:
        parser.error("strict campaign steps must be 0.." + str(corpus.MAX_CASES))
    compiler = str(Path(args.compiler).resolve())
    rng = random.Random(args.seed)
    work = Path(tempfile.mkdtemp(prefix="incremental-diff-"))
    try:
        return run(compiler, args, rng, work)
    except (corpus.CorpusError, subprocess.TimeoutExpired) as error:
        if not args.strict_campaign and not isinstance(error, corpus.CorpusError):
            raise
        print("incremental-diff: harness error: " + str(error), file=sys.stderr)
        return 2
    finally:
        shutil.rmtree(work, ignore_errors=True)


def run(compiler, args, rng, work):
    tree = work / "tree"
    cache = work / "cache"
    retained = corpus.Corpus.load(args.replay_corpus, "incremental-v1") if args.replay_corpus else None
    if retained is not None:
        retained.restore(tree)
    else:
        corpus.copy_baseline(args.project, tree, strict=args.strict_campaign)
    if args.strict_campaign:
        corpus.safe_path(args.entry)
        corpus.isolate_baseline(tree)
    exported = corpus.Corpus.capture(tree, "incremental-v1") if args.corpus_out else None
    pristine = {str(path.relative_to(tree)): path.read_text() for path in sorted(tree.rglob("*.selka")) if ".selka-cache" not in path.relative_to(tree).parts}
    environment = dict(os.environ)

    def check(cached):
        if args.strict_campaign:
            corpus.isolate_baseline(tree)
        flags = [f"--cache-dir={cache}"] if cached else ["--no-cache"]
        done = subprocess.run([compiler, "check", args.entry] + flags, cwd=tree, capture_output=True, env=environment, timeout=300)
        if args.strict_campaign:
            corpus.require_worker(done)
        return done.returncode, done.stdout, CACHED_COUNT.sub(rb"\1N cached)", done.stderr)

    def restore():
        for name, text in pristine.items():
            (tree / name).write_text(text)

    def run_entry(cached):
        flags = [f"--cache-dir={cache}"] if cached else ["--no-cache"]
        done = subprocess.run([compiler, "run", args.entry] + flags, cwd=tree, capture_output=True, env=environment, timeout=300)
        return done.returncode, done.stdout

    def runs(changes):
        """The entry run cached and cold after `changes`, with a build of the unmutated sources in the cache first."""
        edited = {name: (tree / name).read_bytes() for name in changes}
        restore()
        run_entry(True)
        for name, data in edited.items():
            (tree / name).write_bytes(data)
        return run_entry(True), run_entry(False)

    try:
        return steps(compiler, args, rng, work, tree, pristine, retained, exported, check, restore, runs)
    finally:
        if exported is not None:
            exported.save(args.corpus_out)


def steps(compiler, args, rng, work, tree, pristine, retained, exported, check, restore, runs):
    status, _, stderr = check(False)
    if status != 0:
        print(f"incremental-diff: the unmutated project does not check:\n{stderr.decode(errors='replace')}")
        return 2
    mismatches = 0
    outcomes = {"clean": 0, "rejected": 0}
    replay = retained.cases if retained is not None else []
    total_steps = len(replay) + args.steps
    for step in range(1, total_steps + 1):
        if retained is not None:
            retained.restore(tree)
        else:
            restore()
        check(True)
        applied = []
        changes = {}
        if step <= len(replay):
            retained.restore(tree, replay[step - 1])
            applied = replay[step - 1]["labels"]
            changes = {row["path"]: corpus.decode_file(row) for row in replay[step - 1]["changes"]}
        else:
            for _ in range(1 if rng.random() < 0.6 else 2):
                name = rng.choice(sorted(pristine))
                text = (tree / name).read_text()
                candidates = mutations(text, rng)
                if not candidates:
                    continue
                label, mutated = rng.choice(candidates)
                (tree / name).write_text(mutated)
                changes[name] = (tree / name).read_bytes()
                applied.append(f"{name}: {label}")
        if exported is not None:
            exported.append(exported.changes(tree), applied)
        cached = check(True)
        cold = check(False)
        outcomes["clean" if cold[0] == 0 else "rejected"] += 1
        # A strict campaign replays untrusted corpora: it checks them and runs nothing.
        if cached == cold and cold[0] == 0 and not args.strict_campaign and any(COMPUTED.search(data.decode(errors="replace")) for data in changes.values()):
            ran_cached, ran_cold = runs(changes)
            outcomes["runs"] = outcomes.get("runs", 0) + 1
            if ran_cached != ran_cold:
                mismatches += 1
                print(f"MISMATCH step {step} ({'; '.join(applied)}): cached run status {ran_cached[0]}, cold run status {ran_cold[0]}")
                continue
        if cached == cold:
            continue
        mismatches += 1
        print(f"MISMATCH step {step} ({'; '.join(applied)}): cached status {cached[0]}, cold status {cold[0]}")
        print("  cached stderr: " + cached[2].decode(errors="replace")[:600].replace("\n", "\n    "))
        print("  cold   stderr: " + cold[2].decode(errors="replace")[:600].replace("\n", "\n    "))
        if args.keep and mismatches <= 5:
            snapshot = Path(args.keep) / f"mismatch-{step}"
            shutil.rmtree(snapshot, ignore_errors=True)
            shutil.copytree(tree, snapshot, ignore=shutil.ignore_patterns(".selka-cache"))
    print(f"incremental-diff: {total_steps} steps (seed {args.seed}), {mismatches} mismatches; cold check clean {outcomes['clean']}, rejected {outcomes['rejected']}, runs compared {outcomes.get('runs', 0)}")
    return 1 if mismatches else 0


if __name__ == "__main__":
    sys.exit(main())
