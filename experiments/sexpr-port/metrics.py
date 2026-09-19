#!/usr/bin/env python3
"""Measure the Zig and mylang S-expression readers for the port comparison.

Counts per file: total / blank / comment / code lines, characters, top-level
declarations and test bodies; then aggregates the "core reader" (ast +
tokenizer + parser), the optional printer, and the test suites. Emits JSON to
experiments/sexpr-port/evidence/metrics.json and a markdown table on stdout.

Usage:
  python3 experiments/sexpr-port/metrics.py
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
EDA = REPO.parent / "eda"

ZIG_MODULES = {
    "ast": EDA / "src/sexpr/ast.zig",
    "tokenizer": EDA / "src/sexpr/tokenizer.zig",
    "parser": EDA / "src/sexpr/parser.zig",
    "printer": EDA / "src/sexpr/printer.zig",
}

MY_MODULES = {
    "ast": REPO / "experiments/sexpr-port/sexpr/ast.my",
    "tokenizer": REPO / "experiments/sexpr-port/sexpr/tokenizer.my",
    "parser": REPO / "experiments/sexpr-port/sexpr/parser.my",
    "printer": REPO / "experiments/sexpr-port/sexpr/printer.my",
}

# In-repo mylang S-expression readers that predate this port, for context.
CONTEXT_FILES = {
    "schematic/guest/sexpr.my": REPO / "src/schematic/guest/sexpr.my",
    "readiness/tokenizer.my": REPO
    / "experiments/readiness-probes-2026-09-18/proj/sexpr/tokenizer.my",
    "readiness/parser.my": REPO
    / "experiments/readiness-probes-2026-09-18/proj/sexpr/parser.my",
}

MY_TESTS = {
    "ast": REPO / "experiments/sexpr-port/tests/ast_test.my",
    "tokenizer": REPO / "experiments/sexpr-port/tests/tokenizer_test.my",
    "parser": REPO / "experiments/sexpr-port/tests/parser_test.my",
    "printer": REPO / "experiments/sexpr-port/tests/printer_test.my",
    "roundtrip": REPO / "experiments/sexpr-port/tests/roundtrip_test.my",
    "smoke": REPO / "experiments/sexpr-port/tests/smoke_test.my",
}

ZIG_DECLS = [
    ("fn", re.compile(r"^\s*(?:pub\s+)?(?:inline\s+)?fn\s+\w+")),
    ("type", re.compile(r"^\s*(?:pub\s+)?const\s+\w+\s*=\s*(?:struct|enum|union|error)")),
    ("const", re.compile(r"^\s*(?:pub\s+)?const\s+\w+\s*=")),
]

MY_DECLS = [
    ("fn", re.compile(r"^\s*(?:public\s+)?def\s+\w+")),
    ("type", re.compile(r"^\s*(?:public\s+)?(?:record|union|enum|class)\s+\w+")),
]

ZIG_TEST = re.compile(r'^\s*test\s+"')

# Idioms counted on non-test code lines, to explain where the line difference
# comes from: Zig threads an allocator and frees explicitly; mylang relies on
# GC plus Result/`?`.
ZIG_IDIOMS = {
    "allocator": re.compile(r"allocator"),
    "defer": re.compile(r"\bdefer\b"),
    "errdefer": re.compile(r"\berrdefer\b"),
    "try": re.compile(r"\btry\b"),
    "catch": re.compile(r"\bcatch\b"),
}
MY_IDIOMS = {
    "Result[": re.compile(r"Result\["),
    "match": re.compile(r"^\s*match\b"),
    "case Err": re.compile(r"\bcase Err\b"),
}


def split_zig_test_blocks(lines: list[str]) -> tuple[set[int], int]:
    """Indices belonging to `test "..."` blocks, and the number of tests."""
    in_test: set[int] = set()
    tests = 0
    i = 0
    while i < len(lines):
        if ZIG_TEST.match(lines[i]):
            tests += 1
            depth = 0
            started = False
            while i < len(lines):
                in_test.add(i)
                depth += lines[i].count("{") - lines[i].count("}")
                if "{" in lines[i]:
                    started = True
                if started and depth <= 0:
                    break
                i += 1
        i += 1
    return in_test, tests


def count_zig(path: Path) -> dict:
    text = path.read_text()
    lines = text.splitlines()
    test_lines, tests = split_zig_test_blocks(lines)
    blank = comment = code = 0
    core_code = 0
    idioms = {name: 0 for name in ZIG_IDIOMS}
    for idx, raw in enumerate(lines):
        stripped = raw.strip()
        if not stripped:
            blank += 1
        elif stripped.startswith("//"):
            comment += 1
        else:
            code += 1
            if idx not in test_lines:
                core_code += 1
                for name, pattern in ZIG_IDIOMS.items():
                    if pattern.search(raw):
                        idioms[name] += 1
    decls = {"fn": 0, "type": 0, "const": 0}
    for raw in lines:
        for name, pattern in ZIG_DECLS:
            if pattern.match(raw):
                decls[name] += 1
                break
    return {
        "path": str(path),
        "language": "zig",
        "total": len(lines),
        "blank": blank,
        "comment": comment,
        "code": code,
        "core_code": core_code,
        "test_lines": len(test_lines),
        "tests": tests,
        "chars": len(text),
        "decls": decls,
        "idioms": idioms,
    }


def count_my(path: Path) -> dict:
    text = path.read_text()
    lines = text.splitlines()
    blank = comment = code = 0
    for raw in lines:
        stripped = raw.strip()
        if not stripped:
            blank += 1
        elif stripped.startswith("#"):
            comment += 1
        else:
            code += 1
    decls = {"fn": 0, "type": 0}
    tests = 0
    my_idioms = {name: 0 for name in MY_IDIOMS}
    for raw in lines:
        if re.match(r"^\s*public\s+def\s+test_\w+", raw):
            tests += 1
        for name, pattern in MY_DECLS:
            if pattern.match(raw):
                decls[name] += 1
                break
        for name, pattern in MY_IDIOMS.items():
            if pattern.search(raw):
                my_idioms[name] += 1
    return {
        "path": str(path),
        "language": "mylang",
        "total": len(lines),
        "blank": blank,
        "comment": comment,
        "code": code,
        "core_code": code,
        "test_lines": 0,
        "tests": tests,
        "chars": len(text),
        "decls": decls,
        "idioms": my_idioms,
    }


def sum_files(entries: list[dict]) -> dict:
    total = {
        "total": 0,
        "blank": 0,
        "comment": 0,
        "code": 0,
        "core_code": 0,
        "test_lines": 0,
        "tests": 0,
        "chars": 0,
        "decls": {},
        "idioms": {},
    }
    for entry in entries:
        for key in ("total", "blank", "comment", "code", "core_code", "test_lines", "tests", "chars"):
            total[key] += entry[key]
        for name, value in entry["decls"].items():
            total["decls"][name] = total["decls"].get(name, 0) + value
        for name, value in entry.get("idioms", {}).items():
            total["idioms"][name] = total["idioms"].get(name, 0) + value
    return total


def render_markdown(result: dict) -> str:
    modules = ["ast", "tokenizer", "parser", "printer"]
    lines = ["# Zig vs mylang S-expression reader — measured sizes", ""]
    lines.append("Generated by `experiments/sexpr-port/metrics.py`. Lines are physical source lines.")
    lines.append("")
    lines.append("## Per module")
    lines.append("")
    lines.append("| module | Zig lines | mylang lines | ratio | Zig code | mylang code |")
    lines.append("| --- | ---: | ---: | ---: | ---: | ---: |")
    for name in modules:
        zig = result["zig"].get(name)
        my = result["mylang"].get(name)
        zl = zig["total"] if zig else 0
        yl = my["total"] if my else 0
        zc = zig["code"] if zig else 0
        yc = my["code"] if my else 0
        ratio = f"{yl / zl:.2f}x" if zl else "n/a"
        lines.append(f"| {name} | {zl} | {yl} | {ratio} | {zc} | {yc} |")
    lines.append("")
    lines.append("## Totals")
    lines.append("")
    lines.append("| group | lines | code | comment | blank | tests |")
    lines.append("| --- | ---: | ---: | ---: | ---: | ---: |")
    labels = [
        ("zig_core", "Zig core (ast+tokenizer+parser)"),
        ("my_core", "mylang core (ast+tokenizer+parser)"),
        ("zig_printer", "Zig printer"),
        ("my_printer", "mylang printer"),
        ("my_tests", "mylang guest tests"),
        ("zig_all", "Zig, all four modules"),
        ("my_all", "mylang, all four modules"),
    ]
    for key, label in labels:
        t = result["totals"][key]
        lines.append(
            f"| {label} | {t['total']} | {t['code']} | {t['comment']} | {t['blank']} | {t['tests']} |"
        )
    lines.append("")
    lines.append("## Tests")
    lines.append("")
    lines.append("| suite | test cases | test source lines |")
    lines.append("| --- | ---: | ---: |")
    zig_all = result["totals"]["zig_all"]
    my_tests = result["totals"]["my_tests"]
    lines.append(f"| Zig inline `test` blocks (4 modules) | {zig_all['tests']} | {zig_all['test_lines']} |")
    lines.append(f"| mylang guest tests (`tests/*.my`) | {my_tests['tests']} | {my_tests['total']} |")
    lines.append("")
    lines.append("## Memory and error plumbing (non-test core lines)")
    lines.append("")
    zig_idioms = result["totals"]["zig_core"].get("idioms", {})
    my_idioms = result["totals"]["my_core"].get("idioms", {})
    lines.append("- Zig core: " + ", ".join(f"`{k}` {v}" for k, v in zig_idioms.items()))
    lines.append("- mylang core: " + ", ".join(f"`{k}` {v}" for k, v in my_idioms.items()))
    lines.append("")
    lines.append("## Earlier in-repo mylang readers (context)")
    lines.append("")
    lines.append("| file | lines | code |")
    lines.append("| --- | ---: | ---: |")
    for name, entry in result["context"].items():
        lines.append(f"| {name} | {entry['total']} | {entry['code']} |")
    lines.append("")
    return "\n".join(lines)


def main() -> int:
    result: dict = {"zig": {}, "mylang": {}, "mylang_tests": {}, "context": {}}

    for name, path in ZIG_MODULES.items():
        result["zig"][name] = count_zig(path)
    for name, path in MY_MODULES.items():
        if path.exists():
            result["mylang"][name] = count_my(path)
    for name, path in MY_TESTS.items():
        if path.exists():
            result["mylang_tests"][name] = count_my(path)
    for name, path in CONTEXT_FILES.items():
        if path.exists():
            result["context"][name] = count_my(path)

    core_names = ["ast", "tokenizer", "parser"]
    result["totals"] = {
        "zig_core": sum_files([result["zig"][n] for n in core_names if n in result["zig"]]),
        "zig_printer": sum_files([result["zig"]["printer"]] if "printer" in result["zig"] else []),
        "zig_all": sum_files(list(result["zig"].values())),
        "my_core": sum_files([result["mylang"][n] for n in core_names if n in result["mylang"]]),
        "my_printer": sum_files([result["mylang"]["printer"]] if "printer" in result["mylang"] else []),
        "my_all": sum_files(list(result["mylang"].values())),
        "my_tests": sum_files(list(result["mylang_tests"].values())),
    }

    out = REPO / "experiments/sexpr-port/evidence/metrics.json"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(result, indent=2) + "\n")

    md = REPO / "experiments/sexpr-port/evidence/summary.md"
    md.write_text(render_markdown(result))

    print(f"wrote {out}\n")
    header = f"{'impl':<12}{'module':<12}{'total':>7}{'code':>7}{'comment':>9}{'blank':>7}{'tests':>7}"
    print(header)
    print("-" * len(header))
    for lang in ("zig", "mylang"):
        for name, entry in result[lang].items():
            print(
                f"{lang:<12}{name:<12}{entry['total']:>7}{entry['code']:>7}"
                f"{entry['comment']:>9}{entry['blank']:>7}{entry['tests']:>7}"
            )
    for name, entry in result["mylang_tests"].items():
        print(f"{'my-tests':<12}{name:<12}{entry['total']:>7}{entry['code']:>7}{entry['comment']:>9}{entry['blank']:>7}{entry['tests']:>7}")
    print()
    for key in ("zig_core", "my_core", "zig_printer", "my_printer", "my_tests", "zig_all", "my_all"):
        t = result["totals"][key]
        print(
            f"{key:<12} total={t['total']:>5} code={t['code']:>5} comment={t['comment']:>5} "
            f"blank={t['blank']:>4} tests={t['tests']:>3} chars={t['chars']:>7} decls={t['decls']}"
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
