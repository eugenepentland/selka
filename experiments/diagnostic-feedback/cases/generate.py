#!/usr/bin/env python3
"""Generate the behavioral cases: faulty, reference, public examples, hidden cases.

Each case is a small program whose behavior is required on *several* inputs, so a
shortcut (returning the advertised constant, ignoring the error path, dropping a
required branch) fails the oracle. Expectations are computed in Python here, not
hand-written, and every case ships a reference repair plus deliberately wrong
repairs that the oracle must reject.

    python3 experiments/diagnostic-feedback/cases/generate.py --preflight
"""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
COMPILER = REPO / "experiments" / "cascade" / "tools" / "bin" / "mylang"
CACHE = HERE.parent / ".tmp" / "case-cache"


def parse_checked(raw: str, seed: int, fallback: int) -> int:
    try:
        return seed + int(raw)
    except ValueError:
        return fallback


def case_checked_result(vid: str, split: str, fn: str, seed: int, fallback: int, shape: str,
                        hard: bool = False) -> dict:
    header = f'''module main


def {fn}(raw: str) -> Result[int, str]:
    match int(raw):
        case Some(value):
            return Ok(value)
        case None:
            return Err("not a number")
'''
    faulty_main = {
        "expr": f"    out.print({seed} + {fn}(args[0]))",
        "temp": f"    value = {fn}(args[0])\n    out.print({seed} + value)",
        "double": f"    base = {fn}(args[0])\n    out.print(base + base + {seed})",
    }[shape]
    reference_main = {
        "expr": f"""    match {fn}(args[0]):
        case Ok(value):
            out.print({seed} + value)
        case Err(_):
            out.print({fallback})""",
        "temp": f"""    value = {fn}(args[0])
    match value:
        case Ok(found):
            out.print({seed} + found)
        case Err(_):
            out.print({fallback})""",
        "double": f"""    base = {fn}(args[0])
    match base:
        case Ok(found):
            out.print(found + found + {seed})
        case Err(_):
            out.print({fallback})""",
    }[shape]

    def faulty() -> str:
        return header + f"\n\ndef main(args: list[str], out: Stream) -> int:\n{faulty_main}\n    return 0\n"

    def reference() -> str:
        return header + f"\n\ndef main(args: list[str], out: Stream) -> int:\n{reference_main}\n    return 0\n"

    def oracle(args: list[str]) -> str:
        count = parse_checked(args[0], seed, fallback)
        if count == fallback and not args[0].lstrip("-").isdigit():
            return f"{fallback}\n"
        return f"{count + count + 0 if shape == 'double' else count}\n" if shape == "double" else f"{count}\n"

    def expected(args: list[str]) -> str:
        try:
            value = int(args[0])
        except ValueError:
            return f"{fallback}\n"
        if shape == "double":
            return f"{seed} + {value} + {value}\n" if False else f"{value + value + seed}\n"
        return f"{seed + value}\n"

    wrong = {
        "constant": header + f"\n\ndef main(args: list[str], out: Stream) -> int:\n    out.print({seed + 41})\n    return 0\n",
        "err-as-zero": header + f"""\n\ndef main(args: list[str], out: Stream) -> int:
    match {fn}(args[0] if args[0].lstrip("-").isdigit() else "0"):
        case Ok(value):
            out.print({seed} + value)
        case Err(_):
            out.print({seed + 1})
    return 0
""",
    }
    inputs = [["41"], ["0"], ["-5"], ["abc"]] if shape != "double" else [["41"], ["0"], ["7"], ["xyz"]]
    request = (f"`{fn}` reads one numeric argument and returns it as a `Result`. The program must print {seed} plus that "
               f"number; if the argument is not an integer it must print {fallback}.")
    return {"id": vid, "split": split, "family": "checked-result", "code": "E_TYPE",
            "faulty": faulty(), "reference": reference(), "wrong": wrong,
            "public": inputs[:2], "hidden": inputs, "expected": expected, "request": request,
            "structural": ""}


def case_generic(vid: str, split: str, fn: str, req: str, count: int, hard: bool = False) -> dict:
    faulty = f'''module main


def number(text: str) -> int:
    match int(text):
        case Some(value):
            return value
        case None:
            return 0


def {fn}[T: {req}](values: list[int]) -> int:
    best = values[0]
    index = 1
    while index < len(values):
        if values[index] > best:
            best = values[index]
        index = index + 1
    return best


{{second_signature}}
def main(args: list[str], out: Stream) -> int:
    first = number(args[0])
    second = number(args[1])
    third = number(args[2])
    out.print({{caller}}([first, second, third]))
    return 0
'''
    reference = faulty.replace(f"[T: {req}]", "")
    wrong = {
        "first-only": faulty.replace(f"[T: {req}]", "").replace(
            """    best = values[0]
    index = 1
    while index < len(values):
        if values[index] > best:
            best = values[index]
        index = index + 1
    return best""", "    return values[0]"),
        "negatives": faulty.replace(f"[T: {req}]", "").replace("    best = values[0]", "    best = 0"),
    }
    inputs = [["1", "3", "2"], ["5", "5", "5"], ["-4", "-9", "-1"], ["7", "2", "9"]][:count]
    if hard:
        second_signature = f"""def {fn}_of[T: {req}](values: list[int]) -> int:
    return {fn}(values)"""
        caller = f"{fn}_of"
    else:
        second_signature = ""
        caller = fn
    faulty = faulty.format(second_signature=second_signature, caller=caller) if "{second_signature}" in faulty else faulty
    faulty = faulty.replace("{second_signature}", second_signature).replace("{caller}", caller)
    reference = faulty.replace(f"[T: {req}]", "")
    wrong = {
        "first-only": reference.replace(
            """    best = values[0]
    index = 1
    while index < len(values):
        if values[index] > best:
            best = values[index]
        index = index + 1
    return best""", "    return values[0]"),
        "negatives": reference.replace("    best = values[0]", "    best = 0"),
    }
    request = (f"`{fn}` returns the largest of three integers given as arguments. It does not pass the checker; make it "
               f"compile and print the largest value.")
    return {"id": vid, "split": split, "family": "generic-requirement", "code": "E_GENERIC_REQUIREMENT",
            "faulty": faulty, "reference": reference, "wrong": wrong,
            "public": inputs[:2], "hidden": inputs,
            "expected": lambda args: f"{max(int(value) for value in args)}\n", "request": request,
            "structural": ""}


def case_bool_int(vid: str, split: str, fn: str, style: str) -> dict:
    body_faulty = "    return a > b" if style == "return" else "    bigger = a > b\n    return bigger"
    body_reference = ("    if a > b:\n        return 1\n    return 0" if style == "return"
                      else "    bigger = a > b\n    if bigger:\n        return 1\n    return 0")
    faulty = f'''module main


def number(text: str) -> int:
    match int(text):
        case Some(value):
            return value
        case None:
            return 0


def {fn}(a: int, b: int) -> int:
{body_faulty}


def main(args: list[str], out: Stream) -> int:
    out.print({fn}(number(args[0]), number(args[1])))
    return 0
'''
    reference = f'''module main


def number(text: str) -> int:
    match int(text):
        case Some(value):
            return value
        case None:
            return 0


def {fn}(a: int, b: int) -> int:
{body_reference}


def main(args: list[str], out: Stream) -> int:
    out.print({fn}(number(args[0]), number(args[1])))
    return 0
'''
    wrong = {
        "always-one": faulty.replace(body_faulty, "    return 1"),
        "always-zero": faulty.replace(body_faulty, "    return 0"),
    }
    inputs = [["5", "2"], ["2", "5"], ["3", "3"], ["-1", "-4"]]
    return {"id": vid, "split": split, "family": "bool-int", "code": "E_TYPE",
            "faulty": faulty, "reference": reference, "wrong": wrong,
            "public": inputs[:2], "hidden": inputs,
            "expected": lambda args: f"{1 if int(args[0]) > int(args[1]) else 0}\n",
            "request": f"`{fn}` must print 1 when the first argument is larger than the second, and 0 otherwise.",
            "structural": ""}


def case_variant(vid: str, split: str, shape: str) -> dict:
    faulty = f'''module main


def number(text: str) -> int:
    match int(text):
        case Some(value):
            return value
        case None:
            return 0


union Shape:
    circle(radius: int),
    square(side: int)


def area(shape: Shape) -> int:
    match shape:
        case Shape.circle(radius):
            return 3 * radius * radius


def main(args: list[str], out: Stream) -> int:
    size = number(args[1])
    if args[0] == "circle":
        out.print(area(Shape.circle(size)))
    else:
        out.print(area(Shape.square(size)))
    return 0
'''
    reference = faulty.replace('''        case Shape.circle(radius):
            return 3 * radius * radius''', '''        case Shape.circle(radius):
            return 3 * radius * radius
        case Shape.square(side):
            return side * side''')
    wrong = {
        "square-zero": faulty.replace('''        case Shape.circle(radius):
            return 3 * radius * radius''', '''        case Shape.circle(radius):
            return 3 * radius * radius
        case Shape.square(side):
            return 0'''),
        "circle-square": faulty.replace('''        case Shape.circle(radius):
            return 3 * radius * radius''', '''        case Shape.circle(radius):
            return radius * radius
        case Shape.square(side):
            return side * side'''),
    }
    inputs = [["circle", "2"], ["square", "3"], ["square", "5"], ["circle", "1"]]
    def expected(args: list[str]) -> str:
        size = int(args[1])
        return f"{3 * size * size if args[0] == 'circle' else size * size}\n"
    return {"id": vid, "split": split, "family": "variant-coverage", "code": "E_INCOMPLETE_MATCH",
            "faulty": faulty, "reference": reference, "wrong": wrong,
            "public": inputs[:2], "hidden": inputs, "expected": expected,
            "request": "`area` must return 3*r*r for a circle and r*r for a square. It does not pass the checker; "
                       "make it compile and handle both shapes.", "structural": ""}


FAMILIES = {
    "checked-result": case_checked_result,
    "generic-requirement": case_generic,
    "bool-int": case_bool_int,
    "variant-coverage": case_variant,
}

VARIANTS = [
    ("dev", "dev-checked", "checked-result", dict(vid="dev-checked", split="dev", fn="parse_count", seed=1, fallback=-1, shape="expr")),
    ("dev", "dev-generic", "generic-requirement", dict(vid="dev-generic", split="dev", fn="largest", req="Ordered", count=4)),
    ("dev", "dev-bool", "bool-int", dict(vid="dev-bool", split="dev", fn="above", style="return")),
    ("dev", "dev-variant", "variant-coverage", dict(vid="dev-variant", split="dev", shape="basic")),
    ("test", "checked-a", "checked-result", dict(hard=True, vid="checked-a", split="test", fn="parse_count", seed=1, fallback=-1, shape="expr")),
    ("test", "checked-b", "checked-result", dict(hard=True, vid="checked-b", split="test", fn="read_number", seed=0, fallback=-99, shape="temp")),
    ("test", "checked-c", "checked-result", dict(hard=True, vid="checked-c", split="test", fn="decode", seed=10, fallback=0, shape="double")),
    ("test", "checked-d", "checked-result", dict(hard=True, vid="checked-d", split="test", fn="as_count", seed=7, fallback=7, shape="expr")),
    ("test", "checked-e", "checked-result", dict(hard=True, vid="checked-e", split="test", fn="to_int", seed=-3, fallback=-1, shape="temp")),
    ("test", "generic-a", "generic-requirement", dict(hard=True, vid="generic-a", split="test", fn="largest", req="Ordered", count=4)),
    ("test", "generic-b", "generic-requirement", dict(hard=True, vid="generic-b", split="test", fn="biggest", req="Sortable", count=4)),
    ("test", "generic-c", "generic-requirement", dict(hard=True, vid="generic-c", split="test", fn="highest", req="Comparable", count=3)),
    ("test", "generic-d", "generic-requirement", dict(hard=True, vid="generic-d", split="test", fn="maximum", req="Numeric", count=4)),
    ("test", "generic-e", "generic-requirement", dict(hard=True, vid="generic-e", split="test", fn="top", req="Ordered", count=3)),
    ("test", "bool-a", "bool-int", dict(vid="bool-a", split="test", fn="above", style="return")),
    ("test", "bool-b", "bool-int", dict(vid="bool-b", split="test", fn="exceeds", style="temp")),
    ("test", "variant-a", "variant-coverage", dict(vid="variant-a", split="test", shape="basic")),
    ("test", "variant-b", "variant-coverage", dict(vid="variant-b", split="test", shape="basic")),
]


def materialise() -> list[dict]:
    written = []
    for split, cid, family, kwargs in VARIANTS:
        case = FAMILIES[family](**kwargs)
        directory = HERE / split / cid
        if directory.exists():
            shutil.rmtree(directory)
        (directory / "project").mkdir(parents=True)
        (directory / "reference").mkdir()
        (directory / "public").mkdir()
        (directory / "hidden").mkdir()
        (directory / "project" / "main.my").write_text(case["faulty"])
        (directory / "reference" / "main.my").write_text(case["reference"])
        for name, source in case["wrong"].items():
            (directory / "wrong" / name).mkdir(parents=True, exist_ok=True)
            (directory / "wrong" / name / "main.my").write_text(source)
        public = [{"args": args, "stdout": case["expected"](args)} for args in case["public"]]
        (directory / "public" / "expected.json").write_text(json.dumps({"cases": public}, indent=2) + "\n")
        steps = [{"id": f"in-{index}", "kind": "test", "args": args,
                  "expect_stdout": case["expected"](args), "timeout": 120}
                 for index, args in enumerate(case["hidden"])]
        (directory / "hidden" / "verify.json").write_text(json.dumps({"version": 1, "steps": steps}, indent=2) + "\n")
        (directory / "request.md").write_text(f"# Fix the program\n\n{case['request']}\n")
        codes = observed_codes(directory / "project" / "main.my")
        (directory / "case.json").write_text(json.dumps(
            {"id": case["id"], "split": split, "family": case["family"],
             "code": codes[0] if codes else case["code"], "observed_codes": codes,
             "version": 1, "public_inputs": len(case["public"]), "hidden_inputs": len(case["hidden"]),
             "structural": case["structural"]}, indent=2) + "\n")
        written.append({"split": split, "id": cid, "family": family, "directory": directory})
    return written


def compiler_env() -> dict:
    return {**os.environ, "ZIG_GLOBAL_CACHE_DIR": str(CACHE), "ZIG_LOCAL_CACHE_DIR": str(CACHE / "local")}


def run_program(entry: Path, args: list[str], cwd: Path) -> subprocess.CompletedProcess:
    return subprocess.run([str(COMPILER), "run", str(entry), "--", *args],
                          capture_output=True, text=True, cwd=cwd, env=compiler_env())


def observed_codes(entry: Path) -> list[str]:
    """The codes the checker reports for a source file, in order."""
    completed = subprocess.run([str(COMPILER), "check", str(entry)],
                               capture_output=True, text=True, cwd=entry.parent, env=compiler_env())
    return [line.split("error[")[1].split("]")[0] for line in completed.stderr.splitlines() if "error[" in line]


def preflight(cases: list[dict]) -> int:
    failures = 0
    for case in cases:
        directory = case["directory"]
        steps = json.loads((directory / "hidden" / "verify.json").read_text())["steps"]
        case_meta = json.loads((directory / "case.json").read_text())
        codes = observed_codes(directory / "project" / "main.my")
        problems = []
        if case_meta["code"] not in codes:
            problems.append(f"faulty gives {codes}, expected {case_meta['code']}")
        elif any(code != case_meta["code"] for code in codes):
            problems.append(f"faulty has extra diagnostics {codes}")
        reference_ok = all(run_program(directory / "reference" / "main.my", step["args"], directory).stdout == step["expect_stdout"]
                           for step in steps)
        if not reference_ok:
            problems.append("reference fails a hidden input")
        for name in sorted(path.name for path in (directory / "wrong").iterdir()):
            rejected = False
            for step in steps:
                completed = run_program(directory / "wrong" / name / "main.my", step["args"], directory)
                if completed.returncode != 0 or completed.stdout != step["expect_stdout"]:
                    rejected = True
                    break
            if not rejected:
                problems.append(f"wrong repair {name} passes every hidden input")
        print(f"  {'ok  ' if not problems else 'FAIL'} {case['split']}/{case['id']:<12} {case['family']:<20} "
              + ("; ".join(problems) if problems else f"{len(steps)} hidden inputs"))
        failures += 1 if problems else 0
    return failures


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--preflight", action="store_true")
    args = parser.parse_args()
    cases = materialise()
    print(f"wrote {len(cases)} cases ({sum(1 for c in cases if c['split'] == 'dev')} dev, "
          f"{sum(1 for c in cases if c['split'] == 'test')} test)")
    if not args.preflight:
        return 0
    failures = preflight(cases)
    shutil.rmtree(CACHE, ignore_errors=True)
    return failures


if __name__ == "__main__":
    sys.exit(main())
