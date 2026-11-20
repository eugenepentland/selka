#!/usr/bin/env python3
"""The gate action `goals_register`: fail when the goals register names evidence that does not exist.

`docs/goals.md` lists the language's goals and, for each, the evidence behind it: Lean theorems, Zig tests, gate actions,
files and pinned examples (`test/fixtures/goals/docs/*.md`). This driver reads the page and the pins and prints one line
`file:line: message` for each thing that is not true. It runs no Lean (the proof actions do) and refuses no program.

    python3 tests/goals_register.py --compiler zig-out/bin/selka
    python3 tests/goals_register.py --compiler C --root DIR --page docs/goals.md --pins test/fixtures/goals
    python3 tests/goals_register.py --compiler C --map docs/tooling/compiler-map.md

`--map PAGE` adds the compiler map's check (`tests/compiler_map.py`): the gate passes it, so the one action that already reads
documentation and checks the paths it names also fails, with the map's line number, when a file or function the map names is
gone. Its findings are kinds `path`, `function`, `command`, `size` and `inputs`; see that file.

A finding is one of:

* pinned example: `selka doctest PINS` does not exit 0 with "0 failed";
* evidence path: a backquoted repository path does not exist;
* theorem: a Lean name written with its file is not declared there (by text, inside the namespace its name spells);
* gate action: a name after "Gate action" is not an action registered in `build.zig`;
* example id: an id the page cites has no pin, a pin is never cited, or a pin has no example block;
* exception count: the summary table and the entry's list of exceptions disagree;
* duplicate row: the summary table has more than one row for a goal;
* duplicate field: an entry gives one of its labelled fields (`- **Evidence.**`) more than once;
* inputs: the page, a pin, a named path or this check's own files are not inputs of the `goals_register` list of
  `build_test_inputs.zig`, so an edit to one would leave a stale green verdict.

The format the page must follow is stated in its section "How this page is checked". Exit status: 0 when nothing is
found, 1 when something is, 2 on a usage error.
"""
from __future__ import annotations

import argparse
import difflib
import os
import re
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import compiler_map  # noqa: E402  (the compiler map's check, run by `--map`)
import test_inputs_coverage  # noqa: E402  (the one parser of build_test_inputs.zig lists)

LIST_NAME = "goals_register"
FILE_EXTENSIONS = ("md", "zig", "lean", "py", "selka", "json", "zon", "toml", "sh", "txt", "c", "h")
PATH_TOKEN = re.compile(r"^[\w.+*?-]+(?:/[\w.+*?-]+)*/?$")
EXTENSION_TOKEN = re.compile(r"^[\w.+*?-]*[\w+*?-]\.(?:%s)$" % "|".join(FILE_EXTENSIONS))
LEAN_NAME = re.compile(r"^[A-Za-z_][\w.']*$")
ID = r"G\d+-[HX]\d+"
ID_PATTERN = re.compile(r"\b(G(\d+)-([HX])(\d+))(?:\s+to\s+(G(\d+)-([HX])(\d+)))?")
PIN_HEADING = re.compile(r"^\*\*(%s(?:\s*(?:,|and)\s*%s)*)\b" % (ID, ID), re.M)
GATE_PHRASE = re.compile(r"\bgate actions?\b", re.I)
LIST_GAP = re.compile(r"(?:\s*\([^()`]*\))?\s*(?:,\s*and|,|and)\s*")
LEAN_DECLARATION = re.compile(
    r"^\s*(?:@\[[^\]]*\]\s*)*(?:(?:private|protected|noncomputable|unsafe|partial|nonrec)\s+)*(?:theorem|lemma)\s+([^\s:({\[⦃]+)"
)
DOCTEST_FAILURE = re.compile(r"^FAILED (\S+?):(\d+): (.*)$")
DOCTEST_SUMMARY = re.compile(r"\b(\d+) failed$")


@dataclass
class Finding:
    """One thing that is not true: where it is written, which check found it and what was expected."""

    path: str
    line: int
    kind: str
    message: str

    def __str__(self) -> str:
        where = "{}:{}".format(self.path, self.line) if self.line else self.path
        return "{}: {}: {}".format(where, self.kind, self.message)


@dataclass
class Span:
    """A backquoted span of the page: its text and where it starts."""

    text: str
    start: int
    end: int
    line: int


@dataclass
class Report:
    """The findings of one run and the counts of what was checked, for the one-line summary."""

    findings: list[Finding] = field(default_factory=list)
    counts: dict[str, int] = field(default_factory=dict)
    doctest: str = ""


def mask_fences(text: str) -> str:
    """The text with every fenced block blanked, newlines kept, so offsets and line numbers still match."""
    def blank(match: re.Match[str]) -> str:
        return re.sub(r"[^\n]", " ", match.group())
    return re.sub(r"^(```|~~~).*?^\1[ \t]*$", blank, text, flags=re.M | re.S)


def line_of(text: str, offset: int) -> int:
    """The 1-based line of a character offset."""
    return text.count("\n", 0, offset) + 1


def code_spans(masked: str) -> list[Span]:
    """Every backquoted span outside fenced blocks, in order."""
    return [Span(m.group(1), m.start(), m.end(), line_of(masked, m.start())) for m in re.finditer(r"`([^`\n]+)`", masked)]


def is_path(token: str) -> bool:
    """Whether a backquoted token is a repository path: no space, a `/` or a known file extension."""
    return bool(PATH_TOKEN.match(token)) and ("/" in token or bool(EXTENSION_TOKEN.match(token)))


def expand_path(root: Path, path: str) -> list[str]:
    """The repository paths a token names: itself when it exists, each match when it holds a `*` or `?`, else none."""
    if re.search(r"[*?]", path):
        return sorted(p.relative_to(root).as_posix() for p in root.glob(path.rstrip("/")))
    return [path] if (root / path.rstrip("/")).exists() else []


def named_paths(spans: list[Span]) -> list[Span]:
    """The spans of the page that are repository paths."""
    return [span for span in spans if is_path(span.text)]


def strip_lean_comments(text: str) -> str:
    """Lean source with line comments and (nested) block comments and doc comments removed, newlines kept."""
    out: list[str] = []
    depth = 0
    i = 0
    while i < len(text):
        two = text[i:i + 2]
        if depth == 0 and two == "--":
            end = text.find("\n", i)
            i = len(text) if end < 0 else end
        elif two == "/-":
            depth += 1
            i += 2
        elif depth > 0 and two == "-/":
            depth -= 1
            i += 2
        else:
            if depth == 0 or text[i] == "\n":
                out.append(text[i])
            i += 1
    return "".join(out)


def lean_theorems(text: str) -> dict[str, int]:
    """Full name to line of every `theorem` and `lemma` of a Lean file, with the namespaces they sit in."""
    frames: list[list[str]] = []
    found: dict[str, int] = {}
    for number, line in enumerate(strip_lean_comments(text).splitlines(), 1):
        stripped = line.strip()
        namespace = re.match(r"namespace\s+(\S+)", stripped)
        if namespace:
            frames.append(namespace.group(1).split("."))
        elif re.match(r"section(\s|$)", stripped):
            frames.append([])
        elif re.match(r"end(\s|$)", stripped):
            if frames:
                frames.pop()
        else:
            declaration = LEAN_DECLARATION.match(line)
            if declaration:
                name = declaration.group(1)
                if name.startswith("_root_."):
                    found.setdefault(name[len("_root_."):], number)
                else:
                    found.setdefault(".".join([part for frame in frames for part in frame] + [name]), number)
    return found


def theorem_citations(spans: list[Span], masked: str) -> list[tuple[str, Span, Span]]:
    """(Lean name, name span, file span) for each `` `Name` (`File.lean`) `` the page writes, names joined by commas and 'and'."""
    cited = []
    for index, span in enumerate(spans):
        if not span.text.endswith(".lean") or index == 0:
            continue
        if not re.fullmatch(r"\s*\(\s*", masked[spans[index - 1].end:span.start]):
            continue
        j = index - 1
        while j >= 0 and LEAN_NAME.match(spans[j].text):
            cited.append((spans[j].text, spans[j], span))
            if j == 0 or not re.fullmatch(r"\s*(?:,\s*and|,|and)\s*", masked[spans[j - 1].end:spans[j].start]):
                break
            j -= 1
    return sorted(cited, key=lambda item: item[1].start)


def gate_action_citations(spans: list[Span], masked: str) -> list[Span]:
    """The spans written after the words 'Gate action(s)': the first name and each one joined by commas or 'and'."""
    cited = []
    for phrase in GATE_PHRASE.finditer(masked):
        first = next((s for s in spans if s.start >= phrase.end()), None)
        if first is None or masked[phrase.end():first.start].strip():
            continue
        cited.append(first)
        index = spans.index(first)
        while index + 1 < len(spans) and LIST_GAP.fullmatch(masked[spans[index].end:spans[index + 1].start]):
            index += 1
            cited.append(spans[index])
    return cited


def registered_actions(root: Path) -> set[str]:
    """Action names the build registers: `register("NAME"` in build.zig, and each declared input list a step is keyed on."""
    build = (root / "build.zig").read_text(errors="replace")
    declared = (root / "build_test_inputs.zig").read_text(errors="replace")
    names = set(re.findall(r'\.register\("([^"]+)"', build))
    names.update(name for name in re.findall(r"^pub const (\w+) =", declared, re.M) if '"%s"' % name in build)
    return names


def expand_ids(masked: str) -> list[tuple[str, int, str | None]]:
    """(id, line, problem) for every example id the page cites; `G7-H1 to G7-H3` cites each id of the run."""
    cited = []
    for match in ID_PATTERN.finditer(masked):
        line = line_of(masked, match.start())
        if match.group(5) is None:
            cited.append((match.group(1), line, None))
            continue
        goal, kind, low = match.group(2), match.group(3), int(match.group(4))
        if (goal, kind) != (match.group(6), match.group(7)) or int(match.group(8)) < low:
            cited.append((match.group(0), line, "a range joins two ids of one goal and kind, in order"))
            continue
        cited.extend(("G{}-{}{}".format(goal, kind, n), line, None) for n in range(low, int(match.group(8)) + 1))
    return cited


def pin_ids(root: Path, pins: str) -> tuple[dict[str, tuple[str, int, bool]], list[Finding]]:
    """id to (file, line, has an example) of every pin under `pins`, and the findings about duplicate ids."""
    found: dict[str, tuple[str, int, bool]] = {}
    problems: list[Finding] = []
    for path in sorted((root / pins).rglob("*.md")):
        relative = path.relative_to(root).as_posix()
        text = path.read_text(errors="replace")
        headings = list(PIN_HEADING.finditer(text))
        for index, heading in enumerate(headings):
            end = headings[index + 1].start() if index + 1 < len(headings) else len(text)
            has_example = bool(re.search(r"^(?:```|~~~)selka\b", text[heading.end():end], re.M))
            for identifier in re.findall(ID, heading.group(1)):
                line = line_of(text, heading.start())
                if identifier in found:
                    problems.append(Finding(relative, line, "example id", "pin {} is already defined at {}:{}".format(identifier, *found[identifier][:2])))
                found.setdefault(identifier, (relative, line, has_example))
    return found, problems


def check_ids(root: Path, page: str, pins: str, masked: str, report: Report) -> None:
    """Every cited id has a pin with an example block, and every pin is cited."""
    pinned, problems = pin_ids(root, pins)
    report.findings.extend(problems)
    cited = expand_ids(masked)
    seen: set[str] = set()
    for identifier, line, problem in cited:
        if problem:
            report.findings.append(Finding(page, line, "example id", "{} is not a run of ids: {}".format(identifier, problem)))
        elif identifier not in pinned:
            report.findings.append(Finding(page, line, "example id", "{} is cited but no pin under {} has that id".format(identifier, pins)))
        seen.add(identifier)
    for identifier, (path, line, has_example) in sorted(pinned.items()):
        if identifier not in seen:
            report.findings.append(Finding(path, line, "example id", "pin {} is never cited in {}".format(identifier, page)))
        if not has_example:
            report.findings.append(Finding(path, line, "example id", "pin {} has no ```selka block before the next pin".format(identifier)))
    report.counts["pinned examples"] = len(pinned)


def check_paths(root: Path, page: str, spans: list[Span], report: Report) -> list[Span]:
    """Every backquoted repository path exists; returns the spans that are paths."""
    paths = named_paths(spans)
    for span in paths:
        if not expand_path(root, span.text):
            report.findings.append(Finding(page, span.line, "evidence path", "`{}` does not exist (a file of another repository is written `name:path` and is not checked)".format(span.text)))
    report.counts["paths"] = len(paths)
    return paths


def check_theorems(root: Path, page: str, spans: list[Span], masked: str, report: Report) -> None:
    """Every Lean name written with its file is declared there as a theorem, inside the namespace its name spells."""
    cache: dict[str, dict[str, int]] = {}
    citations = theorem_citations(spans, masked)
    for name, name_span, file_span in citations:
        file = file_span.text
        if not (root / file).is_file():
            continue  # the evidence-path check names the missing file
        if file not in cache:
            cache[file] = lean_theorems((root / file).read_text(errors="replace"))
        if name not in cache[file]:
            namespace, _, last = name.rpartition(".")
            expected = "`theorem {}` inside `namespace {}`".format(last, namespace) if namespace else "`theorem {}` at the root, written with its namespace if it has one".format(name)
            near = difflib.get_close_matches(name, cache[file], n=2)
            hint = " (the file declares {})".format(", ".join("`%s`" % n for n in near)) if near else ""
            report.findings.append(Finding(page, name_span.line, "theorem", "`{}` is not declared in {}: expected {}{}".format(name, file, expected, hint)))
    report.counts["theorems"] = len(citations)


def check_gate_actions(root: Path, page: str, spans: list[Span], masked: str, report: Report) -> None:
    """Every name written after 'Gate action' is an action `build.zig` registers."""
    registered = registered_actions(root)
    cited = gate_action_citations(spans, masked)
    for span in cited:
        if span.text not in registered:
            near = difflib.get_close_matches(span.text, registered, n=3)
            hint = " (did you mean {}?)".format(", ".join("`%s`" % n for n in near)) if near else ""
            report.findings.append(Finding(page, span.line, "gate action", "`{}` is not a verification action registered in build.zig{}".format(span.text, hint)))
    report.counts["gate actions"] = len(cited)


def table_rows(text: str) -> list[tuple[str, int, int]]:
    """(goal id, declared exception count, line) for every row of the page's summary table, in order."""
    rows = []
    for number, line in enumerate(text.splitlines(), 1):
        cells = [cell.strip() for cell in line.split("|")]
        if len(cells) >= 5 and re.fullmatch(r"G\d+", cells[1]) and re.fullmatch(r"\d+", cells[-2]):
            rows.append((cells[1], int(cells[-2]), number))
    return rows


def summary_rows(text: str) -> dict[str, tuple[int, int]]:
    """Goal id to (declared exception count, line) for the first row of each goal in the page's summary table."""
    rows: dict[str, tuple[int, int]] = {}
    for goal, count, number in table_rows(text):
        rows.setdefault(goal, (count, number))
    return rows


def entry_exceptions(lines: list[str], start: int) -> tuple[int | None, int, str]:
    """(count or None, line, problem) of one entry's exceptions; `start` is the entry's first line (1-based)."""
    for offset, line in enumerate(lines):
        bullet = re.match(r"- \*\*(Exceptions?)\.\*\*(.*)", line)
        if not bullet:
            continue
        number = start + offset
        nested = []
        for follower in lines[offset + 1:]:
            if follower.strip() and not follower.startswith((" ", "\t")):
                break
            if re.match(r"\s+- ", follower):
                nested.append(len(follower) - len(follower.lstrip()))
        direct = nested.count(min(nested)) if nested else 0
        if bullet.group(1) == "Exception":
            return (1, number, "") if not nested else (None, number, "`**Exception.**` is one exception and has no nested list: write `**Exceptions.**` with one nested bullet each")
        if nested:
            return direct, number, ""
        if bullet.group(2).strip().lower().startswith("none"):
            return 0, number, ""
        return None, number, "`**Exceptions.**` has no nested bullets: write one nested bullet per exception, `**Exception.**` for exactly one, or `None` for none"
    return 0, 0, ""


def goal_entries(lines: list[str]) -> list[tuple[int, str, int]]:
    """(heading line, goal id, line of the next `##` or `###` heading or past the end) of each `### Gn.` entry, 1-based."""
    boundaries = [number for number, line in enumerate(lines, 1) if line.startswith("## ") or line.startswith("### ")]
    entries = []
    for number, line in enumerate(lines, 1):
        heading = re.match(r"### (G\d+)\. ", line)
        if heading:
            entries.append((number, heading.group(1), next((b for b in boundaries if b > number), len(lines) + 1)))
    return entries


def check_exceptions(page: str, text: str, report: Report) -> None:
    """The summary table's exception count equals the number of exceptions the entry lists."""
    rows = summary_rows(text)
    lines = text.splitlines()
    spans = goal_entries(lines)
    entries = {goal for _, goal, _ in spans}
    for number, goal, end in spans:
        count, line, problem = entry_exceptions(lines[number:end - 1], number + 1)
        if goal not in rows:
            report.findings.append(Finding(page, number, "exception count", "{} has an entry but no row in the summary table".format(goal)))
        elif problem:
            report.findings.append(Finding(page, line, "exception count", "{}: {}".format(goal, problem)))
        elif count != rows[goal][0]:
            where = "its list is at line {}".format(line) if line else "it lists none"
            report.findings.append(Finding(page, rows[goal][1], "exception count", "{} says {} open exceptions in the summary table but the entry lists {} ({})".format(goal, rows[goal][0], count, where)))
    for goal, (_, number) in sorted(rows.items()):
        if goal not in entries:
            report.findings.append(Finding(page, number, "exception count", "{} has a row in the summary table but no `### {}.` entry".format(goal, goal)))
    report.counts["goals"] = len(rows)


def check_repeats(page: str, text: str, masked: str, report: Report) -> None:
    """A goal has one row in the summary table and an entry gives each labelled field once; a merge that keeps both sides of an edit repeats them."""
    first: dict[str, int] = {}
    for goal, _, number in table_rows(text):
        if goal in first:
            report.findings.append(Finding(page, number, "duplicate row", "{} has a second row in the summary table (the first is at line {}): keep one".format(goal, first[goal])))
        first.setdefault(goal, number)
    lines = masked.splitlines()
    for number, goal, end in goal_entries(lines):
        seen: dict[str, int] = {}
        for offset, line in enumerate(lines[number:end - 1], number + 1):
            field_label = re.match(r"- \*\*([^*]+?)\.\*\*", line)
            if not field_label:
                continue
            if field_label.group(1) in seen:
                report.findings.append(Finding(page, offset, "duplicate field", "{} gives `{}` twice (first at line {}): keep one".format(goal, field_label.group(1), seen[field_label.group(1)])))
            seen.setdefault(field_label.group(1), offset)


def check_inputs(root: Path, page: str, pins: str, paths: list[Span], report: Report) -> None:
    """The page, the pins, this check's files and every named path are inputs of the action's list, so an edit reruns it."""
    declared = root / "build_test_inputs.zig"
    lists = test_inputs_coverage.declared_lists(declared.read_text(errors="replace"))
    entries = lists.get(LIST_NAME)
    if entries is None:
        report.findings.append(Finding("build_test_inputs.zig", 0, "inputs", "declares no `{}` list".format(LIST_NAME)))
        return

    def covered(path: str) -> bool:
        target = path + "/" if (root / path).is_dir() and not path.endswith("/") else path
        return test_inputs_coverage.covered(target, entries) or test_inputs_coverage.covered(path, entries)

    required: list[tuple[str, str, int]] = [(page, page, 0), ("build.zig", "build.zig", 0), ("build_test_inputs.zig", "build_test_inputs.zig", 0)]
    for own in ("tests/goals_register.py", "tests/test_inputs_coverage.py"):
        if (root / own).exists():
            required.append((own, own, 0))
    for pin in sorted((root / pins).rglob("*")):
        if pin.is_file() and not any(part.startswith(".") for part in pin.relative_to(root).parts):
            required.append((pin.relative_to(root).as_posix(), pin.relative_to(root).as_posix(), 0))
    for span in paths:
        required.extend((match, page, span.line) for match in expand_path(root, span.text))
    done: set[str] = set()
    for path, where, line in required:
        if path in done:
            continue
        done.add(path)
        if not covered(path):
            report.findings.append(Finding(where, line, "inputs", "`{}` is not covered by `{}` in build_test_inputs.zig, so an edit to it would not rerun this check: add it".format(path, LIST_NAME)))


def run_pins(root: Path, compiler: str, pins: str, report: Report) -> None:
    """Run `selka doctest PINS`; every pin must pass. A failed example is reported at its pin's file and line."""
    try:
        done = subprocess.run([compiler, "doctest", pins], cwd=root, capture_output=True, text=True, timeout=900)
    except (OSError, subprocess.TimeoutExpired) as error:
        report.findings.append(Finding(pins, 0, "pinned example", "cannot run `{} doctest {}`: {}".format(compiler, pins, error)))
        return
    lines = [line.rstrip() for line in done.stdout.splitlines() + done.stderr.splitlines() if line.strip()]
    report.doctest = lines[-1].strip() if lines else ""
    failed = DOCTEST_SUMMARY.search(report.doctest)
    if done.returncode == 0 and failed and failed.group(1) == "0":
        return
    shown = 0
    for line in lines:
        match = DOCTEST_FAILURE.match(line)
        if match:
            report.findings.append(Finding("{}/{}".format(pins.rstrip("/"), match.group(1)), int(match.group(2)), "pinned example", "failed: " + match.group(3)))
            shown += 1
    if not shown:
        tail = " | ".join(line.strip() for line in lines[-4:])
        report.findings.append(Finding(pins, 0, "pinned example", "`selka doctest {}` exited {} and did not end with `0 failed`: {}".format(pins, done.returncode, tail)))


def check_map(root: Path, map_page: str, report: Report) -> None:
    """Add the compiler map's findings (`tests/compiler_map.py`): a named path or function that is not there, a page over its size."""
    result = compiler_map.check(root, map_page)
    report.findings.extend(result.findings)
    report.counts["map paths"] = result.counts.get("paths", 0)
    report.counts["map functions"] = result.counts.get("functions", 0)


def check(root: Path, compiler: str, page: str = "docs/goals.md", pins: str = "test/fixtures/goals", map_page: str | None = None) -> Report:
    """Run every check of the register against the page and the pins under `root`, and of the compiler map when `map_page` names one."""
    report = Report()
    text = (root / page).read_text(errors="replace")
    masked = mask_fences(text)
    spans = code_spans(masked)
    paths = check_paths(root, page, spans, report)
    check_theorems(root, page, spans, masked, report)
    check_gate_actions(root, page, spans, masked, report)
    check_ids(root, page, pins, masked, report)
    check_exceptions(page, text, report)
    check_repeats(page, text, masked, report)
    check_inputs(root, page, pins, paths, report)
    run_pins(root, compiler, pins, report)
    if map_page:
        check_map(root, map_page, report)
    report.findings.sort(key=lambda f: (f.path, f.line, f.kind, f.message))
    return report


def main(argv: list[str] | None = None) -> int:
    """Command-line entry: print each finding on its own line, or one summary line when there are none."""
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--compiler", required=True, help="the selka compiler that runs the pinned examples")
    parser.add_argument("--root", default=".", help="the repository root (default: the working directory)")
    parser.add_argument("--page", default="docs/goals.md", help="the register page, relative to the root")
    parser.add_argument("--pins", default="test/fixtures/goals", help="the pinned examples' documentation root, relative to the root")
    parser.add_argument("--map", default=None, help="the compiler map page, relative to the root; its paths and functions are checked too")
    args = parser.parse_args(argv)
    root = Path(args.root).resolve()
    if not (root / args.page).is_file() or not (root / args.pins).is_dir():
        print("goals register: {} or {} not found under {}".format(args.page, args.pins, root), file=sys.stderr)
        return 2
    if args.map and not (root / args.map).is_file():
        print("goals register: the compiler map {} is not found under {}".format(args.map, root), file=sys.stderr)
        return 2
    report = check(root, os.path.abspath(args.compiler), args.page, args.pins, args.map)
    if report.findings:
        for finding in report.findings:
            print(finding, file=sys.stderr)
        print("goals register: {} finding(s); the format the page must follow is in its section \"How this page is checked\"".format(len(report.findings)), file=sys.stderr)
        return 1
    counts = ", ".join("{} {}".format(n, what) for what, n in report.counts.items())
    print("goals register: {} checked ({}); doctest: {}".format(args.page, counts, report.doctest))
    return 0


if __name__ == "__main__":
    sys.exit(main())
