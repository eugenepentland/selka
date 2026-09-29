#!/usr/bin/env python3
"""Large-codebase tooling probe for mylang: latency, output size, and behaviour while red.

usage: tooling_probe.py TIER_DIR   (uses TIER_DIR/mylang, copies it to TIER_DIR/tooling)
"""
import json
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

M = "/home/epentland/ai/canopy/mylang-worktrees/devspeed-audit-20260923/.install/bin/mylang"
ENV = dict(os.environ, TMPDIR="/home/epentland/.cache/mylang-tmp")
CPUS = os.environ.get("SCALE_CPUS", "0-11")


def run(argv, cwd, stdin=None):
    t = time.perf_counter()
    p = subprocess.run(["taskset", "-c", CPUS] + argv, cwd=cwd, env=ENV, capture_output=True, text=True, input=stdin)
    return {"s": round(time.perf_counter() - t, 3), "exit": p.returncode, "stdout_bytes": len(p.stdout),
            "stderr_head": p.stderr[:300], "stdout_head": p.stdout[:200]}


def git(cwd, *args):
    subprocess.run(["git", *args], cwd=cwd, check=True, capture_output=True)


def edit_body(path, token):
    s = path.read_text()
    s2, n = re.subn(r"(\+ ?)(\d+)(\)[^\n]*EDIT_BODY)", lambda m: f"{m.group(1)}{token}{m.group(3)}", s, count=1)
    assert n == 1
    path.write_text(s2)


def main():
    tier = Path(sys.argv[1]).resolve()
    work = tier / "tooling"
    shutil.rmtree(work, ignore_errors=True)
    shutil.copytree(tier / "mylang", work)
    M_count = len(list(work.glob("m*.my")))
    mid = M_count // 2
    target = work / f"m{mid:03d}.my"
    symbol = f"m{mid:03d}::f{mid:03d}_00"
    git(work, "init", "-q")
    git(work, "add", ".")
    git(work, "-c", "user.email=probe@example.invalid", "-c", "user.name=probe", "commit", "-q", "-m", "base")
    r = {"tier": tier.name, "modules": M_count, "symbol": symbol}
    run([M, "check", "main.my"], work)  # warm
    r["check_warm"] = run([M, "check", "main.my"], work)
    r["index_project"] = run([M, "index-project", "main.my"], work)
    r["list_interfaces"] = run([M, "list-interfaces", "main.my"], work)
    r["context_symbol"] = run([M, "context", "main.my", f"--symbol={symbol}"], work)
    r["context_dotted"] = run([M, "context", "main.my", f"--symbol=m{mid:03d}.f{mid:03d}_00"], work)
    r["tests_for"] = run([M, "tests-for", "main.my", symbol], work)
    r["test_full_cold"] = run([M, "test", "main.my", "--cache-dir", str(tier / "tooling-cache")], work)
    r["test_full_warm"] = run([M, "test", "main.my", "--cache-dir", str(tier / "tooling-cache")], work)
    edit_body(target, 4242)
    r["check_after_edit"] = run([M, "check", "main.my"], work)
    r["test_affected_after_edit"] = run([M, "test", "main.my", "--affected", "--against", "HEAD", "--cache-dir", str(tier / "tooling-cache")], work)
    r["test_full_after_edit"] = run([M, "test", "main.my", "--cache-dir", str(tier / "tooling-cache")], work)
    # check-session: one warm check, then an edit and a second check in the same process.
    session_input = "check\n" + "check\n" + "quit\n"
    r["check_session_two_checks"] = run([M, "check-session", "main.my"], work, stdin=session_input)
    # Red project: a type error in an early module.
    early = work / "m001.my"
    good = early.read_text()
    early.write_text(good.replace("    return acc.total", '    return "not an int"', 1))
    r["red_check"] = run([M, "check", "main.my"], work)
    r["red_index_project"] = run([M, "index-project", "main.my"], work)
    r["red_list_interfaces"] = run([M, "list-interfaces", "main.my"], work)
    r["red_context_symbol"] = run([M, "context", "main.my", f"--symbol={symbol}"], work)
    r["red_tests_for"] = run([M, "tests-for", "main.my", symbol], work)
    early.write_text(good)
    (tier / "tooling.json").write_text(json.dumps(r, indent=1))
    for k, v in r.items():
        if isinstance(v, dict):
            print(f"{k:28} {v['s']:>8}s exit {v['exit']} out {v['stdout_bytes']:>9} B  {v['stderr_head'][:90]!r}")


if __name__ == "__main__":
    main()
