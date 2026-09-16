#!/usr/bin/env python3
"""Auxiliary retention-counter probe.

The existing S1 harness drives `mylang check-session` but records only a few
fields, discarding the `functions` statistics (retained_bytes, retention.*).
This probe reuses the same compiler protocol and the same harness-generated
project, sending `check` and printing the retention counters.  It does not
modify the compiler or the harness.
"""
import json, subprocess, sys, time

def probe(compiler, entry, checks=1, cwd=None):
    p = subprocess.Popen([compiler, "check-session", entry],
                         stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                         stderr=subprocess.DEVNULL, text=True, bufsize=1, cwd=cwd)
    out = []
    try:
        for i in range(checks):
            t0 = time.monotonic()
            p.stdin.write("check\n"); p.stdin.flush()
            line = p.stdout.readline()
            if not line:
                raise RuntimeError("check-session exited early")
            rec = json.loads(line)
            fn = rec.get("functions", {})
            ret = fn.get("retention", {})
            work = rec.get("work", {})
            out.append({
                "request": i,
                "wall_ms": (time.monotonic()-t0)*1000.0,
                "status": rec.get("status"),
                "reused_results": work.get("reused"),
                "checked": fn.get("checked"),
                "reused": fn.get("reused"),
                "stored": fn.get("stored"),
                "bypassed": fn.get("bypassed"),
                "retained_bytes": fn.get("retained_bytes"),
                "retention": ret,
                "specializations_checked": (work.get("request") or {}).get("checked_bodies"),
                "work_request": work.get("request"),
            })
        p.stdin.write("quit\n"); p.stdin.flush()
    finally:
        try:
            p.wait(timeout=15)
        except Exception:
            p.kill()
    return out

if __name__ == "__main__":
    compiler, entry = sys.argv[1], sys.argv[2]
    checks = int(sys.argv[3]) if len(sys.argv) > 3 else 1
    res = probe(compiler, entry, checks)
    print(json.dumps({"compiler": compiler, "entry": entry, "results": res}, indent=2))
