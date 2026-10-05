#!/usr/bin/env python3
"""Coverage sweep: which functions the new core accepts, and why it refuses the rest.

usage: coverage.py [--core PATH] [--lox DIR]
Runs `mylang-core coverage` on every `.my` file of each corpus and prints, per
corpus, the files the front end rejected alone (module tests, fragments), the
functions accepted (deduplicated by qualified name), and the refusal reasons
ranked by count. A function's reason is the first construct the builder met.
"""
import argparse, collections, glob, os, re, subprocess

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def sweep(core, files):
    done = subprocess.run([core, "coverage"] + files, capture_output=True, text=True)
    frontend, outcomes = [], {}
    for line in done.stdout.splitlines():
        kind, _, rest = line.partition(" ")
        if kind == "frontend":
            frontend.append(rest.partition("\t")[2])
        elif kind == "ok":
            outcomes.setdefault(rest, None)
        elif kind == "refused":
            reason, _, name = rest.partition("\t")
            if outcomes.get(name, "x") is not None:
                outcomes[name] = reason
    return frontend, outcomes


def with_entry(files, scratch):
    """Module files without `main` (tests/lang) get a trivial entry in a scratch copy, so they check."""
    out = []
    for path in files:
        text = open(path).read()
        if "def main(" in text:
            out.append(path)
            continue
        os.makedirs(scratch, exist_ok=True)
        stem = os.path.basename(path)[:-3]
        copy = os.path.join(scratch, stem + ".my")
        with open(copy, "w") as f:
            f.write(text.rstrip("\n") + "\n\n\ndef main() -> int:\n    return 0\n")
        out.append(copy)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--core", default=os.path.join(ROOT, "zig-out/bin/mylang-core"))
    ap.add_argument("--lox", default=None, help="directory of the Lox port sources (branch bench/lox-mylang)")
    args = ap.parse_args()
    corpora = {
        "examples": with_entry(sorted(glob.glob(os.path.join(ROOT, "examples/**/*.my"), recursive=True)), os.path.join(os.environ.get("TMPDIR", "/tmp"), "coverage-examples")),
        "bench/parity": sorted(glob.glob(os.path.join(ROOT, "bench/parity/**/*.my"), recursive=True)),
        "tests/lang": with_entry(sorted(glob.glob(os.path.join(ROOT, "tests/lang/*.my"))), os.path.join(os.environ.get("TMPDIR", "/tmp"), "coverage-entries")),
        "benchmarks/runtime": sorted(glob.glob(os.path.join(ROOT, "benchmarks/runtime/expanded/*/main.my"))),
    }
    if args.lox:
        corpora["lox port"] = sorted(glob.glob(os.path.join(args.lox, "*.my")))
    total = collections.Counter()
    for name, files in corpora.items():
        frontend, outcomes = sweep(args.core, files)
        accepted = sum(1 for reason in outcomes.values() if reason is None)
        reasons = collections.Counter(reason for reason in outcomes.values() if reason is not None)
        total.update(reasons)
        total["(accepted)"] += accepted
        print(f"## {name}: {len(files)} files ({len(frontend)} not checkable alone), {len(outcomes)} functions, {accepted} accepted ({100.0 * accepted / max(1, len(outcomes)):.0f}%)")
        for problem, count in collections.Counter(re.sub(r"^.*?error", "error", p)[:60] for p in frontend).most_common(3):
            print(f"  front end: {count} x {problem}")
        for reason, count in reasons.most_common(12):
            print(f"  {count:5d}  {reason}")
    functions = sum(total.values())
    print(f"## all corpora: {functions} functions, {total['(accepted)']} accepted ({100.0 * total['(accepted)'] / max(1, functions):.0f}%)")
    for reason, count in total.most_common(25):
        if reason != "(accepted)":
            print(f"  {count:5d}  {reason}")


if __name__ == "__main__":
    main()
