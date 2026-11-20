#!/usr/bin/env python3
"""Generate tools/selka/shadow_summary_fixtures.selka from the Python original.

The Selka port must print exactly what scripts/engine_shadow_summary.py prints. This script builds a fixture log, runs the
Python functions on it and writes both the log lines and every expected output as Selka string literals, so the Selka
tests compare against what Python produced. Run it again after changing the fixture; the output is committed.

Usage: python3 tools/selka/gen_shadow_summary_fixtures.py > tools/selka/shadow_summary_fixtures.selka
       selka fmt tools/selka/shadow_summary_fixtures.selka --write
"""
import importlib.util
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("engine_shadow_summary", os.path.join(HERE, "..", "..", "scripts", "engine_shadow_summary.py"))
original = importlib.util.module_from_spec(spec)
spec.loader.exec_module(original)


def literal(text):
    """A Selka string literal for `text` (UTF-8 kept as is; quote, backslash and control characters escaped)."""
    out = ['"']
    for ch in text:
        if ch == '"':
            out.append('\\"')
        elif ch == "\\":
            out.append("\\\\")
        elif ch == "\n":
            out.append("\\n")
        elif ch == "\t":
            out.append("\\t")
        elif ch == "\r":
            out.append("\\r")
        elif ord(ch) < 32 or ord(ch) == 127:
            out.append("\\x%02x" % ord(ch))
        else:
            out.append(ch)
    out.append('"')
    return "".join(out)


def compact(value):
    return json.dumps(value, separators=(",", ":"), ensure_ascii=False)


# The fixture log: every class, ties, weights, an empty reason, a detail fallback, non-ASCII and escaped text, a float,
# a bad line, a blank line and an unknown class. Buckets tie at the same count so the stable sort is exercised.
LOG = [
    {"v": 1, "class": "efficiency", "test": "a::t1", "entry": "a.selka", "old": {"decision": "reuse", "reason": "whole-receipt-hit"},
     "engine": {"decision": "rerun", "reason": "plan: file /x/a.selka changed"}},
    {"v": 1, "class": "efficiency", "test": "a::t2", "entry": "a.selka", "old": {"decision": "reuse", "reason": "whole-receipt-hit"},
     "engine": {"decision": "rerun", "reason": "plan: file /x/b.selka changed"}},
    {"v": 1, "class": "efficiency", "entry": "b.selka", "tests": 4, "old": {"decision": "reuse", "reason": "whole-report-hit"},
     "engine": {"decision": "rerun", "reason": "plan: no record"}},
    {"v": 1, "class": "efficiency", "entry": "c.selka", "tests": 0, "old": {"decision": "reuse", "reason": "a-reason-longer-than-twenty-four-characters"},
     "engine": {"decision": "rerun", "reason": "listing /x/tests changed"}},
    {"v": 1, "class": "soundness", "test": "a::t3", "entry": "a.selka", "old": {"decision": "rerun", "reason": "no-success-receipt"},
     "engine": {"decision": "reuse", "reason": "record is valid"}, "verdict_differs": False},
    {"v": 1, "class": "soundness", "test": "d::tést_ünï", "entry": "d.selka", "old": {"decision": "rerun", "reason": "no-success-receipt"},
     "engine": {"decision": "reuse", "reason": "record is valid"}, "verdict_differs": True, "note": "quote \" backslash \\ tab \t nl \n bell \u0007   \U0001F600", "ratio": 0.5, "big": 1e22, "small": 1e-05, "list": [1, 2.5, None, True, {"k": []}]},
    {"v": 1, "class": "soundness", "test": "e::t", "old": {"decision": "rerun", "reason": "no-success-receipt"},
     "engine": {"decision": "reuse", "reason": "record is valid"}, "verdict_differs": False},
    {"v": 1, "class": "soundness", "test": "f::t", "old": {"decision": "rerun", "reason": "stale"},
     "engine": {"decision": "reuse", "reason": "SELKA_X environment changed"}, "verdict_differs": False},
    {"v": 1, "class": "soundness", "test": "f::u", "old": {"decision": "rerun", "reason": "stale"},
     "engine": {"decision": "reuse", "reason": "plan: PATH environment changed"}, "verdict_differs": False},
    {"v": 1, "class": "plan", "entry": "g.selka", "old": {}, "detail": "plan: served a test-plan the front end did not produce", "tests": 2},
    {"v": 1, "class": "verify", "test": "h::t", "old": {"reason": "whole-receipt-hit"}, "engine": {"reason": "tool /usr/bin/zig changed"}},
    {"v": 1, "class": "verify", "test": "h::u", "old": {"reason": "whole-receipt-hit"}, "engine": {"reason": "exists /x changed"}},
    {"v": 1, "class": "verify", "test": "h::v", "old": {"reason": "whole-receipt-hit"}, "engine": {"reason": "query abc changed"}},
    {"v": 1, "class": "verify", "test": "h::w", "old": {"reason": "whole-receipt-hit"}, "engine": {"reason": "file  changed"}},
    {"v": 1, "class": "verify", "test": "h::x", "old": {"reason": "whole-receipt-hit"}, "engine": {"reason": "file changed"}},
    {"v": 1, "class": "mystery", "test": "ignored"},
    {"v": 1, "class": "summary", "pid": 1, "observed": 10, "unobserved": 2, "old_reuse": 5, "engine_reuse": 4, "agree": 8, "soundness": 5,
     "verdict_differs": 1, "efficiency": 6, "plan": 2, "verify": 5, "dropped": 0, "spent_us": 1234567},
    {"v": 1, "class": "summary", "pid": 2, "observed": 1, "old_reuse": 0, "engine_reuse": 0, "agree": 1, "spent_us": 5000},
]


def raw_lines(log):
    lines = [compact(entry) for entry in log]
    lines.insert(3, "")
    lines.insert(7, "{not json")
    lines.insert(9, "   ")
    return lines


def summarize_text(lines, examples):
    text = "\n".join(lines) + "\n"
    path = os.path.join(HERE, ".fixture.tmp")
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(text)
    try:
        parsed, bad = original.read(path)
    finally:
        os.remove(path)
    report = original.summarize(parsed, examples)
    return report, bad


def json_report(report):
    report = dict(report)
    report["buckets"] = {name: [{"old": key[0], "engine": key[1], **value} for key, value in found.items()] for name, found in report["buckets"].items()}
    return json.dumps(report)


def main():
    lines = raw_lines(LOG)
    out = ["# Generated by gen_shadow_summary_fixtures.py from scripts/engine_shadow_summary.py; do not edit by hand.\n"]
    out.append("# The fixture log, one raw line per item (blank, indented-blank and malformed lines included).\n")
    out.append("public func log_lines() -> str[]:\n    return [\n")
    for line in lines:
        out.append("        %s,\n" % literal(line))
    out.append("    ]\n\n")
    out.append("# How many lines of the fixture are not JSON.\npublic func bad_lines() -> int:\n    return %d\n\n" % summarize_text(lines, 3)[1])
    out.append("# How many lines of the fixture parse as JSON.\npublic func parsed_lines() -> int:\n    return %d\n\n" % len(LOG))
    for examples in (3, 0, 1):
        report, bad = summarize_text(lines, examples)
        out.append("# What `render` prints for the fixture with %d examples per bucket.\npublic func expected_text_%d() -> str:\n    return %s\n\n" % (examples, examples, literal(original.render(report))))
        out.append("# What `--json` prints for the fixture with %d examples per bucket.\npublic func expected_json_%d() -> str:\n    return %s\n\n" % (examples, examples, literal(json_report(report))))
    empty, _ = summarize_text([], 3)
    out.append("# The report of an empty log.\npublic func expected_empty_text() -> str:\n    return %s\n\n" % literal(original.render(empty)))
    out.append("public func expected_empty_json() -> str:\n    return %s\n\n" % literal(json_report(empty)))
    report, _ = summarize_text(lines, 3)
    out.append("# The Python verdict on the fixture: 1 when a verdict differs, a plan or a verify line exists.\npublic func expected_failing() -> bool:\n    return %s\n\n" % ("True" if original.failing(report) else "False"))
    # normalize table
    cases = ["plan: file /x/a.selka changed", "file x changed", "file  changed", "file changed", "plan: tool /usr/bin/zig changed", "listing d changed",
             "SELKA_X environment changed", "plan: environment changed", "plan: PATH environment changed", "environment unchanged", "exists p changed",
             "query q changed", "other changed", "", "plan: ", "plan: plan: file x changed", "file a changed b changed", "filex changed", "plan: no record",
             "env environment mid changed", "plan: file x changed trailing"]
    out.append("# `normalize` on %d reasons: each is followed by what Python returned.\npublic func normalize_cases() -> str[]:\n    return [\n" % len(cases))
    for case in cases:
        out.append("        %s,\n        %s,\n" % (literal(case), literal(original.normalize(case))))
    out.append("    ]\n\n")
    rates = [(0, 0), (0, 5), (1, 3), (2, 3), (5, 10), (1, 8), (1, 16), (3, 16), (7, 7), (1, 1000), (999, 1000), (12345, 54321), (1, 7), (5, 8), (1, 40)]
    out.append("# `rate` on (part, whole) pairs: part, whole, then what Python returned.\npublic func rate_cases() -> str[]:\n    return [\n")
    for part, whole in rates:
        out.append("        %s,\n        %s,\n        %s,\n" % (literal(str(part)), literal(str(whole)), literal(original.rate(part, whole))))
    out.append("    ]\n\n")
    documents = ['"é"', '"\\ud83d\\ude00"', '"\\u2028\\u007f\\u0000\\u001f"', '[1,2.5,null,true,false,{},[]]', '{"a":{"b":[1,{"c":"x"}]},"d":""}', '1e22', '1e-05', '1e-5', '0.1',
                 '123456789.123', '1e16', '1e15', '-0', '-0.0', '100.0', '1.5e300', '5e-324', '2.5e-7', '"a\\/b"', '"\\b\\f\\n\\r\\t\\"\\\\"', '12345678901234567.0',
                 '0.0001', '0.00001', '-1.5e-10', '[ 1 , 2 ]', '{"k":-12,"j":0}', '9007199254740993', '-9223372036854775808', '123456789012345678.0', '1E5', '2.0e0']
    out.append("# `dumps` on JSON documents: each is followed by what Python's json.dumps(json.loads(...)) returned.\npublic func dumps_cases() -> str[]:\n    return [\n")
    for document in documents:
        out.append("        %s,\n        %s,\n" % (literal(document), literal(json.dumps(json.loads(document)))))
    out.append("    ]\n")
    sys.stdout.write("".join(out))


if __name__ == "__main__":
    main()
