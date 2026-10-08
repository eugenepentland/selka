#!/usr/bin/env python3
"""Extend S1 differential fuzzing with Wave A's whole-list mut rebinding.

Every mut case begins with an observable pure whole-list rebind, an independent
old-value snapshot and a readonly source snapshot. Random operations add
conditional, loop and forwarding rebinds, including record-field arguments.
The S1 harness compares old release with core debug, release and fact
verification. This wrapper enables leak checks and rejects incomplete runs.
All normal S1 fuzz arguments are accepted; use --features mut,records,alias.
"""
import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[3]
REBINDS = """

def assign_only(xs: mut list[int], source: list[int]):
    xs = source


def replace_path(xs: mut list[int], source: list[int], choose: bool, k: int):
    xs.append(k % 1009)
    if choose:
        xs = source
    xs.append((k + 1) % 1009)


def replace_loop(xs: mut list[int], k: int):
    for phase in range(k % 4):
        xs.append(phase)
        xs = [(k + phase) % 1009]
        xs.append(phase)


def replace_forward(xs: mut list[int], source: list[int], choose: bool, k: int):
    replace_path(mut xs, source, choose, k)
"""


class QualificationError(Exception):
    pass


def install(s1):
    """Extend the generator without changing the inherited S1 harness."""
    s1.MUT += REBINDS

    class Gen(s1.Gen):
        def program(self):
            source = super().program()
            if "mut" not in self.f or "scalar" in self.f:
                return source
            lines = source.splitlines()
            position = next(i for i, line in enumerate(lines) if line.startswith("    ys = ")) + 1
            lines[position:position] = [
                "    wave_a_saved = xs",
                "    wave_a_source = ys",
                "    assign_only(mut xs, wave_a_source)",
                "    xs.append((seed + 17) % 1009)",
                "    acc = (acc + fold(wave_a_saved) * 3 + fold(wave_a_source) * 5 + fold(xs) * 7) % 1000003",
            ]
            return "\n".join(lines) + "\n"

        def ops_mut(self):
            targets = ["xs", "ys"]
            if "records" in self.f or "unions" in self.f:
                targets += ["b.items", "c.items"]
            target = self.r.choice(targets)
            source = self.r.choice(["xs", "ys"])
            choose = "(%s) %% 2 == 0" % self.expr()
            k = self.expr()
            return [
                [f"assign_only(mut {target}, {source})"],
                [f"replace_path(mut {target}, {source}, {choose}, {k})"],
                [f"replace_loop(mut {target}, {k})"],
                [f"replace_forward(mut {target}, {source}, {choose}, {k})"],
            ]

    s1.Gen = Gen


def main():
    spec = importlib.util.spec_from_file_location("s1", ROOT / "experiments/new-core-s1-20261005/fuzz.py")
    s1 = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(s1)
    install(s1)
    os.environ["MYL_CORE_LEAKCHECK"] = "1"
    summaries = []
    keep = None
    original_fuzz, original_run = s1.fuzz, s1.run

    def fuzz(args, *arguments):
        nonlocal keep
        keep = args.keep
        stats, reasons = original_fuzz(args, *arguments)
        summaries.append(stats)
        return stats, reasons

    def retain(source):
        if keep and source.exists():
            Path(keep).mkdir(parents=True, exist_ok=True)
            shutil.copy(source, keep)

    def build(argv):
        try:
            done = subprocess.run(argv, capture_output=True, text=True, timeout=60)
        except subprocess.TimeoutExpired as error:
            retain(Path(argv[2]))
            raise QualificationError(f"guest compile timed out after 60s: {argv!r}") from error
        return done.returncode == 0, done.stderr

    def run(argv):
        result = original_run(argv)
        stdout, status, trap = result
        if (stdout == "TIMEOUT" and status == 124) or status < 0 or trap in ("myl-core leakcheck", "R_CORE_FACT"):
            retain(Path(argv[0]).with_suffix(".my"))
            raise QualificationError(f"invalid qualification run: {argv!r}: {result!r}")
        return result

    s1.fuzz, s1.run = fuzz, run
    s1.build = build
    try:
        status = s1.main()
    except QualificationError as error:
        print(error, file=sys.stderr)
        return 1
    if not summaries or any(not stats["cases"] or not stats["compared"] or stats["old_rejected"] or stats["refused"] for stats in summaries):
        print("qualification requires accepted old/new programs and at least one comparison in every feature run", file=sys.stderr)
        return 1
    return status


if __name__ == "__main__":
    raise SystemExit(main())
