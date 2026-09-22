#!/usr/bin/env python3
"""Historical recount of the pre-M0 108-session study, with its limits stated.

The original study measured repair rounds by regex over whole transcripts, which
counted prose and repeated deliveries. The transcripts *are* structured, so this
recount matches tool calls to their results and deduplicates by call id — but it
does not invent the per-process events the old runner never recorded. Where the
transcript does not determine an invocation boundary or an outcome, the number is
reported as "tool results containing diagnostics" with the coverage gap named.

    python3 experiments/diagnostic-feedback/recount.py
"""

from __future__ import annotations

import json
from pathlib import Path
import re
import sys

HERE = Path(__file__).resolve().parent
RUNS = HERE / "runs"
sys.path.insert(0, str(HERE.parents[1] / "experiments" / "cascade"))
import run as runlib  # noqa: E402

CODE = re.compile(r"error\[(E_[A-Z_]+)\]|\"code\":\s*\"(E_[A-Z_]+)\"")
COMPILER_CALL = re.compile(r"\bmylang\b")


def pairs(text: str) -> tuple[list[str], int, int]:
    """Matched compiler calls, diagnostic-bearing results, and unmatched results."""
    calls: dict[str, str] = {}
    matched = 0
    with_diagnostics = 0
    unmatched = 0
    for line in text.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            record = json.loads(line)
        except json.JSONDecodeError:
            continue
        kind = record.get("type")
        data = record.get("data") or {}
        if kind == "tool/call":
            calls[data.get("callId", "")] = str(data.get("arguments") or "")
        elif kind == "tool/result":
            call = (data.get("message") or {}).get("source", {}).get("callId", "")
            if call not in calls:
                unmatched += 1
                continue
            if not COMPILER_CALL.search(calls[call]):
                continue
            matched += 1
            body = ""
            for block in (data.get("message") or {}).get("content") or []:
                if isinstance(block, dict) and block.get("type") == "tool-result":
                    for item in block.get("content") or []:
                        if isinstance(item, dict) and item.get("type") == "text":
                            body += item.get("text") or ""
            if CODE.search(body.replace('\\"', '"')):
                with_diagnostics += 1
    return list(calls), matched, with_diagnostics, unmatched


def main() -> int:
    rows = []
    for path in sorted(RUNS.glob("*/*/*/[0-9].json")):
        record = json.loads(path.read_text())
        work = Path(record["work_dir"])
        logs = list(runlib.session_log_text(work.resolve(),
                                            __import__("datetime").datetime.fromisoformat(
                                                record["session_launch"]["started_utc"])))
        text = "".join(logs)
        _, matched, with_diagnostics, unmatched = pairs(text) if text else ([], 0, 0, 0)
        rows.append({"condition": record["condition"], "case": record["fault"], "run": record["run"],
                     "matched_compiler_results": matched,
                     "results_with_diagnostics": with_diagnostics,
                     "unmatched_results": unmatched,
                     "transcript_available": bool(text),
                     "solved": record.get("solved"),
                     "recorded_repair_rounds": record.get("repair_rounds")})
    by_condition: dict[str, dict] = {}
    for row in rows:
        bucket = by_condition.setdefault(row["condition"], {"sessions": 0, "transcripts": 0,
                                                             "matched": 0, "with_diagnostics": 0, "solved": 0})
        bucket["sessions"] += 1
        bucket["transcripts"] += 1 if row["transcript_available"] else 0
        bucket["matched"] += row["matched_compiler_results"]
        bucket["with_diagnostics"] += row["results_with_diagnostics"]
        bucket["solved"] += 1 if row["solved"] else 0
    report = {
        "version": 1,
        "scope": "the pre-M0 study (96 sessions plus 12 re-runs of one corrected fault)",
        "method": ("matched tool-call/tool-result pairs whose command invoked the compiler, deduplicated by call id; "
                   "diagnostic-bearing results counted from the result body"),
        "limits": [
            "per-process invocation boundaries are not reconstructable where several compiler calls shared one shell command",
            "a result body containing diagnostics cannot be split into one event per diagnostic",
            "transcripts pruned by the operator are reported as unavailable rather than estimated",
            "the study used the defective unknown-name case in its first pass; those attempts remain in runs/ side by side with their re-runs",
        ],
        "by_condition": by_condition,
        "sessions": rows,
    }
    (HERE / "recount.json").write_text(json.dumps(report, indent=2) + "\n")
    print(f"{'condition':<11}{'sessions':>9}{'transcripts':>12}{'matched calls':>14}{'with diagnostics':>17}{'solved':>8}")
    for condition, bucket in sorted(by_condition.items()):
        print(f"{condition:<11}{bucket['sessions']:>9}{bucket['transcripts']:>12}{bucket['matched']:>14}"
              f"{bucket['with_diagnostics']:>17}{bucket['solved']:>8}")
    print(f"\nwrote {HERE / 'recount.json'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
