#!/usr/bin/env python3
"""Summarize the engine's `selka test` shadow log (docs/tooling/engine.md#the-shadow-in-selka-test).

Usage: python3 scripts/engine_shadow_summary.py LOG [--examples N] [--json] [--tag NAME]
       python3 scripts/engine_shadow_summary.py --self-test

LOG is the JSON-lines file `SELKA_ENGINE_SHADOW_LOG` names (default `<cache-dir>/engine-v1/shadow.jsonl`). Each
process of `selka test` appends its disagreements and, when it ends, one `summary` line with its counters. The report
has three parts: the totals (how many tests the shadow compared, how often the receipts and the engine would reuse), the
disagreements by class (`soundness`: the engine would reuse where the receipts rerun; `efficiency`: the engine would
rerun where the receipts reuse; `plan`: a served `test-plan` that is not what the front end produced; `verify`: verify mode found a served answer that
the same reads no longer give), each bucketed by
the receipts' reason and the engine's reason with the first examples, and the verdict-differs count, which is the
disagreements that would have served a wrong result.

An engine reason that names a file ("plan: tests/lang/a.selka changed") is bucketed as "plan: <file> changed", so one edit is
one bucket. Exit status: 1 when the log holds a `soundness` line whose fresh verdict differs from the recorded one, a
`plan` line or a `verify` line (verify mode recomputed a served query and got another result), else 0. A soundness line that does not differ is benign when the receipts' store lacks the receipt (the
engine's store was warmer); the report prints the buckets so a reader can tell.
"""
import collections
import json
import re
import sys

COUNTERS = ["observed", "unobserved", "old_reuse", "engine_reuse", "agree", "soundness", "verdict_differs", "efficiency", "plan", "verify", "dropped", "spent_us"]
CLASSES = ["soundness", "verify", "plan", "efficiency"]


def normalize(reason):
    """The engine's reason without the file or path it names, nor what the record saw and what is there now."""
    reason = re.sub(r" \(saw .*\)$", "", reason)
    if "environment" in reason and reason.endswith(" changed"):
        return re.sub(r"^(plan: )?.*$", r"\1keyed environment changed", reason)
    return re.sub(r"^(plan: )?(file|exists|listing|tool|query) .* changed$", r"\1<\2> changed", reason)


def read(path):
    lines, bad = [], 0
    with open(path, encoding="utf-8") as handle:
        for text in handle:
            text = text.strip()
            if not text:
                continue
            try:
                lines.append(json.loads(text))
            except ValueError:
                bad += 1
    return lines, bad


def summarize(lines, examples, tag=None):
    if tag is not None:
        lines = [line for line in lines if line.get("tag") == tag]
    totals = collections.Counter()
    processes = 0
    buckets = {name: collections.OrderedDict() for name in CLASSES}
    counted = collections.Counter()
    for line in lines:
        if line.get("class") == "summary":
            processes += 1
            for name in COUNTERS:
                totals[name] += int(line.get(name, 0))
            continue
        name = line.get("class")
        if name not in buckets:
            continue
        weight = int(line.get("tests") or 1)
        counted[name] += weight
        old = (line.get("old") or {}).get("reason", "")
        engine = normalize((line.get("engine") or {}).get("reason", line.get("detail", "")))
        bucket = buckets[name].setdefault((old, engine), {"count": 0, "examples": []})
        bucket["count"] += weight
        if len(bucket["examples"]) < examples:
            bucket["examples"].append(line)
    return {"processes": processes, "totals": dict(totals), "lines": dict(counted), "buckets": buckets}


def rate(part, whole):
    return "n/a" if not whole else "%.1f%%" % (100.0 * part / whole)


def render(report):
    totals = report["totals"]
    out = ["engine shadow: %d process summaries" % report["processes"]]
    out.append("  tests compared %d (unobserved %d); receipts reused %d (%s), engine would reuse %d (%s); agree %d (%s)" % (
        totals.get("observed", 0), totals.get("unobserved", 0), totals.get("old_reuse", 0),
        rate(totals.get("old_reuse", 0), totals.get("observed", 0)), totals.get("engine_reuse", 0),
        rate(totals.get("engine_reuse", 0), totals.get("observed", 0)), totals.get("agree", 0),
        rate(totals.get("agree", 0), totals.get("observed", 0))))
    out.append("  soundness %d (verdict differs %d), efficiency %d, plan %d, verify %d, dropped %d" % tuple(
        totals.get(name, 0) for name in ("soundness", "verdict_differs", "efficiency", "plan", "verify", "dropped")))
    out.append("  time spent observing %.2f s, summed over threads" % (totals.get("spent_us", 0) / 1e6))
    for name in CLASSES:
        found = report["buckets"][name]
        if not found:
            continue
        out.append("")
        out.append("%s (%d tests in %d buckets)" % (name, report["lines"].get(name, 0), len(found)))
        for (old, engine), bucket in sorted(found.items(), key=lambda item: -item[1]["count"]):
            out.append("  %6d  receipts: %-24s engine: %s" % (bucket["count"], old or "-", engine or "-"))
            for line in bucket["examples"]:
                where = line.get("test") or line.get("entry") or ""
                extra = " verdict differs" if line.get("verdict_differs") else ""
                out.append("          e.g. %s%s" % (where, extra))
    return "\n".join(out)


def failing(report):
    totals = report["totals"]
    return bool(totals.get("verdict_differs", 0) or totals.get("plan", 0) or totals.get("verify", 0) or
                report["lines"].get("plan", 0) or report["lines"].get("verify", 0))


def self_test():
    log = [
        {"v": 1, "class": "efficiency", "test": "a::t1", "entry": "a.selka", "old": {"decision": "reuse", "reason": "whole-receipt-hit"},
         "engine": {"decision": "rerun", "reason": "plan: file /x/a.selka changed (saw 1a2b, now 3c4d)"}},
        {"v": 1, "class": "efficiency", "entry": "b.selka", "tests": 4, "old": {"decision": "reuse", "reason": "whole-report-hit"},
         "engine": {"decision": "rerun", "reason": "plan: no record"}},
        {"v": 1, "class": "soundness", "test": "a::t2", "entry": "a.selka", "old": {"decision": "rerun", "reason": "no-success-receipt"},
         "engine": {"decision": "reuse", "reason": "record is valid"}, "verdict_differs": False},
        {"v": 1, "class": "summary", "pid": 1, "observed": 10, "old_reuse": 5, "engine_reuse": 4, "agree": 8, "soundness": 1,
         "verdict_differs": 0, "efficiency": 5, "plan": 0, "dropped": 0},
    ]
    report = summarize(log, 2)
    assert report["processes"] == 1 and report["lines"]["efficiency"] == 5 and report["lines"]["soundness"] == 1, report
    assert not failing(report)
    text = render(report)
    assert "(saw" not in text
    assert "plan: <file> changed" in text and "no-success-receipt" in text and "whole-report-hit" in text, text
    tagged = summarize([dict(line, tag="a") for line in log[:2]] + [dict(line, tag="b") for line in log[2:]], 2, "b")
    assert tagged["lines"].get("soundness") == 1 and tagged["lines"].get("efficiency") is None, tagged
    log[2]["verdict_differs"] = True
    log[3]["verdict_differs"] = 1
    assert failing(summarize(log, 2))
    print("engine_shadow_summary self-test passed")
    return 0


def main(argv):
    if argv == ["--self-test"]:
        return self_test()
    examples, as_json, path, at, tag = 3, False, None, 0, None
    while at < len(argv):
        word = argv[at]
        if word == "--examples" and at + 1 < len(argv) and argv[at + 1].isdigit():
            examples, at = int(argv[at + 1]), at + 1
        elif word == "--json":
            as_json = True
        elif word == "--tag" and at + 1 < len(argv):
            tag, at = argv[at + 1], at + 1
        elif not word.startswith("--") and path is None:
            path = word
        else:
            print(__doc__.split("\n\n")[0], file=sys.stderr)
            return 2
        at += 1
    if path is None:
        print("usage: engine_shadow_summary.py LOG [--examples N] [--json]", file=sys.stderr)
        return 2
    try:
        lines, bad = read(path)
    except OSError as err:
        print("engine_shadow_summary: %s" % err, file=sys.stderr)
        return 2
    report = summarize(lines, examples, tag)
    if as_json:
        report["buckets"] = {name: [{"old": key[0], "engine": key[1], **value} for key, value in found.items()] for name, found in report["buckets"].items()}
        print(json.dumps(report))
    else:
        print(render(report))
        if bad:
            print("(%d unreadable lines skipped)" % bad)
    return 1 if failing(summarize(lines, 0, tag)) else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
