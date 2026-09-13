#!/usr/bin/env python3
"""Execute every fenced documentation example against a pinned compiler.

Walks README.md, SPEC.md and docs/**/*.md, extracts fenced code blocks, and runs
the ones tagged ``mylang`` or ``my`` through the compiler.  Blocks carry optional
``# doc:`` (or ``// doc:``) directives on their leading lines; see
docs/experiments/doc-examples.md for the grammar.  Blocks tagged as prose that
still look like guest source are reported as mis-tagged so stale examples cannot
hide behind a non-executing fence.
"""
import argparse
from fnmatch import fnmatch
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
EXECUTABLE_TAGS = ("mylang", "my")
PROSE_TAGS = ("", "text", "rust", "python", "go")
GUEST_SHAPE = re.compile(r"^(?:def main|fn main|module )", re.M)
PRINT_CALL = re.compile(r"(?<![A-Za-z0-9_.])print\s*\(")
MODULE_LINE = re.compile(r"^module[ \t]+([A-Za-z_][A-Za-z0-9_]*)", re.M)
MAIN_LINE = re.compile(r"^[ \t]*(?:pub[ \t]+)?(?:def|fn)[ \t]+main\b", re.M)
DIRECTIVE = re.compile(r"^[ \t]*(?:#|//)[ \t]*doc:[ \t]*(?P<name>[A-Za-z-]+)[ \t]*(?P<rest>.*?)[ \t]*$")
KNOWN = ("expect", "expect-error", "check", "project", "file", "skip", "not-mylang")
TIMEOUT = 120
# `check` and `check-project` both demand an entry point, so a declaration-only example
# gets this neutral one appended.  Every spelling shares one file grammar, so the
# Python-style stub compiles after brace-syntax declarations too.
STUB = "def main() -> int:\n    return 0\n"


class Fence:
    """One fenced code block lifted out of a Markdown document."""

    def __init__(self, document, line, tag, flags, body):
        self.document = document
        self.line = line
        self.tag = tag
        self.flags = flags
        self.body = body
        self.directives = []
        self.source = body
        self.error = None

    @property
    def label(self):
        """Human-readable `document:line` identity used in reports."""
        return f"{self.document}:{self.line}"


def fences(document, text):
    """Yield every fenced block of a document with its info string and body."""
    lines = text.splitlines()
    found, index = [], 0
    while index < len(lines):
        opener = re.match(r"^(?P<indent>[ \t]*)(?P<ticks>```+|~~~+)(?P<info>.*)$", lines[index])
        if not opener:
            index += 1
            continue
        ticks, indent, start = opener.group("ticks"), opener.group("indent"), index
        info = opener.group("info").strip().split()
        closer = re.compile(r"^[ \t]*" + re.escape(ticks[0]) + "{" + str(len(ticks)) + r",}[ \t]*$")
        body, index = [], index + 1
        while index < len(lines) and not closer.match(lines[index]):
            body.append(lines[index][len(indent):] if lines[index].startswith(indent) else lines[index])
            index += 1
        index += 1
        found.append(Fence(document, start + 1, info[0] if info else "", tuple(info[1:]), "\n".join(body)))
    return found


def directives(fence):
    """Split leading ``doc:`` directives from a fence body, recording bad names."""
    lines, taken = fence.body.splitlines(), 0
    for line in lines:
        match = DIRECTIVE.match(line)
        if not match:
            if line.strip() == "":
                taken += 1
                continue
            break
        name, rest = match.group("name"), match.group("rest")
        if name not in KNOWN:
            fence.error = f"unknown directive '# doc: {name}'"
        fence.directives.append((name, rest))
        taken += 1
    while taken and lines[taken - 1].strip() == "":
        taken -= 1
    fence.source = "\n".join(lines[taken:])
    return fence


def values(fence, name):
    """Every argument given to a directive, in document order."""
    return [rest for key, rest in fence.directives if key == name]


class Unit:
    """A single executable example: one block, or one grouped multi-file project."""

    def __init__(self, kind, label, document):
        self.kind = kind
        self.label = label
        self.document = document
        self.members = []
        self.status = "pending"
        self.detail = ""
        self.command = []

    def record(self, status, detail=""):
        """Set the outcome and explanatory detail for this unit."""
        self.status, self.detail = status, detail
        return self


def group(blocks):
    """Fold executable fences into standalone units and named project units."""
    units, projects = [], {}
    for fence in blocks:
        names = values(fence, "project")
        if not names:
            unit = Unit("block", fence.label, fence.document)
            unit.members.append(fence)
            units.append(unit)
            continue
        key = (fence.document, names[0])
        if key not in projects:
            projects[key] = Unit("project", f"{fence.document}#{names[0]}", fence.document)
            units.append(projects[key])
        projects[key].members.append(fence)
    return units


def plan(unit):
    """Decide how a unit should be exercised, or why it cannot be."""
    skips = [reason for member in unit.members for reason in values(member, "skip")]
    broken = [member.error for member in unit.members if member.error]
    if broken:
        return {"action": "invalid", "detail": "; ".join(broken)}
    if skips:
        if any(not reason.strip() for reason in skips):
            return {"action": "invalid", "detail": "'# doc: skip' requires a reason"}
        return {"action": "skip", "detail": "; ".join(skips)}
    for member in unit.members:
        if values(member, "not-mylang"):
            return {"action": "invalid", "detail": "'# doc: not-mylang' cannot tag an executable block"}
    if unit.kind == "project" and not any(values(member, "file") == ["main.my"] for member in unit.members):
        return {"action": "invalid", "detail": "project has no '# doc: file main.my' entry"}
    expect = [line for member in unit.members for line in values(member, "expect")]
    codes = [code.strip() for member in unit.members for code in values(member, "expect-error")]
    forced = any(values(member, "check") for member in unit.members)
    if codes and (expect or forced):
        return {"action": "invalid", "detail": "'expect-error' cannot combine with 'expect' or 'check'"}
    if codes:
        return {"action": "expect-error", "codes": codes}
    if forced:
        return {"action": "check", "expect": expect}
    if not any(MAIN_LINE.search(member.source) for member in unit.members):
        if expect:
            return {"action": "invalid", "detail": "'expect' needs a 'main' to run"}
        return {"action": "check", "expect": []}
    return {"action": "run", "expect": expect}


def write(unit, directory):
    """Materialise a unit's sources under a private directory, returning the entry."""
    directory.mkdir(parents=True, exist_ok=True)
    entry = None
    for index, member in enumerate(unit.members):
        named = values(member, "file")
        module = MODULE_LINE.search(member.source)
        if named:
            name = named[0].strip()
        elif module:
            name = f"{module.group(1)}.my"
        else:
            name = "main.my" if len(unit.members) == 1 else f"block{index}.my"
        path = directory / name
        path.write_text(member.source + "\n")
        if name == "main.my" or (entry is None and unit.kind == "block"):
            entry = path
    entry = entry or directory / "main.my"
    if not any(MAIN_LINE.search(member.source) for member in unit.members):
        entry.write_text(entry.read_text() + STUB)
    return entry


def project_shaped(unit, entry):
    """Whether a unit must go through the project commands rather than single-file ones."""
    return len(unit.members) > 1 or bool(MODULE_LINE.search(entry.read_text()))


def diagnose(stderr):
    """Collect diagnostic codes from ``--diagnostics=json`` JSON Lines on stderr."""
    codes = []
    for line in stderr.splitlines():
        if not line.startswith("{"):
            continue
        try:
            payload = json.loads(line)
        except json.JSONDecodeError:
            continue
        code = payload.get("diagnostic", {}).get("code")
        if code:
            codes.append(code)
    return codes


def normalise(text):
    """Trim a stream for comparison against ``expect`` text."""
    return "\n".join(line.rstrip() for line in text.strip().splitlines())


def invoke(compiler, command, entry, options):
    """Run one compiler command against an entry file with extra CLI options."""
    argv = [str(compiler), command, str(entry), "--diagnostics=json", *options.get("argv", ())]
    if options.get("verbose"):
        print("  $ " + " ".join(argv))
    return subprocess.run(argv, capture_output=True, text=True, timeout=TIMEOUT), argv


def execute(unit, compiler, directory, verbose):
    """Carry out a unit's plan and record its outcome."""
    intent = plan(unit)
    if intent["action"] in ("skip", "invalid"):
        return unit.record("skipped" if intent["action"] == "skip" else "failed", intent["detail"])
    entry = write(unit, directory)
    project = project_shaped(unit, entry)
    wanted = intent["action"]
    command = ("check-project" if project else "check") if wanted in ("check", "expect-error") else ("run-project" if project else "run")
    try:
        result, unit.command = invoke(compiler, command, entry, {"verbose": verbose, "argv": options(unit, command)})
    except subprocess.TimeoutExpired:
        return unit.record("failed", f"'{command}' did not finish within {TIMEOUT} seconds")
    if verbose and result.stderr:
        print("  ! " + result.stderr.strip().replace("\n", "\n  ! "))
    if wanted == "expect-error":
        codes = diagnose(result.stderr)
        if result.returncode == 0:
            return unit.record("failed", f"expected {intent['codes']} but the example checked cleanly")
        missing = [code for code in intent["codes"] if code not in codes]
        if missing:
            return unit.record("failed", f"expected {missing}, saw {codes or 'no JSON diagnostics'}")
        return unit.record("checked", f"rejected with {intent['codes']}")
    if result.returncode != 0:
        return unit.record("failed", f"exit {result.returncode}: {normalise(result.stderr) or normalise(result.stdout)}")
    if wanted == "check":
        stubbed = not any(MAIN_LINE.search(member.source) for member in unit.members)
        return unit.record("checked", "generated entry point" if stubbed else "")
    if intent["expect"]:
        wanted_text = normalise("\n".join(intent["expect"]))
        actual = normalise(result.stdout)
        if actual != wanted_text:
            return unit.record("failed", f"expected stdout {wanted_text!r}, saw {actual!r}")
        return unit.record("run", f"stdout {wanted_text!r}")
    return unit.record("run")


def options(unit, command):
    """CLI options a unit needs: result reporting, plus any granted directories."""
    if not command.startswith("run"):
        return []
    # An example that prints its own output asserts that output; one that does not
    # keeps asserting the entry point's int result, which `run` reports on request.
    prints = any(PRINT_CALL.search(member.source) for member in unit.members)
    return [] if prints else ["--print-result"]


def mistagged(fence):
    """Whether a prose-tagged fence still looks like guest source."""
    if "notest" in fence.flags or values(fence, "not-mylang"):
        return False
    return fence.tag in PROSE_TAGS and bool(GUEST_SHAPE.search(fence.source))


def documents(root, pattern):
    """Every documentation file in scan order, minus docs/legacy/, honouring an optional path filter."""
    found = [root / "README.md", root / "SPEC.md"] + sorted((root / "docs").rglob("*.md"))
    relative = [path for path in found if path.exists()]
    relative = [path for path in relative if not path.relative_to(root).as_posix().startswith("docs/legacy/")]
    if pattern:
        relative = [path for path in relative if fnmatch(path.relative_to(root).as_posix(), pattern)]
    return relative


def scan(root, pattern):
    """Extract and classify every fence of every selected document."""
    executable, suspects, counts = [], [], {}
    for path in documents(root, pattern):
        name = path.relative_to(root).as_posix()
        blocks = [directives(fence) for fence in fences(name, path.read_text())]
        counts[name] = len(blocks)
        for fence in blocks:
            if fence.tag in EXECUTABLE_TAGS and "notest" not in fence.flags:
                executable.append(fence)
            elif mistagged(fence):
                suspects.append(fence)
    return executable, suspects, counts


def tabulate(units, suspects, counts):
    """Per-document tallies of run, checked, skipped, mis-tagged and failed units."""
    table = {name: {"blocks": total, "run": 0, "checked": 0, "skipped": 0, "mistagged": 0, "failed": 0, "skips": []}
             for name, total in counts.items()}
    for unit in units:
        row = table[unit.document]
        row[unit.status] = row.get(unit.status, 0) + 1
        if unit.status == "skipped":
            row["skips"].append(unit.detail)
    for fence in suspects:
        table[fence.document]["mistagged"] += 1
    return table


def report(table, units, suspects):
    """Print the human-readable summary and return the failure count."""
    failures = [unit for unit in units if unit.status == "failed"]
    for name in sorted(table):
        row = table[name]
        if not any(row[key] for key in ("run", "checked", "skipped", "mistagged", "failed")):
            continue
        print(f"  {name}: {row['run']} run, {row['checked']} checked, {row['skipped']} skipped, "
              f"{row['mistagged']} mis-tagged, {row['failed']} failed")
        for reason in row["skips"]:
            print(f"      skip: {reason}")
    for fence in suspects:
        print(f"MIS-TAGGED {fence.label}: '```{fence.tag}' block looks like guest source; "
              "retag it 'mylang' or mark it '# doc: not-mylang'")
    for unit in failures:
        print(f"FAILED {unit.label}: {unit.detail}")
    counted = {key: sum(row[key] for row in table.values()) for key in ("run", "checked", "skipped", "mistagged", "failed")}
    print(f"Doc examples: {len(table)} files scanned, {sum(row['blocks'] for row in table.values())} blocks found, "
          f"{counted['run']} run, {counted['checked']} checked, {counted['skipped']} skipped, "
          f"{counted['mistagged']} mis-tagged, {counted['failed']} failed")
    return counted


def main():
    """Entry point for the executable-documentation gate."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler", type=Path, default=ROOT / "zig-out/bin/mylang")
    parser.add_argument("--report", type=Path)
    parser.add_argument("--filter", dest="pattern", help="glob matched against repository-relative document paths")
    parser.add_argument("--verbose", action="store_true")
    args = parser.parse_args()
    compiler = args.compiler.resolve()
    if not compiler.exists():
        print(f"Doc examples: compiler {compiler} is missing; build it first", file=sys.stderr)
        return 2
    blocks, suspects, counts = scan(ROOT, args.pattern)
    units = group(blocks)
    temporary = Path(tempfile.mkdtemp(prefix="mylang-doc-examples-"))
    try:
        for index, unit in enumerate(units):
            if args.verbose:
                print(f"[{index + 1}/{len(units)}] {unit.label}")
            execute(unit, compiler, temporary / f"unit{index:03d}", args.verbose)
    finally:
        shutil.rmtree(temporary, ignore_errors=True)
    table = tabulate(units, suspects, counts)
    counted = report(table, units, suspects)
    executable = counted["run"] + counted["checked"] + counted["skipped"] + counted["failed"]
    if executable == 0:
        print("Doc examples: no executable blocks found; the extractor or the filter is wrong", file=sys.stderr)
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps({
            "version": "doc-examples-v1",
            "compiler": str(compiler),
            "compiler_sha256": hashlib.sha256(compiler.read_bytes()).hexdigest(),
            "totals": counted,
            "files": table,
            "units": [{"label": unit.label, "kind": unit.kind, "document": unit.document,
                       "status": unit.status, "detail": unit.detail, "command": unit.command} for unit in units],
            "mistagged": [{"label": fence.label, "tag": fence.tag} for fence in suspects],
        }, indent=2) + "\n")
    return 0 if executable and not counted["failed"] and not counted["mistagged"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
