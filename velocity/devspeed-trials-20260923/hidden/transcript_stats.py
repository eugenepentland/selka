#!/usr/bin/env python3
"""Summarise one trial agent transcript without printing its content.

usage: transcript_stats.py RUN_NAME TRANSCRIPT.jsonl  -> one JSON object on stdout
"""
import json
import re
import sys
from collections import Counter
from datetime import datetime

KIT = "/home/epentland/ai/trials/devspeed-20260923/kit"
RUNS = "/home/epentland/ai/trials/devspeed-20260923/runs"


def ts(s):
    return datetime.fromisoformat(s.replace("Z", "+00:00"))


def main():
    run, path = sys.argv[1], sys.argv[2]
    rows = [json.loads(line) for line in open(path)]
    times = [ts(r["timestamp"]) for r in rows if "timestamp" in r]
    usage = {}
    model = None
    tools = Counter()
    uses = {}
    for r in rows:
        if r.get("type") != "assistant":
            continue
        m = r["message"]
        model = m.get("model", model)
        usage[m["id"]] = m.get("usage") or {}
        for c in m.get("content", []):
            if c.get("type") == "tool_use":
                tools[c["name"]] += 1
                uses[c["id"]] = (c["name"], c.get("input", {}))
    results = {}
    for r in rows:
        if r.get("type") != "user":
            continue
        content = r["message"].get("content")
        if not isinstance(content, list):
            continue
        for c in content:
            if c.get("type") == "tool_result":
                body = c.get("content")
                if isinstance(body, list):
                    text = "".join(b.get("text", "") for b in body if isinstance(b, dict))
                else:
                    text = str(body or "")
                results[c["tool_use_id"]] = (len(text.encode()), bool(c.get("is_error")))
    ctx = sum((u.get("input_tokens", 0) + u.get("cache_creation_input_tokens", 0) + u.get("cache_read_input_tokens", 0)) for u in usage.values())
    out_tok = sum(u.get("output_tokens", 0) for u in usage.values())
    doc_files = Counter()
    doc_bytes = 0
    outside = []
    tool_calls = 0
    compile_calls = 0
    for uid, (name, inp) in uses.items():
        size = results.get(uid, (0, False))[0]
        blob = json.dumps(inp)
        touches_doc = KIT in blob
        if name == "Read":
            fp = inp.get("file_path", "")
            if fp.startswith(KIT):
                doc_files[fp[len(KIT) + 1:]] += 1
                doc_bytes += size
        elif touches_doc:
            doc_bytes += size
            for m in re.findall(re.escape(KIT) + r"/([\w./-]+\.md)", blob):
                doc_files[m] += 1
        if name == "Bash" and re.search(r"/bin/(mylang|go|python3)\b", inp.get("command", "")):
            compile_calls += 1
        for p in re.findall(r"/home/epentland/[\w./-]+", blob):
            if not (p.startswith(KIT) or p.startswith(f"{RUNS}/{run}")):
                outside.append(p)
        tool_calls += 1
    print(json.dumps({
        "run": run,
        "model": model,
        "wall_min": round((max(times) - min(times)).total_seconds() / 60, 1) if times else None,
        "api_calls": len(usage),
        "tool_calls": tool_calls,
        "tools": dict(tools),
        "tool_calls_invoking_toolchain": compile_calls,
        "context_tokens": ctx,
        "output_tokens": out_tok,
        "doc_bytes_read": doc_bytes,
        "doc_files_distinct": len(doc_files),
        "doc_files_top": doc_files.most_common(12),
        "outside_paths": sorted(set(outside))[:20],
    }))


if __name__ == "__main__":
    main()
