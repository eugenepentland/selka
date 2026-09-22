#!/usr/bin/env python3
"""The ten M3 cases: the seeded regression, the brief and the hidden contract.

A case is authored coordinator material. The mutation is applied to the frozen
application snapshot when a workspace is built, so the participant receives a
seeded *behavioral* regression — never a broken header, a wrong command or a
misleading document. The hidden checks demand the same contract as the public
ones on different inputs, and they live only here: no participant-readable file
names a mutation, an expected hidden value or a solution.

The sexpr-port cases are `authored`: mutation, reference, wrong repairs and
hidden checks are all preflighted against the frozen snapshot. The planner cases
are `declared`: the runbook's task specifications written before the readiness
check, which cannot be preflighted while the frozen planner snapshot does not
compile with the current toolchain. Their mutations are deliberately *not*
invented against dead source; `preflight` records the blocker instead.
"""

from __future__ import annotations

from pathlib import Path

HERE = Path(__file__).resolve().parent
M3 = HERE.parent
CASES_ROOT = M3 / "pack" / "cases"

SEXPR_RUN = ["bin/mylang", "run", "main.my", "--", "fixtures/hidden/{fixture}"]
SEXPR_RENDER = ["bin/mylang", "run", "main.my", "--", "fixtures/hidden/{fixture}", "--render"]


def run(fixture: str, step_id: str) -> dict:
    return {"id": step_id, "kind": "test", "timeout": 300,
            "commands": [[part.format(fixture=fixture) for part in SEXPR_RUN]]}


def render(fixture: str, step_id: str) -> dict:
    return {"id": step_id, "kind": "test", "timeout": 300,
            "commands": [[part.format(fixture=fixture) for part in SEXPR_RENDER]]}


def rejects(fixture: str, step_id: str) -> dict:
    """A malformed input must be rejected with a located lexical error."""
    return {"id": step_id, "kind": "test", "timeout": 300, "expect_exit": 1,
            "expect_stderr_contains": "unterminated string",
            "commands": [[part.format(fixture=fixture) for part in SEXPR_RUN]]}


PERCENT_FAULT = """    # Percent literal: only when the sign ends the token, so a standalone `%`
    # still lexes as an operator atom.
    if peek(src, length, pos) == 37 and not is_atom_continue(peek(src, length, pos + 1)):
        pos = pos + 1
        col = col + 1
        store_cursor(lx, pos, line, col)
        return raw(Kind.si_val, offset, pos, start, pos, start_line, start_col)
    if is_atom_continue(peek(src, length, pos)):"""

PERCENT_LENIENT = """    if is_atom_continue(peek(src, length, pos)):"""

UNTERMINATED_FAULT = """    if not closed:
        store_cursor(lx, pos, line, col)
        return Err(LexError(message="unterminated string", offset=offset, line=start_line))"""

UNTERMINATED_LENIENT = """    if not closed:
        store_cursor(lx, pos, line, col)
        return Ok(raw(Kind.string, offset, pos, start, pos, start_line, start_col))"""

UNTERMINATED_WRONG = """    if not closed:
        store_cursor(lx, pos, line, col)
        return Err(LexError(message="unexpected end of input", offset=pos, line=line))"""

ESCAPE_FAULT = """        escaped = False
        back = pos - 1
        while back >= start and src[back] == 92:
            escaped = not escaped
            back = back - 1
        if escaped:"""

ESCAPE_LAST_BYTE = """        escaped = pos > start and src[pos - 1] == 92
        if escaped:"""

MIL_FAULT = """def mil_to_mm() -> float:
    return 0.0254"""

MIL_WRONG_FAULT = """def mil_to_mm() -> float:
    return 0.00254"""

MIL_WRONG_REPAIR = """def mil_to_mm() -> float:
    return 1.0 / 39.3701"""

EMPTY_FAULT = """            if len(entries) == 0:
                byte_builder.append(out, b"()")
                return"""

EMPTY_VANISHES = """            if len(entries) == 0:
                return"""

CASES: dict[str, dict] = {
    "sexpr-percent": {
        "id": "sexpr-percent",
        "split": "pilot",
        "application": "sexpr-port",
        "working_directory": "app",
        "status": "authored",
        "requested_behavior": "percent-terminated literals parse as one scaled literal with the "
                              "value the source spells; a standalone `%` stays an operator atom",
        "mutation": {"file": "sexpr/tokenizer.my", "find": PERCENT_FAULT, "replace": PERCENT_LENIENT},
        "wrong_repairs": [
            {"name": "percent-scaled-by-one-hundredth",
             "note": "restores the token kind but treats `%` as a /100 scale, so the value is wrong",
             "edits": [
                 {"file": "sexpr/tokenizer.my", "find": PERCENT_LENIENT, "replace": PERCENT_FAULT},
                 {"file": "sexpr/parser.my",
                  "find": """def si_scale(letter: str) -> float:
    if letter == "k":""",
                  "replace": """def si_scale(letter: str) -> float:
    if letter == "%":
        return 0.01
    if letter == "k":"""},
             ]},
        ],
        "hidden": {"checks": [
            run("percent.sexp", "hidden-percent-values"),
            render("percent.sexp", "hidden-percent-render"),
            run("percent-standalone.sexp", "hidden-standalone-percent"),
        ]},
    },
    "sexpr-invalid-input": {
        "id": "sexpr-invalid-input",
        "split": "pilot",
        "application": "sexpr-port",
        "working_directory": "app/tests",
        "status": "authored",
        "requested_behavior": "an unterminated quoted string is rejected with a located lexical error",
        "mutation": {"file": "sexpr/tokenizer.my", "find": UNTERMINATED_FAULT,
                     "replace": UNTERMINATED_LENIENT},
        "wrong_repairs": [
            {"name": "rejected-with-the-wrong-diagnostic",
             "note": "restores rejection but reports an unnamed end-of-input error at the wrong location",
             "edits": [{"file": "sexpr/tokenizer.my", "find": UNTERMINATED_LENIENT,
                        "replace": UNTERMINATED_WRONG}]},
        ],
        "hidden": {"checks": [
            rejects("unterminated-simple.sexp", "hidden-unterminated-simple"),
            rejects("unterminated-escape.sexp", "hidden-unterminated-escape"),
            rejects("unterminated-multiline.sexp", "hidden-unterminated-multiline"),
        ]},
    },
    "sexpr-units": {
        "id": "sexpr-units",
        "split": "main",
        "application": "sexpr-port",
        "working_directory": "app/sexpr",
        "status": "authored",
        "requested_behavior": "mil dimensions convert to millimetres with the exact contractual "
                              "factor across small, large and fractional magnitudes",
        "mutation": {"file": "sexpr/parser.my", "find": MIL_FAULT, "replace": MIL_WRONG_FAULT},
        "wrong_repairs": [
            {"name": "approximate-inch-division",
             "note": "replaces the factor with an inch approximation that is close but not exact",
             "edits": [{"file": "sexpr/parser.my", "find": MIL_WRONG_FAULT,
                        "replace": MIL_WRONG_REPAIR}]},
        ],
        "hidden": {"checks": [
            run("units-small.sexp", "hidden-units-small"),
            run("units-large.sexp", "hidden-units-large"),
            render("units-mixed.sexp", "hidden-units-mixed"),
        ]},
    },
    "sexpr-escaping": {
        "id": "sexpr-escaping",
        "split": "main",
        "application": "sexpr-port",
        "working_directory": "app/tests",
        "status": "authored",
        "requested_behavior": "a quote closes a string unless an odd number of consecutive "
                              "backslashes precedes it",
        "mutation": {"file": "sexpr/tokenizer.my", "find": ESCAPE_FAULT, "replace": ESCAPE_LAST_BYTE},
        "wrong_repairs": [
            {"name": "inverted-backslash-parity",
             "note": "counts the run but treats an even run as escaping and an odd run as closing",
             "edits": [{"file": "sexpr/tokenizer.my", "find": ESCAPE_LAST_BYTE,
                        "replace": ESCAPE_LAST_BYTE.replace("if escaped:", "if not escaped:")}]},
        ],
        "hidden": {"checks": [
            render("escapes-even.sexp", "hidden-escapes-even"),
            render("escapes-odd.sexp", "hidden-escapes-odd"),
            render("escapes-runs.sexp", "hidden-escapes-runs"),
            render("escapes-newline.sexp", "hidden-escapes-newline"),
        ]},
    },
    "sexpr-nesting": {
        "id": "sexpr-nesting",
        "split": "main",
        "application": "sexpr-port",
        "working_directory": ".",
        "status": "authored",
        "requested_behavior": "an empty form renders as `()` at the top level, as a child and at "
                              "any nesting depth",
        "mutation": {"file": "sexpr/printer.my", "find": EMPTY_FAULT, "replace": EMPTY_VANISHES},
        "wrong_repairs": [
            {"name": "top-level-empty-forms-only",
             "note": "restores `()` only when the empty form is not indented, so nested empties vanish",
             "edits": [{"file": "sexpr/printer.my", "find": EMPTY_VANISHES,
                        "replace": """            if len(entries) == 0:
                if indent == 0:
                    byte_builder.append(out, b"()")
                return"""}]},
        ],
        "hidden": {"checks": [
            render("nesting-top.sexp", "hidden-nesting-top"),
            render("nesting-child.sexp", "hidden-nesting-child"),
            render("nesting-deep.sexp", "hidden-nesting-deep"),
        ]},
    },
}

# The planner half of the runbook's task pack. These are specifications, not
# runnable seeds: the frozen planner snapshot is written in the pre-migration
# surface (`=>` match arms, `export`, `&[]i64`, heap/allocator entry points) and
# does not compile with the current toolchain. Porting it to populate the
# experiment is explicitly out of scope, so the pack records what each case
# would require and preflight reports the readiness blocker.
PLANNER_BLOCKER = ("the frozen planner snapshot does not compile with the frozen toolchain: "
                   "`E_REMOVED_SPELLING` for `=>` and `&`, and `E_EXPORT_REMOVED` for plain "
                   "`export`; it predates the Wave 1 surface migration of 2026-09-14")

PLANNER_CASES = {
    "planner-empty": {
        "id": "planner-empty", "split": "pilot", "application": "planner",
        "working_directory": ".", "status": "declared", "mutation": None,
        "requested_behavior": "an empty job list returns the documented empty plan "
                              "(`order`/`layers`/`timings` empty, `makespan` 0)",
        "intended_fault": "the empty-job-list path returns a non-contractual result",
        "intended_oracle": "stdin `{\"cases\":[{\"version\":1,\"jobs\":[]}]}` through the frozen "
                           "byte-I/O host returns the empty plan; non-empty and invalid requests "
                           "are unchanged",
        "blocked_on": PLANNER_BLOCKER,
        "hidden": {"checks": []},
    },
    "planner-zero-duration": {
        "id": "planner-zero-duration", "split": "pilot", "application": "planner",
        "working_directory": "..", "status": "declared", "mutation": None,
        "requested_behavior": "a zero-duration job has finish == start and its successors begin at "
                              "that instant",
        "intended_fault": "timing arithmetic adds a nonzero span to zero-duration jobs",
        "intended_oracle": "chains of zero-duration jobs report coincident start/finish values and "
                           "makespan 0; positive durations keep their current timings",
        "blocked_on": PLANNER_BLOCKER,
        "hidden": {"checks": []},
    },
    "planner-chain": {
        "id": "planner-chain", "split": "main", "application": "planner",
        "working_directory": "app", "status": "declared", "mutation": None,
        "requested_behavior": "each job starts at the latest finish among its dependencies and "
                              "finishes at start + duration along chains of any length",
        "intended_fault": "successor start times do not accumulate the whole chain",
        "intended_oracle": "deep chains report make spans that accumulate every link; independent "
                           "jobs and layers are unchanged",
        "blocked_on": PLANNER_BLOCKER,
        "hidden": {"checks": []},
    },
    "planner-ties": {
        "id": "planner-ties", "split": "main", "application": "planner",
        "working_directory": "..", "status": "declared", "mutation": None,
        "requested_behavior": "`order` picks the ASCII-smallest currently ready job and `layers` "
                              "rounds list ready jobs sorted by ID, independent of input order",
        "intended_fault": "ready jobs are emitted in declaration order rather than ASCII order",
        "intended_oracle": "the same job graph declared in several orders yields one plan, and the "
                           "plan is the contractual ASCII-ordered one",
        "blocked_on": PLANNER_BLOCKER,
        "hidden": {"checks": []},
    },
    "planner-boundary": {
        "id": "planner-boundary", "split": "main", "application": "planner",
        "working_directory": "app", "status": "declared", "mutation": None,
        "requested_behavior": "exactly 64 manifests and exactly 128 jobs are accepted; one more of "
                              "either is a whole-request `invalid-request`",
        "intended_fault": "the documented count boundary is off by one",
        "intended_oracle": "boundary-sized requests are accepted and one-past-boundary requests are "
                           "rejected with no partial results",
        "blocked_on": PLANNER_BLOCKER,
        "hidden": {"checks": []},
    },
}

CASES.update(PLANNER_CASES)

SPLITS = {"pilot": ["sexpr-percent", "sexpr-invalid-input", "planner-empty", "planner-zero-duration"],
          "main": ["sexpr-units", "sexpr-escaping", "sexpr-nesting",
                   "planner-chain", "planner-ties", "planner-boundary"]}


def load(case_id: str) -> dict:
    if case_id not in CASES:
        raise SystemExit(f"unknown case {case_id!r}")
    case = dict(CASES[case_id])
    case["request_path"] = str(CASES_ROOT / case_id / "request.md")
    return case


def split_cases(split: str) -> list[dict]:
    return [load(case_id) for case_id in SPLITS[split]]


def request_text(case: dict, arm: str, deadline_seconds: int) -> str:
    """The brief both arms receive, with only the arm's command syntax differing."""
    text = Path(case["request_path"]).read_text()
    if arm == "manual":
        command = ("```sh\n"
                   "# from this working copy, naming the active project's entry and manifest:\n"
                   "bin/project verify --entry <entry path> --manifest <manifest path>\n\n"
                   "# for example, from the working-copy root:\n"
                   "bin/project verify --entry app/main.my --manifest app/verify.json\n"
                   "```")
    else:
        command = ("```sh\n"
                   "# from anywhere in this working copy:\n"
                   "bin/project verify\n\n"
                   "# explicit paths are also accepted, exactly as the manual form uses them:\n"
                   "bin/project verify --entry app/main.my --manifest app/verify.json\n"
                   "```")
    return (text.replace("{{COMMAND}}", command)
                .replace("{{DEADLINE}}", str(deadline_seconds)))
