#!/usr/bin/env python3
"""Summarize the engine's `selka test` log (docs/tooling/engine.md#the-engine-in-selka-test).

Usage: python3 scripts/engine_log_summary.py LOG [--examples N] [--json] [--tag NAME]
       python3 scripts/engine_log_summary.py --self-test

LOG is the JSON-lines file `SELKA_ENGINE_SHADOW_LOG` names (default `<cache-dir>/engine-v1/shadow.jsonl`). Each process of
`selka test` appends one `verify` line for every finding (a served record that was checked by running the test, and the test
failed; or a query verify mode recomputed and got another result for) and, when it ends, one `summary` line with its counters.
The report prints the totals (tests the engine was asked about, how many it served and how many ran), then the findings with
the first examples. A log written before the receipts were removed (it has `old_reuse`, `soundness` and `efficiency`
counters) is read by `scripts/engine_shadow_summary.py`.

Exit status: 1 when the log holds a `verify` line or a nonzero `verdict_differs`, else 0.
"""
import collections
import json
import sys

COUNTERS = ["asked", "unobserved", "reused", "ran", "checked", "replayed", "verify", "verdict_differs", "local_only", "dropped", "spent_us"]


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
    findings = []
    for line in lines:
        if line.get("class") == "summary":
            processes += 1
            for name in COUNTERS:
                totals[name] += int(line.get(name, 0))
        elif line.get("class") == "verify":
            findings.append(line)
    return {"processes": processes, "totals": dict(totals), "findings": len(findings), "examples": findings[:examples]}


def rate(part, whole):
    return "n/a" if not whole else "%.1f%%" % (100.0 * part / whole)


def render(report):
    totals = report["totals"]
    asked = totals.get("asked", 0)
    out = ["engine log: %d process summaries" % report["processes"]]
    out.append("  tests asked about %d (not asked, by policy: %d); served %d (%s), ran %d, checked by running %d; replayed %d" % (
        asked, totals.get("unobserved", 0), totals.get("reused", 0), rate(totals.get("reused", 0), asked), totals.get("ran", 0),
        totals.get("checked", 0), totals.get("replayed", 0)))
    out.append("  verify findings %d (checked records whose test failed: %d); kept out of the shared tier %d; lines dropped %d" % (
        totals.get("verify", 0), totals.get("verdict_differs", 0), totals.get("local_only", 0), totals.get("dropped", 0)))
    out.append("  time spent observing %.2f s, summed over threads" % (totals.get("spent_us", 0) / 1e6))
    if report["findings"]:
        out.append("")
        out.append("verify (%d lines)" % report["findings"])
        for line in report["examples"]:
            out.append("  e.g. %s %s: %s" % (line.get("entry", ""), line.get("test", ""), line.get("detail", "")))
    return "\n".join(out)


def failing(report):
    totals = report["totals"]
    return bool(report["findings"] or totals.get("verify", 0) or totals.get("verdict_differs", 0))


def self_test():
    log = [
        {"v": 1, "class": "summary", "pid": 1, "asked": 10, "reused": 8, "ran": 2, "checked": 1, "replayed": 3, "verify": 0,
         "verdict_differs": 0, "local_only": 1, "dropped": 0, "spent_us": 2500000, "tag": "a"},
        {"v": 1, "class": "summary", "pid": 2, "asked": 4, "reused": 0, "ran": 4, "tag": "b"},
    ]
    report = summarize(log, 2)
    assert report["processes"] == 2 and report["totals"]["asked"] == 14 and not failing(report), report
    text = render(report)
    assert "served 8 (57.1%)" in text and "replayed 3" in text and "2.50 s" in text, text
    assert summarize(log, 2, "b")["totals"]["asked"] == 4
    log.append({"v": 1, "class": "verify", "test": "a::t", "entry": "a.selka", "detail": "the test failed"})
    log[0]["verdict_differs"] = 1
    report = summarize(log, 2)
    assert failing(report) and report["findings"] == 1 and "a::t" in render(report), render(report)
    print("engine_log_summary self-test passed")
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
        print("usage: engine_log_summary.py LOG [--examples N] [--json] [--tag NAME]", file=sys.stderr)
        return 2
    try:
        lines, bad = read(path)
    except OSError as err:
        print("engine_log_summary: %s" % err, file=sys.stderr)
        return 2
    report = summarize(lines, examples, tag)
    if as_json:
        print(json.dumps(report))
    else:
        print(render(report))
        if bad:
            print("(%d unreadable lines skipped)" % bad)
    return 1 if failing(report) else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
