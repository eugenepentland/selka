#!/usr/bin/env python3
"""Aggregate trial evidence: grades + transcript stats + toolchain shim logs -> evidence JSON + table."""
import json
import re
import subprocess
import sys
from collections import Counter
from pathlib import Path

SP = Path("/tmp/claude-1000/-home-epentland-ai-canopy-mylang/481b72b0-e2f9-4f0f-bcf8-35b9cdd4c0b4/scratchpad")
SUB = Path("/home/epentland/.claude/projects/-home-epentland-ai-canopy-mylang/481b72b0-e2f9-4f0f-bcf8-35b9cdd4c0b4/subagents")
AGENTS = json.loads((SP / "hidden" / "agents.json").read_text())


def shim_summary(run):
    p = SP / "logs" / f"{run}.final.jsonl"
    if not p.exists():
        return None
    rows = [json.loads(line) for line in p.open()]
    fails = [r for r in rows if r["exit"] != 0]
    codes = Counter()
    for r in fails:
        for c in set(re.findall(r"\b([ER]_[A-Z_]+)\b", r["stderr"] + r["stdout"])):
            codes[c] += 1
    sub = Counter(r["argv"][0] if r["argv"] else "" for r in rows)
    return {
        "calls": len(rows),
        "nonzero": len(fails),
        "toolchain_s": round(sum(r["dur"] for r in rows), 1),
        "subcommands": dict(sub.most_common()),
        "error_codes": dict(codes.most_common()),
    }


def main():
    out = {}
    for run, agent in AGENTS.items():
        rec = {"run": run}
        g = SP / "grades" / f"{run}.json"
        if g.exists():
            gr = json.loads(g.read_text())
            rec["passed"] = gr.get("passed")
            rec["total"] = gr.get("total")
            rec["build_exit"] = gr.get("build_exit")
            rec["failed_cases"] = {k: v["problems"] for k, v in gr.get("cases", {}).items() if not v["ok"]}
            rec["large_case_s"] = {k: v.get("s") for k, v in gr.get("cases", {}).items() if "large" in k or "many" in k}
        t = SUB / f"agent-{agent}.jsonl"
        if t.exists():
            st = json.loads(subprocess.run([sys.executable, str(SP / "hidden" / "transcript_stats.py"), run, str(t)], capture_output=True, text=True).stdout)
            rec.update({k: st[k] for k in ["wall_min", "api_calls", "tool_calls", "tools", "context_tokens", "output_tokens", "doc_bytes_read", "doc_files_distinct", "doc_files_top", "outside_paths"]})
        rec["shim"] = shim_summary(run)
        out[run] = rec
    (SP / "evidence.json").write_text(json.dumps(out, indent=1))
    print(f"{'run':12} {'pass':>7} {'min':>5} {'tools':>5} {'ctxK':>6} {'outK':>5} {'docKB':>6} {'calls':>5} {'fail':>4} {'tc_s':>6}")
    for run, r in out.items():
        s = r.get("shim") or {}
        print(f"{run:12} {str(r.get('passed'))+'/'+str(r.get('total')):>7} {r.get('wall_min', ''):>5} {r.get('tool_calls', ''):>5} "
              f"{(r.get('context_tokens') or 0)//1000:>6} {(r.get('output_tokens') or 0)//1000:>5} {(r.get('doc_bytes_read') or 0)//1024:>6} "
              f"{s.get('calls', ''):>5} {s.get('nonzero', ''):>4} {s.get('toolchain_s', ''):>6}")


if __name__ == "__main__":
    main()
