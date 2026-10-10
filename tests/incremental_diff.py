#!/usr/bin/env python3
"""Differential check of incremental `mylang check` against a cold check.

A seeded sequence of source mutations is applied to a copy of a small project
(`tests/fixtures/incremental/`: records nested in lists, dictionaries, Options,
tuples, unions and record fields, an enum, a recursive record and a facade
re-export). Before every step the cache is warmed on the unmutated project; the
step then applies one or two mutations and runs `check` twice, once with the
persistent cache and once with `--no-cache`. Exit status, stdout and stderr
must be byte-identical: any difference means the cache served a stale answer.

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

DEF = re.compile(r"^(public )?func (\w+)\((.*)\)( -> [^:]+)?:$", re.M)
FIELD = re.compile(r"^    (\w+): ([\w\[\]., ?]+)$", re.M)
CASE = re.compile(r"^    (\w+)(\(.*\)|: [\w\[\]., ?]+)?(,?)$", re.M)
LITERAL = re.compile(r"(?<![\w.])(\d+)(?![\w.])")


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
    parser.add_argument("--entry", default="main.my")
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
    pristine = {str(path.relative_to(tree)): path.read_text() for path in sorted(tree.rglob("*.my")) if ".mylang-cache" not in path.relative_to(tree).parts}
    environment = dict(os.environ)

    def check(cached):
        if args.strict_campaign:
            corpus.isolate_baseline(tree)
        flags = [f"--cache-dir={cache}"] if cached else ["--no-cache"]
        done = subprocess.run([compiler, "check", args.entry] + flags, cwd=tree, capture_output=True, env=environment, timeout=300)
        if args.strict_campaign:
            corpus.require_worker(done)
        return done.returncode, done.stdout, done.stderr

    def restore():
        for name, text in pristine.items():
            (tree / name).write_text(text)

    try:
        return steps(compiler, args, rng, work, tree, pristine, retained, exported, check, restore)
    finally:
        if exported is not None:
            exported.save(args.corpus_out)


def steps(compiler, args, rng, work, tree, pristine, retained, exported, check, restore):
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
        if cached == cold:
            continue
        mismatches += 1
        print(f"MISMATCH step {step} ({'; '.join(applied)}): cached status {cached[0]}, cold status {cold[0]}")
        print("  cached stderr: " + cached[2].decode(errors="replace")[:600].replace("\n", "\n    "))
        print("  cold   stderr: " + cold[2].decode(errors="replace")[:600].replace("\n", "\n    "))
        if args.keep and mismatches <= 5:
            snapshot = Path(args.keep) / f"mismatch-{step}"
            shutil.rmtree(snapshot, ignore_errors=True)
            shutil.copytree(tree, snapshot, ignore=shutil.ignore_patterns(".mylang-cache"))
    print(f"incremental-diff: {total_steps} steps (seed {args.seed}), {mismatches} mismatches; cold check clean {outcomes['clean']}, rejected {outcomes['rejected']}")
    return 1 if mismatches else 0


if __name__ == "__main__":
    sys.exit(main())
