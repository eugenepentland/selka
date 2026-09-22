#!/usr/bin/env python3
"""Run the transfer probe for one arm: can one contract predict the whole output?

A fresh agent is given the arm's AST module and its literal/unit facts — every
module under ``sexpr/`` except the printer — and nothing else that could answer
the question. It is asked to write down what ``main.my -- <input> --render``
would print for ten inputs, without running a printer (there is none in its
working copy) and without seeing the goldens.

    python3 experiments/cascade/probe.py --arm B --n 1
    python3 experiments/cascade/probe.py --arm B --n 1 --dry-run
    python3 experiments/cascade/probe.py --arm B --n 1 --score-only

The expected answers are produced by the frozen arm itself, so the probe measures
whether the agent could reconstruct behaviour from the contract, not whether the
contract matches some other oracle. ``probes/<arm>/<n>.json`` records the
answers, the score, the tokens and the bytes the agent read.
"""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

import run as runlib

HERE = Path(__file__).resolve().parent
WORK = HERE / "work" / "probe"
PROBES = HERE / "probes"

QUESTIONS = [
    "10mil",
    "100nF",
    "220k",
    "3.3V",
    "10%",
    "1.0mm",
    "(pad 1 smd rect (pos -1.25 1.75) (size 0.7 0.3))",
    "(fits-exactly alpha bravo charlie delta echo foxtrot golf hotel india x)",
    "204928-0301.stp",
    "(nested (a (b (c (d)))))",
]

INSTRUCTIONS = """# Transfer probe

Below are ten S-expression sources. For each one, write the exact bytes that

```sh
bin/mylang run main.my -- <source.sexp> --render
```

would print for a file containing exactly that source, not counting the single
trailing newline the CLI adds. One answer per line, in order, in `answers.txt`;
write embedded newlines as the two characters `\\n` and nothing else.

You have the reader's contract — its AST module and its literal, unit and number
rules — and no printer, no parser CLI and no way to run this. The point is
whether the contract is enough to predict the output. Answer from the contract;
do not fetch the port from anywhere else and do not spawn subagents.

```text
{questions}
```
"""


def probe_arm(arm: str) -> Path:
    candidate = Path(arm)
    if candidate.is_dir():
        return candidate.resolve()
    return (HERE / "designs" / arm).resolve()


def build(arm: str, run: int) -> Path:
    project = probe_arm(arm)
    if not (project / "sexpr").is_dir():
        raise SystemExit(f"probe: {project} has no sexpr/")
    directory = WORK / arm / str(run)
    if directory.exists():
        shutil.rmtree(directory)
    (directory / "sexpr").mkdir(parents=True)
    for path in sorted((project / "sexpr").glob("*.my")):
        if "print" in path.name:
            continue  # the printer is the thing being predicted
        shutil.copy2(path, directory / "sexpr" / path.name)
    if (project / "CONTRACT.md").is_file():
        shutil.copy2(project / "CONTRACT.md", directory / "CONTRACT.md")
    (directory / "QUESTIONS.md").write_text(INSTRUCTIONS.format(questions="\n".join(QUESTIONS)))
    return directory


def expected(arm: str) -> list[str]:
    """The frozen arm's own renderings, one per question."""
    project = probe_arm(arm)
    scratch = HERE / ".cache" / "probe"
    scratch.mkdir(parents=True, exist_ok=True)
    binary = runlib.COMPILER
    answers = []
    for index, question in enumerate(QUESTIONS):
        source = scratch / f"q{index}.sexp"
        source.write_text(question + "\n")
        result = subprocess.run(
            [str(binary), "run", str(project / "main.my"), "--", str(source), "--render"],
            cwd=scratch, capture_output=True, text=True,
        )
        if result.returncode != 0:
            raise SystemExit(f"probe: arm failed on {question!r}: {result.stderr}")
        text = result.stdout[:-1] if result.stdout.endswith("\n") else result.stdout
        answers.append(text)
    return answers


def read_answers(directory: Path) -> list[str]:
    path = directory / "answers.txt"
    if not path.is_file():
        return []
    lines = [line for line in path.read_text().splitlines()]
    return [line.replace("\\n", "\n") for line in lines]


def score(arm: str, run: int, directory: Path, launched: dict | None) -> dict:
    wants = expected(arm)
    got = read_answers(directory)
    rows = []
    correct = 0
    for index, want in enumerate(wants):
        answer = got[index] if index < len(got) else ""
        ok = answer == want
        correct += 1 if ok else 0
        rows.append({"input": QUESTIONS[index], "expected": want, "answer": answer, "correct": ok})
    usage = {"bytes_read": 0, "read_calls": 0, "tool_calls": {}}
    if launched:
        logs = runlib.read_session_logs(directory, datetime.fromisoformat(launched["started_utc"]))
        usage["tool_calls"] = logs.get("tool_calls", {})
        usage["session"] = logs.get("usage", {})
        usage["models"] = logs.get("models", {})
        usage["bytes_read"] = logs.get("bytes_read", 0)
        usage["read_calls"] = usage["tool_calls"].get("read", 0)
    return {
        "version": 1,
        "arm": arm,
        "run": run,
        "captured_utc": datetime.now(timezone.utc).isoformat(),
        "questions": len(QUESTIONS),
        "correct": correct,
        "score": correct / len(QUESTIONS),
        "rows": rows,
        **usage,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--arm", required=True)
    parser.add_argument("--n", type=int, default=1)
    parser.add_argument("--timeout", type=float, default=3600.0)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--score-only", action="store_true", help="score an existing probe working copy")
    args = parser.parse_args()
    directory = WORK / args.arm / str(args.n)
    launched = None
    if not args.score_only:
        directory = build(args.arm, args.n)
        prompt = (directory / "QUESTIONS.md").read_text()
        if args.dry_run:
            print(json.dumps({"work_dir": str(directory), "command": ["dsh", "--profile", "headless", prompt]}, indent=2))
            return 0
        launched = runlib.launch(directory, prompt, args.timeout)
        (directory / "session.txt").write_text(launched.pop("stdout"))
        (directory / "session.err").write_text(launched.pop("stderr"))
    record = score(args.arm, args.n, directory, launched)
    path = PROBES / args.arm / f"{args.n}.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(record, indent=2) + "\n")
    print(f"{record['correct']}/{record['questions']} correct, {record['bytes_read']} bytes read -> {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
