#!/usr/bin/env python3
"""S4-F front-end timing, ReleaseFast compilers, shared CPU-10 lock outside.

Uses the unmodified S4 synthetic generator. Every command gets a new exclusive
log. Validation-only and complete typed-tree checking are measured separately;
build and test always use the latter. Each edited request changes one function
against the previous successful request, rather than timing repeated warm checks.
"""
import argparse
import hashlib
import json
import os
import random
from pathlib import Path
import shlex
import shutil
import statistics
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
GENERATOR = ROOT / "experiments/new-core-s4-20261006/gen_program.py"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


class Runner:
    def __init__(self, evidence):
        self.evidence = evidence
        self.ordinal = 0

    def run(self, label, command, timed=False):
        self.ordinal += 1
        log = self.evidence / f"command-{self.ordinal:04d}-{label}.log"
        argv = ["taskset", "-c", "10", *map(str, command)] if timed else list(map(str, command))
        started = time.perf_counter()
        result = subprocess.run(argv, capture_output=True, text=True)
        seconds = time.perf_counter() - started
        with log.open("x") as stream:
            stream.write("$ " + shlex.join(argv) + "\n")
            stream.write(result.stdout + result.stderr)
            stream.write(f"\nexit={result.returncode} elapsed_seconds={seconds:.9f}\n")
        if result.returncode:
            raise RuntimeError(f"{label} failed; retained {log}")
        work = []
        for line in result.stderr.splitlines():
            if line.startswith("{"):
                try:
                    work.append(json.loads(line))
                except json.JSONDecodeError:
                    pass
        return {"seconds": seconds, "log": str(log.relative_to(ROOT)), "receipts": work}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--core", type=Path, required=True)
    parser.add_argument("--old", type=Path, required=True)
    parser.add_argument("--evidence", type=Path, required=True)
    parser.add_argument("--work", type=Path, required=True)
    parser.add_argument("--sizes", nargs="+", type=int, default=[120, 1200, 2400, 4800])
    parser.add_argument("--rounds", type=int, default=3)
    parser.add_argument("--counterbalance", action="store_true")
    args = parser.parse_args()
    args.core, args.old = args.core.resolve(), args.old.resolve()
    args.evidence, args.work = args.evidence.resolve(), args.work.resolve()
    args.evidence.mkdir(parents=True, exist_ok=False)
    args.work.mkdir(parents=True, exist_ok=True)
    runner = Runner(args.evidence)
    summary = {
        "source_commit": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
        "compiler_mode": "ReleaseFast",
        "core": {"path": str(args.core), "sha256": digest(args.core)},
        "old": {"path": str(args.old), "sha256": digest(args.old)},
        "cpu": 10, "edit_rounds": args.rounds, "counterbalanced": args.counterbalance, "rows": [],
    }
    for size in args.sizes:
        project = args.work / f"synthetic-{size}"
        runner.run("generate", [sys.executable, GENERATOR, size, project])
        source = project / "main.my"
        files = list(project.glob("*.my"))
        row = {"modules": size, "files": len(files),
               "lines": sum(len(path.read_text().splitlines()) for path in files),
               "bytes": sum(path.stat().st_size for path in files), "roles": {}}
        commands = {}
        for role in ("old", "validation", "typed"):
            cache = args.work / f"cache-{size}-{role}"
            shutil.rmtree(cache, ignore_errors=True)
            if role == "old":
                command = [args.old, "check-project", source, f"--cache-dir={cache}", "--timings=json"]
            else:
                command = [args.core, "check", source, "--cache-dir", cache, "--stats", "--timings=json"]
                if role == "typed":
                    command.append("--typed")
            commands[role] = command
            cold = runner.run(f"{size}-{role}-cold", command, True)
            warm = [runner.run(f"{size}-{role}-warm", command, True) for _ in range(args.rounds)]
            row["roles"][role] = {"cold": cold, "warm": warm, "edits": [],
                                  "cold_seconds": cold["seconds"],
                                  "warm_seconds": statistics.median(item["seconds"] for item in warm)}
        for round_index in range(args.rounds):
            edited = size // 2
            generate = [sys.executable, GENERATOR, size, project, "--edit", edited]
            runner.run("edit-one-function", generate)
            # Every measured source version must be new. Alternating baseline
            # and --edit would replay old's earlier whole-project verdict on
            # the second and third edits, and measure a warm check instead.
            file = project / f"p{edited // 100}.my"
            original = 7 + edited % 13 + 1000
            multiplier = 7 + edited % 13 + 1000 * (round_index + 1)
            text = file.read_text()
            needle = f"out.append((j * {original}) % 101)"
            assert text.count(needle) == 1
            text = text.replace(needle, f"out.append((j * {multiplier}) % 101)")
            file.write_text(text)
            row.setdefault("edit_versions", []).append({"function": f"m{edited}_build", "multiplier": multiplier, "sha256": digest(file)})
            order = ("old", "validation", "typed")
            if args.counterbalance:
                offset = round_index % len(order)
                order = order[offset:] + order[:offset]
            row.setdefault("edit_role_order", []).append(list(order))
            for role in order:
                item = runner.run(f"{size}-{role}-edited", commands[role], True)
                row["roles"][role]["edits"].append(item)
        for data in row["roles"].values():
            data["edited_seconds"] = statistics.median(item["seconds"] for item in data["edits"])
        row["validation_at_or_below_old"] = row["roles"]["validation"]["edited_seconds"] <= row["roles"]["old"]["edited_seconds"]
        row["edited_96k_gate"] = size != 2400 or row["roles"]["validation"]["edited_seconds"] <= 0.45
        old_edits = row["roles"]["old"]["edits"]
        new_edits = row["roles"]["validation"]["edits"]
        paired = [new["seconds"] - old["seconds"] for old, new in zip(old_edits, new_edits)]
        rng = random.Random(44000 + size)
        bootstrap = sorted(statistics.median(rng.choices(paired, k=len(paired))) for _ in range(10000))
        row["paired_validation_minus_old"] = {"samples": paired,
            "median": statistics.median(paired), "stdev": statistics.stdev(paired) if len(paired) > 1 else 0,
            "median_bootstrap_95_percent": [bootstrap[250], bootstrap[9749]]}
        summary["rows"].append(row)
        (args.evidence / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
        print(json.dumps({"lines": row["lines"], **{role: {name: round(data[name], 6) for name in ("cold_seconds", "warm_seconds", "edited_seconds")} for role, data in row["roles"].items()}, "gate": row["validation_at_or_below_old"] and row["edited_96k_gate"]}), flush=True)
    summary["qualified"] = all(row["validation_at_or_below_old"] and row["edited_96k_gate"] for row in summary["rows"])
    (args.evidence / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    return 0 if summary["qualified"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
