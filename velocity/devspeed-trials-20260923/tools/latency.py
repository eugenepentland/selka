#!/usr/bin/env python3
"""Edit-loop latency probes for mylang (installed ReleaseFast main 35fcbc02) vs Go/Python.

Min of N samples per step; cold steps use a fresh cache directory each sample.
"""
import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

M = "/home/epentland/ai/canopy/mylang-worktrees/devspeed-audit-20260923/.install/bin/mylang"
GO = "/home/epentland/.local/bin/go"
SP = Path("/tmp/claude-1000/-home-epentland-ai-canopy-mylang/481b72b0-e2f9-4f0f-bcf8-35b9cdd4c0b4/scratchpad/lat")
LOX = Path("/home/epentland/ai/trials/devspeed-20260923-private/probe/benchmarks/lox/ports")
ENV = dict(os.environ, TMPDIR="/home/epentland/.cache/mylang-tmp")
N = 3

SMALL = '''module prog


def count_words(text: str) -> dict[str, int]:
    counts: dict[str, int] = {}
    for word in text.lower().split():
        counts[word] = counts.get(word, 0) + 1
    return counts


def top(counts: dict[str, int], n: int) -> list[str]:
    keys = sorted([k for k in counts])
    out: list[str] = []
    for k in keys:
        if len(out) < n:
            out.append(f"{k} {counts[k]}")
    return out


public def test_count_words() -> bool:
    c = count_words("a b a")
    return c["a"] == 2 and c["b"] == 1


public def test_top() -> bool:
    return top({"x": 1, "y": 2}, 1) == ["x 1"]


def main(out: Stream) -> int:
    for line in top(count_words("the cat and the hat"), 3):
        out.print(line)
    return 0
'''


def timed(cmd, cwd):
    t = time.perf_counter()
    p = subprocess.run(cmd, cwd=cwd, env=ENV, capture_output=True)
    dt = time.perf_counter() - t
    if p.returncode != 0:
        print("FAILED", cmd, p.stderr[-800:].decode(errors="replace"), file=sys.stderr)
    return dt


def edit(path, i):
    s = path.read_text()
    marker = "    return 0\n"
    s = s.replace(marker, f"    _ = {i}\n" + marker, 1) if marker in s else s
    path.write_text(s)


def small_suite():
    res = {}
    d = SP / "small"
    shutil.rmtree(d, ignore_errors=True)
    d.mkdir(parents=True)
    src = d / "prog.my"
    samples = {k: [] for k in ["run_cold", "run_warm", "run_edit", "check_warm", "check_edit", "test_cold", "test_warm", "test_edit", "build_edit"]}
    for i in range(N):
        src.write_text(SMALL)
        cache = d / f"cache{i}"
        samples["run_cold"].append(timed([M, "run", "prog.my", f"--cache-dir={cache}"], d))
        samples["run_warm"].append(timed([M, "run", "prog.my", f"--cache-dir={cache}"], d))
        edit(src, i * 10 + 1)
        samples["run_edit"].append(timed([M, "run", "prog.my", f"--cache-dir={cache}"], d))
        samples["check_warm"].append(timed([M, "check", "prog.my"], d))
        edit(src, i * 10 + 2)
        samples["check_edit"].append(timed([M, "check", "prog.my"], d))
        tcache = d / f"tcache{i}"
        samples["test_cold"].append(timed([M, "test", "prog.my", "--cache-dir", str(tcache)], d))
        samples["test_warm"].append(timed([M, "test", "prog.my", "--cache-dir", str(tcache)], d))
        edit(src, i * 10 + 3)
        samples["test_edit"].append(timed([M, "test", "prog.my", "--cache-dir", str(tcache)], d))
        edit(src, i * 10 + 4)
        samples["build_edit"].append(timed([M, "build", "prog.my", "-o", str(d / "prog"), f"--cache-dir={cache}"], d))
    res["mylang_small"] = {k: round(min(v), 3) for k, v in samples.items()}
    py = d / "prog.py"
    py.write_text("def main():\n    print('hi')\n    return 0\nif __name__ == '__main__':\n    raise SystemExit(main())\n")
    res["python_small_run"] = round(min(timed(["python3", "prog.py"], d) for _ in range(N)), 3)
    return res


def lox_suite():
    res = {}
    src = LOX / "mylang"
    work = SP / "lox-mylang"
    shutil.rmtree(work, ignore_errors=True)
    shutil.copytree(src, work)
    target = work / "scanner.my"
    base = target.read_text()
    anchor = "def is_digit("
    assert anchor in base
    samples = {k: [] for k in ["check_warm", "check_edit", "build_qbe_cold", "build_qbe_warm", "build_qbe_edit", "test_dir_cold", "test_dir_warm", "test_dir_edit"]}
    for i in range(N):
        target.write_text(base)
        cache = work / f"cache{i}"
        timed([M, "check", "main.my"], work)
        samples["check_warm"].append(timed([M, "check", "main.my"], work))
        target.write_text(base.replace(anchor, f"# edit {i}a\n" + anchor.replace("def", "def"), 1).replace("    return ", f"    _ = {i}\n    return ", 1))
        samples["check_edit"].append(timed([M, "check", "main.my"], work))
        target.write_text(base)
        samples["build_qbe_cold"].append(timed([M, "build", "main.my", "--project", "--backend", "qbe", "-o", str(work / "lox"), f"--cache-dir={cache}"], work))
        samples["build_qbe_warm"].append(timed([M, "build", "main.my", "--project", "--backend", "qbe", "-o", str(work / "lox"), f"--cache-dir={cache}"], work))
        target.write_text(base.replace("    return ", f"    _ = {i + 100}\n    return ", 1))
        samples["build_qbe_edit"].append(timed([M, "build", "main.my", "--project", "--backend", "qbe", "-o", str(work / "lox"), f"--cache-dir={cache}"], work))
        target.write_text(base)
        tcache = work / f"tcache{i}"
        samples["test_dir_cold"].append(timed([M, "test", ".", "--cache-dir", str(tcache)], work))
        samples["test_dir_warm"].append(timed([M, "test", ".", "--cache-dir", str(tcache)], work))
        target.write_text(base.replace("    return ", f"    _ = {i + 200}\n    return ", 1))
        samples["test_dir_edit"].append(timed([M, "test", ".", "--cache-dir", str(tcache)], work))
    target.write_text(base)
    res["mylang_lox"] = {k: round(min(v), 3) for k, v in samples.items()}
    gsrc = Path("/home/epentland/ai/trials/devspeed-20260923-private/probe/benchmarks/lox/ports/go")
    gwork = SP / "lox-go"
    shutil.rmtree(gwork, ignore_errors=True)
    shutil.copytree(gsrc, gwork)
    gt = gwork / "internal" / "scanner" / "scanner.go"
    gbase = gt.read_text()
    gs = {k: [] for k in ["build_edit", "test_edit", "vet_edit"]}
    timed([GO, "build", "-o", str(gwork / "lox"), "./cmd/lox"], gwork)
    for i in range(N):
        gt.write_text(gbase + f"\n// edit {i}\nvar _ = {i}\n")
        gs["build_edit"].append(timed([GO, "build", "-o", str(gwork / "lox"), "./cmd/lox"], gwork))
        gt.write_text(gbase + f"\n// edit t{i}\nvar _ = {i + 50}\n")
        gs["test_edit"].append(timed([GO, "test", "./..."], gwork))
        gt.write_text(gbase + f"\n// edit v{i}\nvar _ = {i + 90}\n")
        gs["vet_edit"].append(timed([GO, "vet", "./..."], gwork))
    gt.write_text(gbase)
    res["go_lox"] = {k: round(min(v), 3) for k, v in gs.items()}
    return res


if __name__ == "__main__":
    SP.mkdir(parents=True, exist_ok=True)
    out = {"load_before": os.getloadavg()}
    out.update(small_suite())
    pass
    out["load_after"] = os.getloadavg()
    print(json.dumps(out, indent=1))
