#!/usr/bin/env python3
"""Materialise the seeded-fault corpus for the diagnostic-feedback experiment.

Every fault is a small, self-contained mylang project that fails exactly one way,
with a pinned expected stdout for the fixed program. Each family has a `dev`
variant — used only to author the fix wording for the third treatment — and a
`test` variant with different names, values and shapes, so a fix rule that helps
on `test` had to transfer rather than memorise.

    python3 experiments/diagnostic-feedback/faults/generate.py
    python3 experiments/diagnostic-feedback/faults/generate.py --check   # run the checker, assert the seeded code
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import shutil
import subprocess
import sys

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
COMPILER = REPO / "experiments" / "cascade" / "tools" / "bin" / "mylang"

# Each fault: id, family, the checker code it must produce, the project files,
# the request handed to the agent, and the stdout a correct fix must print.
FAULTS = [
    {
        "id": "bool-int", "code": "E_TYPE", "dev": True,
        "request": "The program must print `1` when the argument is positive and `0` otherwise. "
                   "It currently does not pass the checker; make it compile and print `1` for the call in main.",
        "expect": "1",
        "files": {"main.my": """module main


def positive(n: int) -> int:
    return n > 0


def main(out: Stream) -> int:
    out.print(positive(3))
    return 0
"""}},
    {
        "id": "bool-int", "code": "E_TYPE", "dev": False,
        "request": "The program must print `1` when the first argument is larger than the second and `0` otherwise. "
                   "It currently does not pass the checker; make it compile and print `1` for the call in main.",
        "expect": "1",
        "files": {"main.my": """module main


def above(a: int, b: int) -> int:
    return a > b


def main(out: Stream) -> int:
    out.print(above(5, 2))
    return 0
"""}},
    {
        "id": "module-name", "code": "E_MODULE_NAME", "dev": True,
        "request": "The project has a helper module used by main. It does not pass the checker; make it compile "
                   "and print `42`.",
        "expect": "42",
        "files": {
            "main.my": """module main

import helper as helper


def main(out: Stream) -> int:
    out.print(helper.answer())
    return 0
""",
            "helper.my": """module utilities


def answer() -> int:
    return 42
"""},
    },
    {
        "id": "module-name", "code": "E_MODULE_NAME", "dev": False,
        "request": "The project has a helper module used by main. It does not pass the checker; make it compile "
                   "and print `7`.",
        "expect": "7",
        "files": {
            "main.my": """module main

import stats as stats


def main(out: Stream) -> int:
    out.print(stats.total())
    return 0
""",
            "stats.my": """module statistics


def total() -> int:
    return 7
"""},
    },
    {
        "id": "output-capability", "code": "E_OUTPUT_CAPABILITY", "dev": True,
        "request": "The program must print `hi`. It does not pass the checker; make it compile and print `hi`.",
        "expect": "hi",
        "files": {"main.my": """module main


def shout(text: str) -> int:
    print(text)
    return 0


def main(out: Stream) -> int:
    return shout("hi")
"""}},
    {
        "id": "output-capability", "code": "E_OUTPUT_CAPABILITY", "dev": False,
        "request": "The program must print `== ok`. It does not pass the checker; make it compile and print "
                   "`== ok`.",
        "expect": "== ok",
        "files": {"main.my": """module main


def banner(text: str) -> int:
    print("==", text)
    return 0


def main(out: Stream) -> int:
    return banner("ok")
"""}},
    {
        "id": "variant-coverage", "code": "E_INCOMPLETE_MATCH", "dev": True,
        "request": "The program must print the integer area of the square passed in main. It does not pass the "
                   "checker; make it compile and print `4`.",
        "expect": "4",
        "files": {"main.my": """module main


union Shape:
    circle(radius: float),
    square(side: float)


def area(shape: Shape) -> float:
    match shape:
        case Shape.circle(radius):
            return 3.0 * radius * radius


def main(out: Stream) -> int:
    out.print(int(area(Shape.square(2.0))))
    return 0
"""}},
    {
        "id": "variant-coverage", "code": "E_INCOMPLETE_MATCH", "dev": False,
        "request": "The program must print `stopped`. It does not pass the checker; make it compile and print "
                   "`stopped`.",
        "expect": "stopped",
        "files": {"main.my": """module main


union Event:
    start(name: str),
    stop(name: str)


def describe(event: Event) -> str:
    match event:
        case Event.start(name):
            return "started"


def main(out: Stream) -> int:
    out.print(describe(Event.stop("job")))
    return 0
"""}},
    {
        "id": "unknown-name", "code": "E_UNKNOWN_NAME", "dev": True,
        "request": "The program must print the sum of the list, `6`. It does not pass the checker; make it "
                   "compile and print `6`.",
        "expect": "6",
        "files": {"main.my": """module main


def total(values: list[int]) -> int:
    index = 0
    while index < len(values):
        running = running + values[index]
        index = index + 1
    return running


def main(out: Stream) -> int:
    out.print(total([1, 2, 3]))
    return 0
"""}},
    {
        "id": "unknown-name", "code": "E_UNKNOWN_NAME", "dev": False,
        "request": "The program must print `15`: the sum of the running total and the argument. It does not pass "
                   "the checker; make it compile and print `15`.",
        "expect": "15",
        "files": {"main.my": """module main


def pick(bonus: int) -> int:
    total = 10
    return total + reward


def main(out: Stream) -> int:
    out.print(pick(5))
    return 0
"""}},
    {
        "id": "module-path", "code": "E_MODULE_READ", "dev": True,
        "request": "The project has a helper module used by main. It does not pass the checker; make it compile "
                   "and print `42`.",
        "expect": "42",
        "files": {
            "main.my": """module main

import utils.helper as helper


def main(out: Stream) -> int:
    out.print(helper.answer())
    return 0
""",
            "helper.my": """module helper


def answer() -> int:
    return 42
"""},
    },
    {
        "id": "module-path", "code": "E_MODULE_READ", "dev": False,
        "request": "The project has a helper module used by main. It does not pass the checker; make it compile "
                   "and print `7`.",
        "expect": "7",
        "files": {
            "main.my": """module main

import lib.stats as stats


def main(out: Stream) -> int:
    out.print(stats.total())
    return 0
""",
            "stats.my": """module stats


def total() -> int:
    return 7
"""},
    },
    {
        "id": "generic-requirement", "code": "E_GENERIC_REQUIREMENT", "dev": True,
        "request": "The program must print the largest value, `3`. It does not pass the checker; make it compile "
                   "and print `3`.",
        "expect": "3",
        "files": {"main.my": """module main


def largest[T: Ordered](items: list[int]) -> int:
    best = items[0]
    for item in items:
        if item > best:
            best = item
    return best


def main(out: Stream) -> int:
    out.print(largest([1, 3, 2]))
    return 0
"""}},
    {
        "id": "generic-requirement", "code": "E_GENERIC_REQUIREMENT", "dev": False,
        "request": "The program must print `9`. It does not pass the checker; make it compile and print `9`.",
        "expect": "9",
        "files": {"main.my": """module main


def pick[T: Sortable](values: list[int], index: int) -> int:
    return values[index]


def main(out: Stream) -> int:
    out.print(pick([4, 9, 1], 1))
    return 0
"""}},
    {
        "id": "checked-result", "code": "E_TYPE", "dev": True,
        "request": "The program must print `41`, the count that `parse_count(\"40\")` returns plus the seed. It does "
                   "not pass the checker; make it compile and print `41`.",
        "expect": "41",
        "files": {"main.my": """module main


def parse_count(raw: str) -> Result[int, str]:
    match int(raw):
        case Some(value):
            return Ok(value)
        case None:
            return Err("not a number")


def main(out: Stream) -> int:
    seed = 1
    total = seed + parse_count("40")
    out.print(total)
    return 0
"""}},
    {
        "id": "checked-result", "code": "E_TYPE", "dev": False,
        "request": "The program must print `5`, the score that `lookup(\"five\")` returns plus the bonus. It does not "
                   "pass the checker; make it compile and print `5`.",
        "expect": "5",
        "files": {"main.my": """module main


def lookup(key: str) -> Result[int, str]:
    if key == "five":
        return Ok(5)
    return Err("missing")


def main(out: Stream) -> int:
    bonus = 0
    score = bonus + lookup("five")
    out.print(score)
    return 0
"""}},
]


def materialise() -> list[dict]:
    written = []
    for fault in FAULTS:
        split = "dev" if fault["dev"] else "test"
        directory = HERE / split / fault["id"]
        if directory.exists():
            shutil.rmtree(directory)
        (directory / "project").mkdir(parents=True)
        (directory / "hidden").mkdir()
        for name, content in fault["files"].items():
            (directory / "project" / name).write_text(content)
        (directory / "request.md").write_text(
            "# Fix the program\n\n"
            f"{fault['request']}\n\n"
            "The working copy holds `project/` and `bin/mylang`. Work in `project/`; you may create, edit and run "
            "files there. When you are done, `bin/mylang run project/main.my` must exit 0 and print exactly the "
            "required output.\n"
        )
        manifest = {
            "version": 1,
            "steps": [{
                "id": "fixed",
                "kind": "test",
                "commands": [["../../bin/mylang", "run", "../../project/main.my"]],
                "expect_stdout": fault["expect"] + "\n",
                "timeout": 120,
            }],
        }
        (directory / "hidden" / "verify.json").write_text(json.dumps(manifest, indent=2) + "\n")
        (directory / "hidden" / "fault.json").write_text(json.dumps(
            {"id": fault["id"], "family": fault["code"], "split": split, "expect": fault["expect"]}, indent=2) + "\n")
        written.append({"split": split, "id": fault["id"], "code": fault["code"], "directory": directory})
    return written


def check(faults: list[dict]) -> int:
    failures = 0
    for fault in faults:
        entry = fault["directory"] / "project" / "main.my"
        result = subprocess.run([str(COMPILER), "check", str(entry)], capture_output=True, text=True, cwd=fault["directory"])
        codes = [line.split("error[")[1].split("]")[0] for line in result.stderr.splitlines() if "error[" in line]
        ok = fault["code"] in codes
        print(f"  {'ok  ' if ok else 'FAIL'} {fault['split']}/{fault['id']:<22} expected {fault['code']:<22} got {codes}")
        failures += 0 if ok else 1
    return failures


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--check", action="store_true", help="run the checker and assert each seeded code")
    args = parser.parse_args()
    faults = materialise()
    print(f"wrote {len(faults)} faults ({sum(1 for f in faults if f['split'] == 'dev')} dev, "
          f"{sum(1 for f in faults if f['split'] == 'test')} test)")
    return check(faults) if args.check else 0


if __name__ == "__main__":
    sys.exit(main())
