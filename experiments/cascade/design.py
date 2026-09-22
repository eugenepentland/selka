#!/usr/bin/env python3
"""Run one designer session and freeze the arm it produces.

A designer session is the same shape as a maintainer session — one fresh
``dsh --profile headless`` agent in a working copy — but its input is a design
brief instead of a change request, and its output is a whole arm:

    python3 experiments/cascade/design.py --arm P1
    python3 experiments/cascade/design.py --arm P1 --dry-run
    python3 experiments/cascade/design.py --arm P1 --freeze-only   # gate what is there

The working copy holds only the baseline port, the brief, the docs and the
compiler. When the session ends the result is gated with ``arm_gate.py`` (79
tests, 17 goldens, the differential census) and, only if it passes, copied to
``designs/<arm>/`` with its ``DESIGN.md`` and ``evidence/`` (the gate report and
the designer session's usage). The baseline arm B is never produced this way.
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
REPO = HERE.parents[1]
DESIGNS = HERE / "designs"
WORK = HERE / "work" / "design"


def build(arm: str) -> Path:
    brief = DESIGNS / arm / "BRIEF.md"
    if not brief.is_file():
        raise SystemExit(f"design: no brief at {brief}")
    directory = WORK / arm
    if directory.exists():
        shutil.rmtree(directory)
    (directory / "bin").mkdir(parents=True)
    shutil.copytree(
        DESIGNS / "B", directory / "project", symlinks=False,
        ignore=shutil.ignore_patterns(".mylang-cache", "__pycache__", "DESIGN.md", "evidence"),
    )
    for name, target in (("mylang", runlib.COMPILER), ("qbe", runlib.QBE)):
        os.symlink(target, directory / "bin" / name)
    shutil.copy2(brief, directory / "BRIEF.md")
    docs = REPO / "docs"
    if docs.is_dir():
        shutil.copytree(docs, directory / "docs", symlinks=False, ignore=shutil.ignore_patterns("__pycache__"))
    return directory


def gate(arm: str, project: Path, destination: Path) -> dict:
    report_path = destination / "evidence" / "gate.json"
    result = subprocess.run(
        [sys.executable, str(HERE / "arm_gate.py"), str(project), "--label", arm, "--json", str(report_path)],
        capture_output=True, text=True,
    )
    print(result.stdout, end="")
    if result.returncode != 0:
        print(result.stderr, file=sys.stderr, end="")
    return json.loads(report_path.read_text()) if report_path.is_file() else {"passed": False}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--arm", required=True, choices=["P1", "P2"])
    parser.add_argument("--timeout", type=float, default=14400.0)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--freeze-only", action="store_true", help="gate and freeze an existing working copy")
    args = parser.parse_args()
    directory = WORK / args.arm
    if not args.freeze_only:
        directory = build(args.arm)
        brief = (directory / "BRIEF.md").read_text()
        if args.dry_run:
            print(json.dumps({"work_dir": str(directory), "command": ["dsh", "--profile", "headless", brief]}, indent=2))
            return 0
        session = runlib.launch(directory, brief, args.timeout)
        (directory / "session.txt").write_text(session.pop("stdout"))
        (directory / "session.err").write_text(session.pop("stderr"))
        (directory / "designer.json").write_text(
            json.dumps(
                {
                    "version": 1,
                    "arm": args.arm,
                    "finished_utc": datetime.now(timezone.utc).isoformat(),
                    "session": {
                        **session,
                        **runlib.read_session_logs(directory, datetime.fromisoformat(session["started_utc"])),
                    },
                },
                indent=2,
            )
            + "\n"
        )
    if not (directory / "project" / "main.my").is_file():
        raise SystemExit(f"design: no project under {directory}")
    destination = DESIGNS / args.arm
    (destination / "evidence").mkdir(parents=True, exist_ok=True)
    if (directory / "DESIGN.md").is_file():
        shutil.copy2(directory / "DESIGN.md", destination / "DESIGN.md")
    elif (directory / "project" / "DESIGN.md").is_file():
        shutil.copy2(directory / "project" / "DESIGN.md", destination / "DESIGN.md")
    else:
        print("design: no DESIGN.md in the working copy", file=sys.stderr)
    if (directory / "designer.json").is_file():
        shutil.copy2(directory / "designer.json", destination / "evidence" / "designer.json")
    report = gate(args.arm, directory / "project", destination)
    if report.get("passed"):
        for name in ("main.my", "CONTRACT.md", "README.md", "DESIGN.md"):
            if (directory / "project" / name).is_file():
                shutil.copy2(directory / "project" / name, destination / name)
        for name in ("tests", "sexpr"):
            if (directory / "project" / name).is_dir():
                if (destination / name).exists():
                    shutil.rmtree(destination / name)
                shutil.copytree(directory / "project" / name, destination / name)
        print(f"design: {args.arm} frozen at {destination}")
        return 0
    print(f"design: {args.arm} did not pass the gate; nothing frozen", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
