#!/usr/bin/env python3
"""Aggregate edit_fuzz.py --json summaries into markdown tables.

    aggregate.py RESULT.json... > table.md
"""
import json
import re
import sys
from collections import Counter, defaultdict


def stats(values):
    if not values:
        return "-"
    s = sorted(values)
    return f"{sum(s) / len(s):.1f} / {s[len(s) // 2]} / {s[-1]}"


def main(paths):
    runs = []
    for path in paths:
        with open(path) as handle:
            runs.append(json.load(handle))
    print("## Runs\n")
    print("| project | runtime | seed | modules | steps | built | on module path | off path | matched | findings "
          "| compiled mean/median/max | wall s |")
    print("|---|---|---|---|---|---|---|---|---|---|---|---|")
    for r in runs:
        compiled = [x["compiled"] for x in r["rows"] if x["kind"] not in ("cold", "revert-check") and x.get("engaged")]
        print(f"| {r['project_kind']} | {'gc' if r['gc_runtime'] else 'rc'} | {r['seed']} | {r['modules']} | {r['steps']} "
              f"| {r['built']} | {r['engaged']} | {r['off_module_path']} | {r['matched']} | {len(r['findings'])} "
              f"| {stats(compiled)} | {r['wall_seconds']} |")
    total = sum(r["steps"] for r in runs)
    built = sum(r["built"] for r in runs)
    matched = sum(r["matched"] for r in runs)
    findings = sum(len(r["findings"]) for r in runs)
    print(f"\nTotal: {total} edit steps, {built} built ({100 * built / max(total, 1):.0f}%), {matched} matched the "
          f"oracle, {findings} findings, {sum(r['revert_checks'] for r in runs)} revert checks.\n")

    print("## Edit kinds\n")
    print("| kind | applied | built | failed | off module path | compiled mean/median/max |")
    print("|---|---|---|---|---|---|")
    kinds = defaultdict(lambda: {"applied": 0, "built": 0, "failed": 0, "off_module_path": 0, "compiled": []})
    for r in runs:
        for k, v in r["by_kind"].items():
            for field in ("applied", "built", "failed", "off_module_path"):
                kinds[k][field] += v[field]
            kinds[k]["compiled"] += v["compiled"]
    for k, v in sorted(kinds.items(), key=lambda kv: -kv[1]["applied"]):
        print(f"| {k} | {v['applied']} | {v['built']} | {v['failed']} | {v['off_module_path']} | {stats(v['compiled'])} |")

    print("\n## Compiled-module counts (engaged incremental builds)\n")
    hist = Counter()
    for r in runs:
        for x in r["rows"]:
            if x["kind"] not in ("cold", "revert-check") and x.get("engaged"):
                hist[x["compiled"]] += 1
    print("| compiled | builds |")
    print("|---|---|")
    for c, n in sorted(hist.items()):
        print(f"| {c} | {n} |")

    print("\n## Why edits failed to build\n")
    reasons = Counter()
    for r in runs:
        for x in r["rows"]:
            if x.get("verdict") == "both-failed":
                m = re.search(r"error\[(\w+)\]", x.get("error") or "")
                reasons[(x["kind"], m.group(1) if m else (x.get("error") or "?")[:60])] += 1
    print("| kind | diagnostic | count |")
    print("|---|---|---|")
    for (k, code), n in reasons.most_common():
        print(f"| {k} | {code} | {n} |")
    differ = sum(r["diagnostics_differ"] for r in runs)
    print(f"\nFailed steps where the two builds reported different error sets: {differ}.")

    off = [x for r in runs for x in r["rows"] if x.get("engaged") is False and x.get("built")]
    if off:
        print("\n## Edits that took the build off the module path (reverted)\n")
        for x in off:
            print(f"- seed {x['seed']} step {x['step']} `{x['kind']}` {x['desc']}: {x.get('off_module_path_because')}")

    if findings:
        print("\n## Findings\n")
        for r in runs:
            for f in r["findings"]:
                print(f"- {r['project_kind']} seed {r['seed']} step {f['step']} `{f['kind']}`: {f['verdict']} - {f.get('error', '')[:200]}")


if __name__ == "__main__":
    main(sys.argv[1:])
