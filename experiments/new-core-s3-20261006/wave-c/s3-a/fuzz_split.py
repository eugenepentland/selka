#!/usr/bin/env python3
"""Deterministic differential split-key loops, managed returns and source snapshots."""
import argparse
import json
import os
from pathlib import Path
import random
import subprocess

ROOT = Path(__file__).resolve().parents[4]


def program(rng, index):
    vocabulary = ["a", "b", "café", "naïve", "Ω", "😀", "x\u00a0y", "collision002553", "collision005a0e"]
    vocabulary += [f"long{j:02d}éabcdefghijklmnop" for j in range(rng.randrange(2, 15))]
    text = "".join(rng.choice(vocabulary) + rng.choice([" ", "\t", "\n", "\r", "\v", "\f", "  "]) for _ in range(rng.randrange(0, 55)))
    text += rng.choice(["", "tail", "é", " "])
    literal = json.dumps(text, ensure_ascii=False).replace("\\f", "\\x0c").replace("\\u000b", "\\x0b")
    return f'''module split_{index:04d}

def number(text: str) -> int:
    match int(text):
        case Some(value):
            return value
        case None:
            return 0

def tally(text: str, seed: int) -> dict[str, int]:
    counts: dict[str, int] = {{}}
    for word in text.split():
        text = "rebound"
        counts[word] = counts[word] + 1 if word in counts else 1
        if len(counts) == seed % 7:
            continue
        if len(counts) > seed % 31 + 2:
            break
    return counts

def score(counts: dict[str, int]) -> int:
    value = len(counts)
    for key in counts:
        value += len(key) * counts[key]
        for octet in key.encode():
            value += octet
    return value

def main(args: list[str], out: Stream) -> int:
    seed = number(args[0])
    original = {literal}
    owned = "".join([original, " ", original])
    counts = tally(owned, seed)
    snapshot = counts
    counts["post"] = seed + 1
    _ = counts.pop("post")
    for word in "post fresh café collision005a0e".split():
        counts[word] = counts[word] + 1 if word in counts else 1
    escaped: list[str] = []
    for word in original.split():
        escaped.append(word)
    value = score(counts) + score(snapshot) + len(escaped)
    out.print(value)
    return 0
'''


def invoke(argv, path, environment=None):
    result = subprocess.run(list(map(str, argv)), capture_output=True, text=True, env=environment)
    record = {"command": list(map(str, argv)), "status": result.returncode,
              "stdout": result.stdout, "stderr": result.stderr}
    path.write_text(json.dumps(record, indent=2) + "\n")
    if result.returncode:
        raise RuntimeError(f"nonzero command: {record}")
    return record


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cases", type=int, default=50)
    parser.add_argument("--seed", type=int, default=20261006)
    parser.add_argument("--evidence", type=Path, required=True)
    args = parser.parse_args()
    evidence = args.evidence.resolve()
    evidence.relative_to(ROOT)
    evidence.mkdir(parents=True, exist_ok=False)
    cache = ROOT / ".mylang-cache/s3-a" / evidence.name
    cache.mkdir(parents=True, exist_ok=False)
    summary = {"qualified": False, "seed": args.seed, "cases": args.cases, "compared": 0, "mismatch": 0, "error": None}
    rng = random.Random(args.seed)
    environment = dict(os.environ, MYL_CORE_LEAKCHECK="1")
    try:
        for case in range(args.cases):
            directory = evidence / f"{case:04d}"
            directory.mkdir()
            source = directory / f"split_{case:04d}.my"
            source.write_text(program(rng, case))
            binary = cache / "old"
            invoke([ROOT / ".mylang-cache/s3-a/oracle/mylang", "build", source, "-o", binary, "--release", "--cache-dir", cache / "old-cache"], directory / "build-old.json")
            expected = [invoke([binary, seed], directory / f"old-{seed}.json") for seed in (0, 1, 3, 7, 23)]
            for name, flags in [("debug", []), ("release", ["--release"]), ("verify", ["--release", "--verify-facts"])]:
                binary = cache / name
                invoke([ROOT / "zig-out/bin/mylang-core", "build", source, "-o", binary, "--cache-dir", cache / "core-cache", *flags], directory / f"build-{name}.json")
                for seed, before in zip((0, 1, 3, 7, 23), expected):
                    after = invoke([binary, seed], directory / f"{name}-{seed}.json", environment)
                    summary["compared"] += 1
                    if before["stdout"] != after["stdout"] or before["stderr"] or after["stderr"]:
                        summary["mismatch"] += 1
                        raise RuntimeError(f"mismatch case={case} mode={name} seed={seed}")
            print(f"case={case:04d} matched debug/release/verify with leakcheck", flush=True)
        summary["qualified"] = True
    except Exception as error:
        summary["error"] = str(error)
        raise
    finally:
        (evidence / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")


if __name__ == "__main__":
    main()
