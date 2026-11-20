#!/usr/bin/env python3
"""Run each Selka tool and the Python script it ports on the same inputs, and fail on any difference.

The Selka tools under tools/selka replace Python scripts one at a time (step 4 of the incremental engine plan, the outer
layer). Until a Python original is retired the two must not drift, so this driver builds every Selka tool with the given
compiler, runs it and its original on the same command lines and the same input files in a scratch directory, and compares
standard output, standard error and the exit status byte for byte.

    python3 tests/test_selka_tools.py --compiler zig-out/bin/selka [--tool NAME] [--real] [--list]

`--real` adds the real logs of this machine (the engine shadow logs under ~/.cache/selka/engine-shadow and the copies in
the evidence archive) to the synthetic inputs; they are copied into the scratch directory first. Without it the driver reads
only repository files, so a cached verdict stays valid (the step declares `selka_tools` in build_test_inputs.zig).

Where a Selka tool is knowingly not the original (it takes `--examples=3`, which the original refuses) the difference is
listed in the tool's own header and the driver does not probe it.
"""
import argparse
import dataclasses
import glob
import importlib.util
import os
import random
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Callable

ROOT = Path(__file__).resolve().parents[1]
TIMEOUT = 300


@dataclasses.dataclass
class Case:
    """One command line, run in `cwd` (a directory under the tool's scratch directory) with the files it needs."""
    name: str
    argv: list[str]
    cwd: str = ""


@dataclasses.dataclass
class Tool:
    """A Selka tool, the Python script it ports, and how to produce inputs and command lines for both."""
    name: str
    python: str
    selka: str
    make_inputs: Callable[[Path, bool], list[str]]
    cases: Callable[[list[str]], list[Case]]


def load_module(path: Path):
    spec = importlib.util.spec_from_file_location(path.stem, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


# ---- shadow_summary ----------------------------------------------------------------------------------------------

def shadow_inputs(scratch: Path, real: bool) -> list[str]:
    """Write the input logs the shadow summary runs on; return their file names."""
    fixtures = load_module(ROOT / "tools" / "selka" / "gen_shadow_summary_fixtures.py")
    lines = fixtures.raw_lines(fixtures.LOG)
    files: dict[str, str] = {
        "fixture.jsonl": "\n".join(lines) + "\n",
        "no_final_newline.jsonl": "\n".join(lines),
        "crlf.jsonl": "\r\n".join(lines) + "\r\n",
        "empty.jsonl": "",
        "blank.jsonl": "\n\n   \n\t\n",
        "bad_only.jsonl": "{nope\n[1, 2\n\"text\n",
        "summary_only.jsonl": "\n".join(l for l in lines if '"summary"' in l) + "\n",
        "unicode.jsonl": '{"v":1,"class":"efficiency","test":"é::日本語","entry":"é.selka","old":{"reason":"réponse"},"engine":{"reason":"plan: file /tmp/é changed"}}\n',
    }
    # A larger log built from the fixture lines in a seeded order: many buckets, ties, repeated reasons.
    rng = random.Random(20261030)
    classes = ["soundness", "efficiency", "plan", "verify"]
    big = []
    for index in range(1500):
        name = classes[rng.randrange(len(classes))]
        old = rng.choice(["whole-receipt-hit", "no-success-receipt", "stale", "", "whole-report-hit"])
        engine = rng.choice(["record is valid", "plan: file /x/%d.selka changed" % rng.randrange(40), "tool /usr/bin/zig changed",
                             "KEY environment changed", "plan: no record", "listing /t changed"])
        entry = {"v": 1, "class": name, "test": "m%d::t%d" % (rng.randrange(30), index), "entry": "m.selka", "old": {"decision": "x", "reason": old},
                 "engine": {"decision": "y", "reason": engine}}
        if name == "soundness":
            entry["verdict_differs"] = rng.random() < 0.01
        if rng.random() < 0.1:
            entry["tests"] = rng.randrange(0, 9)
        big.append(fixtures.compact(entry))
    for index in range(40):
        big.append(fixtures.compact({"v": 1, "class": "summary", "pid": index, "observed": rng.randrange(1000), "unobserved": rng.randrange(5), "old_reuse": rng.randrange(900),
                                     "engine_reuse": rng.randrange(900), "agree": rng.randrange(900), "soundness": rng.randrange(20), "verdict_differs": 0,
                                     "efficiency": rng.randrange(20), "plan": 0, "verify": 0, "dropped": 0, "spent_us": rng.randrange(10**7)}))
    files["big.jsonl"] = "\n".join(big) + "\n"
    for name, text in files.items():
        (scratch / name).write_text(text, encoding="utf-8", newline="")
    names = sorted(files)
    if real:
        sources = glob.glob(os.path.expanduser("~/.cache/selka/engine-shadow/*.jsonl"))
        sources += glob.glob(os.path.expanduser("~/ai/canopy/mylang-evidence-archive/**/shadow*.jsonl"), recursive=True)
        for index, source in enumerate(sorted(set(sources))):
            if os.path.getsize(source) > 64 * 1024 * 1024 or os.path.basename(source).startswith("real-"):
                continue
            name = "real_%d.jsonl" % index
            shutil.copyfile(source, scratch / name)
            names.append(name)
    return names


def shadow_cases(files: list[str]) -> list[Case]:
    cases = [Case("self-test", ["--self-test"]), Case("no arguments", []), Case("help", ["--help"]), Case("unknown flag", ["fixture.jsonl", "--nope"]),
             Case("bad examples", ["fixture.jsonl", "--examples", "x"]), Case("negative examples", ["fixture.jsonl", "--examples", "-1"]),
             Case("examples without a value", ["fixture.jsonl", "--examples"]), Case("two logs", ["fixture.jsonl", "empty.jsonl"]),
             Case("json without a log", ["--json"]), Case("missing log", ["absent.jsonl"]), Case("log is a directory", ["."]),
             Case("self-test with more words", ["--self-test", "fixture.jsonl"])]
    for name in files:
        cases.append(Case(name, [name]))
        cases.append(Case(name + " --json", [name, "--json"]))
        cases.append(Case(name + " --examples 0", [name, "--examples", "0"]))
        cases.append(Case(name + " --examples 1 --json", [name, "--examples", "1", "--json"]))
        cases.append(Case(name + " options first", ["--json", "--examples", "12", name]))
    return cases


# ---- gate_summary ------------------------------------------------------------------------------------------------

def gate_inputs(scratch: Path, real: bool) -> list[str]:
    """Write the gate logs the gate summary runs on and the trees its command-line cases need; return the names."""
    fixtures = load_module(ROOT / "tools" / "selka" / "gen_gate_summary_fixtures.py")
    names: list[str] = []
    for index, (_, text, _) in enumerate(fixtures.CASES):
        name = "log_%03d.log" % index
        (scratch / name).write_text(text, encoding="utf-8", newline="")
        names.append(name)
    for index, (_, tree) in enumerate(fixtures.cli_cases()):
        for path, text in tree.items():
            target = scratch / ("cli_%02d" % index) / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(text, encoding="utf-8", newline="")
        (scratch / ("cli_%02d" % index)).mkdir(exist_ok=True)
    if real:
        archive = os.path.expanduser("~/ai/canopy/mylang-evidence-archive")
        sources = sorted(set(glob.glob(archive + "/**/*gate*.log", recursive=True)))
        for index, source in enumerate(sources):
            if os.path.getsize(source) > 64 * 1024 * 1024:
                continue
            name = "real_%03d.log" % index
            shutil.copyfile(source, scratch / name)
            names.append(name)
        directories = sorted(set(glob.glob(archive + "/**/last-logs", recursive=True)))
        for index, source in enumerate(directories):
            name = "real_dir_%02d" % index
            shutil.copytree(source, scratch / name)
            names.append(name + "/")
    return names


def gate_cases(files: list[str]) -> list[Case]:
    fixtures = load_module(ROOT / "tools" / "selka" / "gen_gate_summary_fixtures.py")
    cases = []
    for index, (argv, _) in enumerate(fixtures.cli_cases()):
        cases.append(Case("cli case %d %s" % (index, argv), argv, "cli_%02d" % index))
    for name in files:
        target = name.rstrip("/")
        cases.append(Case(name, [target]))
        cases.append(Case(name + " --max-lines 7", ["--max-lines", "7", target]))
        cases.append(Case(name + " --max-lines=1", [target, "--max-lines=1"]))
    return cases


TOOLS = [Tool("shadow_summary", "scripts/engine_shadow_summary.py", "tools/selka/shadow_summary.selka", shadow_inputs, shadow_cases),
         Tool("gate_summary", "scripts/gate_summary.py", "tools/selka/gate_summary.selka", gate_inputs, gate_cases)]


# ---- the driver --------------------------------------------------------------------------------------------------

def build(compiler: str, source: str, output: Path, cache: Path) -> None:
    command = [compiler, "build", str(ROOT / source), "-o", str(output), "--cache-dir", str(cache)]
    result = subprocess.run(command, capture_output=True, text=True, timeout=TIMEOUT * 4)
    if result.returncode != 0:
        raise SystemExit("could not build %s:\n%s%s" % (source, result.stdout, result.stderr))


def run(command: list[str], cwd: Path) -> tuple[bytes, bytes, int]:
    result = subprocess.run(command, cwd=cwd, capture_output=True, timeout=TIMEOUT)
    return result.stdout, result.stderr, result.returncode


def show(blob: bytes) -> str:
    text = blob.decode("utf-8", "replace")
    return text if len(text) < 400 else text[:400] + "... (%d bytes)" % len(blob)


def compare(tool: Tool, binary: Path, scratch: Path, cases: list[Case]) -> list[str]:
    failures = []
    for case in cases:
        where = scratch / case.cwd
        python = run([sys.executable, str(ROOT / tool.python)] + case.argv, where)
        selka = run([str(binary)] + case.argv, where)
        for label, left, right in (("stdout", python[0], selka[0]), ("stderr", python[1], selka[1]), ("exit status", python[2], selka[2])):
            if left != right:
                shown_left = show(left) if isinstance(left, bytes) else left
                shown_right = show(right) if isinstance(right, bytes) else right
                failures.append("%s: %s [%s] differs\n  python: %r\n  selka:  %r" % (tool.name, case.name, label, shown_left, shown_right))
    return failures


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--compiler", default=str(ROOT / "zig-out" / "bin" / "selka"), help="the compiler that builds the Selka tools")
    parser.add_argument("--tool", action="append", help="only this tool (repeatable)")
    parser.add_argument("--real", action="store_true", help="also run on the real shadow logs of this machine")
    parser.add_argument("--list", action="store_true", help="list the tools and exit")
    parser.add_argument("--keep", action="store_true", help="keep the scratch directory")
    options = parser.parse_args()
    if options.list:
        for tool in TOOLS:
            print("%s: %s <-> %s" % (tool.name, tool.selka, tool.python))
        return 0
    chosen = [tool for tool in TOOLS if not options.tool or tool.name in options.tool]
    if not chosen:
        print("no such tool: %s" % options.tool, file=sys.stderr)
        return 2
    scratch = Path(tempfile.mkdtemp(prefix="selka-tools-"))
    failures: list[str] = []
    try:
        cache = scratch / "cache"
        for tool in chosen:
            work = scratch / tool.name
            work.mkdir()
            binary = scratch / tool.name
            binary = scratch / ("bin-" + tool.name)
            build(options.compiler, tool.selka, binary, cache)
            files = tool.make_inputs(work, options.real)
            cases = tool.cases(files)
            found = compare(tool, binary, work, cases)
            failures.extend(found)
            print("%s: %d command lines on %d inputs, %d differences" % (tool.name, len(cases), len(files), len(found)))
    finally:
        if options.keep:
            print("scratch kept at %s" % scratch)
        else:
            shutil.rmtree(scratch, ignore_errors=True)
    for failure in failures[:20]:
        print("FAIL " + failure, file=sys.stderr)
    if len(failures) > 20:
        print("... and %d more" % (len(failures) - 20), file=sys.stderr)
    if failures:
        return 1
    print("selka tools: every output matches its Python original")
    return 0


if __name__ == "__main__":
    sys.exit(main())
