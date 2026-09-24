#!/usr/bin/env python3
"""Print a probe.py JSONL log as a compact table.

usage: summarize.py LOG.jsonl [--phases] [--min]

--phases also prints each measurement's phase timings; --min prints, per label, the
minimum wall time, the peak RSS and the median of the phase timings of the fastest run.
"""
import json
import sys

KEEP = ("checked_bodies", "lowered_functions", "emitted_fragments")


def main():
    path = sys.argv[1]
    show_phases = "--phases" in sys.argv
    mins = "--min" in sys.argv
    rows = []
    for line in open(path):
        line = line.strip()
        if not line.startswith("{"):
            continue
        d = json.loads(line)
        if "label" in d and d["label"].endswith(":phases"):
            continue
        rows.append(d)
    if mins:
        best = {}
        for d in rows:
            if "label" not in d or d.get("rc") not in (0, None):
                continue
            b = best.get(d["label"])
            if b is None or d["wall_s"] < b["wall_s"]:
                best[d["label"]] = dict(d, peak=max(d.get("max_rss_kb") or 0, (b or {}).get("peak", 0)))
            else:
                b["peak"] = max(b["peak"], d.get("max_rss_kb") or 0)
        for k, d in best.items():
            print(f"{k:24s} {d['wall_s']:8.3f}s  rss {d['peak'] / 1024:7.0f} MB  cpu {((d.get('user_s') or 0) + (d.get('sys_s') or 0)):6.2f}s  load {d.get('load')}")
            if show_phases and d.get("phases"):
                print("      " + ", ".join(f"{p}={v:.3f}" for p, v in d["phases"].items() if v >= 0.002))
        return
    for d in rows:
        if "label" not in d:
            print(json.dumps(d)[:1500])
            continue
        work = {k: v for k, v in (d.get("work") or {}).items() if k in KEEP}
        print(f"{d['label']:24s} {d['wall_s']:8.3f}s rss {(d.get('max_rss_kb') or 0) / 1024:7.0f} MB rc {d.get('rc')} load {d.get('load')} "
              f"{json.dumps(d.get('counters', {}))} {json.dumps(work)}")
        if d.get("tools"):
            print("      tools " + json.dumps(d["tools"]))
        if show_phases and d.get("phases"):
            print("      " + ", ".join(f"{p}={v:.3f}" for p, v in d["phases"].items() if v >= 0.002))
        if d.get("tail"):
            print("      TAIL " + d["tail"][-600:].replace("\n", " | "))


if __name__ == "__main__":
    main()
