#!/usr/bin/env python3
"""Read the output of a test run and print what an agent needs: the verdict, then only what failed.

This is a reader. It runs nothing and decides nothing: the exit status of the run is the verdict, and the text
only chooses what to print. A failed run in which no known failure form is found prints the last lines of the
log and says so; it never prints a pass. A run that exits 0 while its own counts show a failure is a FAIL too.

`scripts/focused_test.py` and `scripts/dev_loop.py test` print through `render()`:

    PASS units 'arena': 34 passed, 0 skipped (34 selected) in 41.2s

    FAIL units 'try': 99 passed, 1 failed, 0 skipped (100 selected) in 41.2s
    FAILED advice_messages_test.test.a try in a call's argument is accepted (TRYARG)
      at src/advice_messages_test.zig:86  try expectAccepted(half ++
      error from src/parser.zig:1435  if (self.cursor.recovered) return error.SourceError;

The forms read (taken from real logs, kept in scripts/run-report-fixtures/): a Zig `expect*` failure with its
`expected N, found M` line or its two blocks and the first difference; an error returned from a test; a panic
(`exited with code 134 with stderr:`); a leak; a test killed at its deadline; a compile error in a test root; a
filter that named no test; the F22 crash signature; a run still queued for a build slot; and the test binary's
own terminal form (`N name...FAIL (Err)` followed by the trace) that `dev_loop.py test` runs.
"""
from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MAX_LINES = 30
TAIL_LINES = 20
MAX_NAME = 400
MAX_TEXT = 160

RESULT = re.compile(r"test: RESULT (\{.*\})")
SELECTED = re.compile(r"(\d+)\s+test\(s\) selected")
BUILD_SUMMARY = re.compile(r"Build Summary: .*?; (\d+)/(\d+) tests passed(?: \(([^)]*)\))?")
ALL_PASSED = re.compile(r"^All (\d+) tests passed\.$", re.M)
COUNTS = re.compile(r"^(\d+) passed; (\d+) skipped; (\d+) failed\.$", re.M)
GUARDIAN_FAIL = re.compile(r"^test: FAIL \S+ (.*)$", re.M)
# `error: 'NAME' failed:` and its relatives. NAME may hold quotes, so the match is greedy up to the last `' word`.
HEADER = re.compile(r"^error: '(.*)' (failed|leaked|exited with code|timed out|crashed|logged)\b(.*)$")
TERMINAL_FAIL = re.compile(r"^(\d+) (.+)\.\.\.FAIL \(([^)]*)\)$")
FRAME = re.compile(r"^(\S.*?):(\d+):(\d+): 0x[0-9a-f]+ in (.+) \(([^()]*)\)\s*$")
CARET = re.compile(r"^\s*\^~*\s*$")
COMPILE_ERROR = re.compile(r"^(\S+\.(?:zig|selka|c|h)):(\d+):(\d+): error: (.*)$")
COMPILE_COUNT = re.compile(r"^error: (\d+) compilation errors?$")
EXPECTED_FOUND = re.compile(r"^expected .+, found .+$")
FIRST_DIFFERENCE = re.compile(r"^First difference occurs on line (\d+):$")
DEADLINE = re.compile(r"^(?:test|step) deadline: .+ ran [0-9.]+ s \(limit [0-9.]+ s\); killed")
QUEUE_WAIT = re.compile(r"^build-slot: FIFO ticket (\d+), position (\d+); .*waiting \(([0-9.]+)s so far\)")
ADMITTED = re.compile(r"^build-slot: \S+ slot \d+, FIFO ticket \d+ after ")
SLOT_ERROR = re.compile(r"^build-slot: (?!FIFO|\S+ slot \d+|shadow|finishing|trimming|cannot trim)(.+)$")
MACHINE = re.compile(r"General protection exception|trap=13|Segmentation fault|terminated with signal|"
                     r"terminated unexpectedly|\bkilled by signal")
# A frame that is the toolchain's or the test runner's, never the author's.
OUTSIDE = re.compile(r"/zig-toolchains/|/lib/std/|/lib/compiler/|guardian-zig/src/test_runner|tools/test_runner/")
REPO_PREFIX = re.compile(r"^/home/[^/]+/ai/canopy/[^/]+/")


def short_path(path: str) -> str:
    """The path as the repository names it: without the checkout's directory."""
    text = str(path)
    root = str(ROOT) + "/"
    if text.startswith(root):
        return text[len(root):]
    return REPO_PREFIX.sub("", text)


def cut(text: str, width: int = MAX_TEXT) -> str:
    """TEXT on one line, at most WIDTH characters."""
    text = text.strip()
    return text if len(text) <= width else text[:width - 3] + "..."


def read_frames(lines: list[str], start: int) -> tuple[list[dict], int]:
    """The stack frames that begin at LINES[START]: (frames, index of the first line after them).

    A frame is the `path:line:col: 0xADDR in function (module)` line, then the source line and a caret line when
    the compiler could print them.
    """
    frames, i = [], start
    while i < len(lines):
        match = FRAME.match(lines[i])
        if not match:
            break
        frame = {"path": match.group(1), "line": int(match.group(2)), "function": match.group(4), "source": ""}
        i += 1
        if i + 1 < len(lines) and CARET.match(lines[i + 1]):
            frame["source"] = lines[i].strip()
            i += 2
        frames.append(frame)
    return frames, i


def string_difference(message: list[str]) -> list[str]:
    """`first difference at line N`, `expected: ...`, `found: ...` from an expectEqualStrings block; [] when absent."""
    for i, line in enumerate(message):
        match = FIRST_DIFFERENCE.match(line.strip())
        if not match:
            continue
        shown = ["first difference at line " + match.group(1)]
        j = i + 1
        for label in ("expected", "found"):
            while j < len(message) and message[j].strip() != label + ":":
                j += 1
            if j + 1 >= len(message):
                return shown
            text, caret = message[j + 1], message[j + 2] if j + 2 < len(message) else ""
            shown.append("%s: %s" % (label, "(end of string)" if "end of string" in caret else cut(text)))
            j += 3
        return shown
    return []


def message_lines(message: list[str]) -> list[str]:
    """What the failed assertion said, in at most three or four lines."""
    message = [line.rstrip() for line in message if not line.startswith("test:")]
    difference = string_difference(message)
    if difference:
        return difference
    message = [line for line in message if line.strip()]
    wanted = [line for line in message if EXPECTED_FOUND.match(line)]
    if wanted:
        return [cut(wanted[-1])]
    panics = [line for line in message if " panic: " in line or line.startswith("panic: ")]
    if panics:
        return [cut(panics[0])]
    shown = [cut(line) for line in message[:3]]
    if len(message) > 3:
        shown.append("(%d more lines in the log)" % (len(message) - 3))
    return shown


def sites(frames: list[dict]) -> list[str]:
    """`at FILE:LINE  source` for the test's own frame, and `error from ...` when an inner repository frame differs."""
    own = [frame for frame in frames if not OUTSIDE.search(frame["path"])]
    test = next((frame for frame in own if frame["function"].startswith("test.")), None)
    first = own[0] if own else None
    found = []
    if test is not None:
        found.append("at %s:%d  %s" % (short_path(test["path"]), test["line"], cut(test["source"], 100)))
    if first is not None and first is not test:
        found.append("%s %s:%d  %s" % ("error from" if test is not None else "at",
                                       short_path(first["path"]), first["line"], cut(first["source"], 100)))
    return [line.rstrip() for line in found]


def what_kind(word: str, rest: str) -> str:
    """The kind of failure a header names, as a short phrase."""
    rest = rest.strip().rstrip(":").strip()
    if word == "failed":
        return "failed without output" if rest.startswith("without output") else ""
    if word == "exited with code":
        return "exited with code " + rest.split()[0] if rest else "crashed"
    return (word + " " + rest).strip()


def zig_failures(lines: list[str]) -> list[dict]:
    """The failed tests of a `zig build` log: each `error: 'NAME' failed:` header and the indented block under it."""
    found, i = [], 0
    while i < len(lines):
        match = HEADER.match(lines[i])
        i += 1
        if not match:
            continue
        body = []
        while i < len(lines) and lines[i].startswith("  "):
            body.append(lines[i][7:] if lines[i].startswith(" " * 7) else lines[i].lstrip())
            i += 1
        first_frame = next((k for k, line in enumerate(body) if FRAME.match(line)), len(body))
        frames, _ = read_frames(body, first_frame)
        details = message_lines(body[:first_frame])
        kind = what_kind(match.group(2), match.group(3))
        if kind:
            details.insert(0, kind)
        found.append({"name": match.group(1), "details": details + sites(frames)})
    return found


def terminal_failures(lines: list[str]) -> list[dict]:
    """The failed tests of a test binary run by itself: the assertion's message, `N name...FAIL (Err)`, the trace.

    The message is printed before the FAIL line and the trace after it, so a failure's message is what lies between
    the previous failure's trace and its own FAIL line.
    """
    found, previous_end = [], 0
    for index, line in enumerate(lines):
        match = TERMINAL_FAIL.match(line)
        if not match:
            continue
        message = [text for text in lines[previous_end:index] if not text.startswith("test:")]
        frames, previous_end = read_frames(lines, index + 1)
        details = message_lines(message) or ["error." + match.group(3)]
        found.append({"name": match.group(2), "details": details + sites(frames)})
    return found


def compile_errors(lines: list[str]) -> list[str]:
    """Up to three compile errors of a test root as `file:line:col: error: message` with the source line, and the count."""
    shown, total = [], 0
    for i, line in enumerate(lines):
        match = COMPILE_ERROR.match(line)
        if match:
            total += 1
            if len(shown) < 6:
                shown.append(cut("%s:%s:%s: error: %s" % (short_path(match.group(1)), match.group(2), match.group(3),
                                                           match.group(4))))
                if i + 1 < len(lines) and not COMPILE_ERROR.match(lines[i + 1]) and lines[i + 1].strip():
                    shown.append("  " + cut(lines[i + 1], 100))
    counted = [COMPILE_COUNT.match(line) for line in lines]
    count = next((int(m.group(1)) for m in counted if m), total)
    if shown:
        shown.insert(0, "compile error in the test root (%d); no test ran" % count)
    return shown


def counts(text: str) -> dict:
    """passed, failed, skipped, selected: the runner's own RESULT lines summed, else the build summary, else the closing line."""
    found = {"passed": 0, "failed": 0, "skipped": 0, "processes": 0, "aborted": False}
    for raw in RESULT.findall(text):
        try:
            parsed = json.loads(raw)
        except ValueError:
            continue
        if isinstance(parsed, dict):
            found["processes"] += 1
            for key in ("passed", "failed", "skipped"):
                found[key] += int(parsed.get(key, 0) or 0)
            found["aborted"] = found["aborted"] or bool(parsed.get("aborted"))
    if not found["processes"]:
        summary = BUILD_SUMMARY.search(text)
        closing = COUNTS.search(text)
        every = ALL_PASSED.search(text)
        if summary:
            found["passed"] = int(summary.group(1))
            extra = summary.group(3) or ""
            for word, key in (("skipped", "skipped"), ("failed", "failed")):
                hit = re.search(r"(\d+) " + word, extra)
                found[key] = int(hit.group(1)) if hit else 0
            found["processes"] = 1
        elif closing:
            found["passed"], found["skipped"], found["failed"] = (int(group) for group in closing.groups())
            found["processes"] = 1
        elif every:
            found["passed"] = int(every.group(1))
            found["processes"] = 1
    chosen = [int(n) for n in SELECTED.findall(text)]
    found["selected"] = sum(chosen) if chosen else None
    return found


def extra_lines(lines: list[str], failures: list[dict], found: dict) -> list[str]:
    """Lines about the run as a whole: a deadline, a filter that named no test, a leak, the machine's crash, the queue."""
    notes = []
    notes += [cut(line) for line in lines if DEADLINE.match(line)][:2]
    if any("nothing the filter named ran" in line for line in lines):
        notes.append("no test matched the filter: a zero-match filter fails the run; correct the filter text")
    else:
        guardian = [m.group(1) for m in GUARDIAN_FAIL.finditer("\n".join(lines))]
        loud = [text for text in guardian if "leaked" in text or "logged" in text]
        if loud:
            notes.append("guardian: " + cut(loud[0]))
    slot = [line for line in lines if SLOT_ERROR.match(line)]
    if slot:
        notes.append(cut(slot[-1]))
    if queued(lines):
        notes.append(queued(lines))
    if any(MACHINE.search(line) for line in lines):
        notes.append("the machine's signature (crash, signal or the F22 trap=13): run it once more before investigating")
    return notes


def queued(lines: list[str]) -> str:
    """`still queued for a build slot: ...` when the last build-slot line of the run is a wait, else ''."""
    last = None
    for line in lines:
        if ADMITTED.match(line):
            last = None
        match = QUEUE_WAIT.match(line)
        if match:
            last = match
    if last is None:
        return ""
    return "still queued for a build slot (ticket %s, position %s, %ss so far): it has not started" % last.groups()


def failure_block(failures: list[dict], room: int) -> list[str]:
    """The failures as lines, at most ROOM of them: each name in full, with as many detail lines as fit for all."""
    for depth in (6, 4, 3, 2, 1, 0):
        total = sum(1 + min(len(item["details"]), depth) for item in failures)
        if total <= room:
            break
    else:
        depth, total = 0, len(failures)
    shown, lines = failures, []
    if total > room:
        keep = max(room - 1, 0)
        shown = failures[:keep]
    for item in shown:
        lines.append("FAILED " + cut(item["name"], MAX_NAME))
        lines += ["  " + detail for detail in item["details"][:depth]]
    if len(shown) < len(failures):
        lines.append("... and %d more failing tests (names: grep -a -e \"^error: '\" -e '\\.\\.\\.FAIL' LOG)"
                     % (len(failures) - len(shown)))
    return lines


def verdict(returncode: int, found: dict, failures: list[dict]) -> str:
    """PASS only for exit status 0 with no failure in the runner's own counts and none found in the text."""
    if returncode != 0:
        return "FAIL"
    if found["failed"] or found["aborted"] or failures:
        return "FAIL"
    return "PASS"


def summary(state: str, what: str, found: dict, seconds: float | None, returncode: int) -> str:
    """The first line: verdict, what ran, how many tests, how long."""
    pieces = []
    if found["processes"]:
        pieces.append("%d passed" % found["passed"])
        if state == "FAIL" or found["failed"]:
            pieces.append("%d failed" % found["failed"])
        pieces.append("%d skipped" % found["skipped"])
    if not pieces and found["failed"]:
        pieces.append("%d failed" % found["failed"])
    text = ", ".join(pieces) if pieces else "no test count in the output"
    if found["selected"] is not None:
        text += " (%d selected)" % found["selected"]
    if found["processes"] > 1:
        text += " over %d test processes" % found["processes"]
    if seconds is not None:
        text += " in %.1fs" % seconds
    if state == "PASS" and found["processes"] and found["passed"] == 0:
        text += "; no test ran, check the filter"
    if returncode == 0 and state == "FAIL":
        text += "; exit status 0 but the output shows a failure"
    return "%s %s: %s" % (state, what, text)


def render(text: str, returncode: int, what: str, seconds: float | None = None, max_lines: int = MAX_LINES,
           tail: int = TAIL_LINES) -> list[str]:
    """The lines to print for one finished run: the summary, then (on failure) only what failed; at most MAX_LINES.

    The caller prints the closing `exit status N; log PATH` line (`closing()`).
    """
    lines = text.splitlines()
    found = counts(text)
    failures = zig_failures(lines) + terminal_failures(lines)
    state = verdict(returncode, found, failures)
    found["failed"] = max(found["failed"], len(failures)) if state == "FAIL" else found["failed"]
    out = [summary(state, what, found, seconds, returncode)]
    if state == "PASS":
        return out
    notes = compile_errors(lines) + extra_lines(lines, failures, found)
    room = max(max_lines - 1 - len(notes), 1)
    block = failure_block(failures, room) if failures else []
    out += block + notes
    if not failures and not notes:
        shown = lines[-tail:] if tail > 0 else []
        if not lines:
            out.append("the log is empty")
        else:
            out.append("no known failure form in the log; its last %d lines:" % len(shown))
            out += [cut(line, 200) for line in shown]
    return out[:max(max_lines, tail + 2)]


def closing(returncode: int, log: object) -> str:
    """The last line of every report: the exit status and the full log."""
    return "exit status %d; log %s" % (returncode, log)


def exit_status(returncode: int, text: str) -> int:
    """The status to exit with: the run's own, except 1 for a run that exited 0 and shows a failure in its output."""
    if returncode != 0:
        return returncode
    lines = text.splitlines()
    failures = zig_failures(lines) + terminal_failures(lines)
    return 1 if verdict(returncode, counts(text), failures) == "FAIL" else 0
