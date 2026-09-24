#!/usr/bin/env python3
"""Prototype: compile ONE module of a gen_scale.py project on its own, against
declaration-only stubs of its imports (a stand-in for Go-style export data), and check
that the objects it produces are the ones the whole-program build produced.

usage:
  module_compile.py stub TIER_SRC MODULE OUT_DIR      # write the stub project
  module_compile.py one  TIER_SRC MODULE OUT_DIR --mylang BIN --sidecar FULL.qbe-manifest.json [--mode default|Debug]
  module_compile.py all  TIER_SRC OUT_DIR --mylang BIN --jobs N [--frontend-only]

`stub` writes OUT_DIR/{main.my, MODULE.my, <import>.my...}: the module's own source
unchanged, and for every module it imports a stub that keeps the records and every
public signature but replaces each body with a small allocating loop. The stub keeps
the facts a caller's emission reads (the callee allocates, writes no parameter, is not
an inlining candidate), so the module's QBE IL should not change.

`one` builds the stub project (`build --project --report`), and compares the unit key
(a digest of the IL and the build environment) of every function of MODULE with the
key the whole-program build recorded in its sidecar. Identical keys mean identical
objects. Prints the build's wall time, the frontend's phases and the comparison.

`all` builds the stub project of every module, N at a time, and reports the wall time
(the per-module parallel frontend bound). With --frontend-only it runs only
`emit-project-qbe` per module (no codegen, no link).
"""
import argparse
import concurrent.futures
import json
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

STUB_BODY = {
    "int": ["    stub_xs: list[int] = []", "    for stub_k in range(n):", "        stub_xs.append(stub_k)", "    return len(stub_xs)"],
    "bool": ["    stub_xs: list[int] = []", "    for stub_k in range(3):", "        stub_xs.append(stub_k)", "    return len(stub_xs) > 0"],
}


def stub_source(text):
    """Keep module/import/record lines and def signatures; replace def bodies."""
    out, lines, i = [], text.splitlines(), 0
    while i < len(lines):
        line = lines[i]
        m = re.match(r"(public )?def (\w+)\((.*)\) -> (\w+):\s*$", line)
        if m:
            out.append(line)
            ret = m.group(4)
            params = m.group(3)
            body = list(STUB_BODY[ret])
            if "n: int" not in params:
                body = [b.replace("range(n)", "range(3)") for b in body]
            out += body
            i += 1
            while i < len(lines) and (lines[i].startswith(" ") or not lines[i].strip()):
                i += 1
            out.append("")
            continue
        if not line.startswith("import "):
            out.append(line)
        i += 1
    return "\n".join(out) + "\n"


def write_stub(src, module, out):
    out = Path(out)
    shutil.rmtree(out, ignore_errors=True)
    out.mkdir(parents=True)
    text = (Path(src) / f"{module}.my").read_text()
    (out / f"{module}.my").write_text(text)
    imports = re.findall(r"^import (\w+)", text, re.M)
    for imp in imports:
        (out / f"{imp}.my").write_text(stub_source((Path(src) / f"{imp}.my").read_text()))
    fns = re.findall(r"^public def (\w+)\((n: int)?\) -> int:", text, re.M)
    main = ["module main", f"import {module}", "", "", "def main(out: Stream) -> int:", "    total = 0"]
    for name, arg in fns:
        main.append(f"    total += {module}.{name}({'1' if arg else ''})")
    main += ["    out.print(total)", "    return 0", ""]
    (out / "main.my").write_text("\n".join(main))
    return out


def timed(cmd, cwd):
    t = time.perf_counter()
    p = subprocess.run(["/usr/bin/time", "-f", "__RSS__ %M"] + cmd, cwd=cwd, capture_output=True, text=True,
                       env=dict(os.environ, TMPDIR="/home/epentland/.cache/mylang-tmp"))
    dt = time.perf_counter() - t
    rss = re.search(r"__RSS__ (\d+)", p.stderr)
    return dt, p, int(rss.group(1)) if rss else None


def mode_args(mode):
    return ["--mode", "Debug"] if mode == "Debug" else []


def one(a):
    d = write_stub(a.src, a.module, a.out).resolve()
    cache = Path(a.cache or (Path(a.out).parent / f"cache-{a.module}")).resolve()
    cmd = [a.mylang, "build", "main.my", "--project", "-o", str(d / "stub"), f"--cache-dir={cache}", "--report", "--timings=json"] + mode_args(a.mode)
    dt, p, rss = timed(["taskset", "-c", "0-11"] + cmd, d)
    rep = None
    for line in p.stdout.splitlines():
        if line.startswith('{"version":"qbe-build-v1"'):
            rep = json.loads(line)
    res = {"module": a.module, "wall_s": round(dt, 3), "rc": p.returncode, "max_rss_kb": rss, "load": round(os.getloadavg()[0], 2)}
    if p.returncode != 0:
        res["err"] = (p.stderr + p.stdout)[-1500:]
        print(json.dumps(res))
        return
    res.update({k: rep.get(k) for k in ("frontend_seconds", "codegen_seconds", "link_seconds", "compiled_functions", "compiled_function_objects")})
    if a.sidecar:
        full = {f["name"]: f["key"] for f in json.load(open(a.sidecar))["functions"]}
        mine = {f["name"]: f["key"] for f in rep["functions"] if f["name"].startswith(a.module + "::")}
        same = sum(1 for n, k in mine.items() if full.get(n) == k)
        res["module_functions"] = len(mine)
        res["keys_identical_to_whole_program_build"] = same
        res["differing"] = [n for n, k in mine.items() if full.get(n) != k][:5]
        res["objects"] = sorted({f["object"] for f in rep["functions"] if f["name"].startswith(a.module + "::")})
    print(json.dumps(res), flush=True)
    for e in range(a.edits):
        text = (d / f"{a.module}.my").read_text()
        text = re.sub(r"(\+ ?)(\d+)(\)[^\n]*EDIT_BODY)", lambda m: f"{m.group(1)}{9100 + e}{m.group(3)}", text, count=1)
        (d / f"{a.module}.my").write_text(text)
        dt, p, rss = timed(["taskset", "-c", "0-11"] + cmd, d)
        rep = next((json.loads(line) for line in p.stdout.splitlines() if line.startswith('{"version":"qbe-build-v1"')), {})
        print(json.dumps({"edit": e, "wall_s": round(dt, 3), "rc": p.returncode, "max_rss_kb": rss, "load": round(os.getloadavg()[0], 2),
                          **{k: rep.get(k) for k in ("frontend_seconds", "codegen_seconds", "link_seconds", "compiled_functions",
                                                     "compiled_function_objects")}}), flush=True)


def all_modules(a):
    src = Path(a.src)
    mods = sorted(p.stem for p in src.glob("m[0-9]*.my"))
    root = Path(a.out).resolve()
    shutil.rmtree(root, ignore_errors=True)
    root.mkdir(parents=True)
    for m in mods:
        write_stub(src, m, root / m)

    def job(m):
        d = root / m
        cache = root / f"cache-{m}"
        if a.frontend_only:
            cmd = [a.mylang, "emit-project-qbe", str(d / "main.my"), "--lean-manifest=executable", f"--cache-dir={cache}"]
            if a.mode != "Debug":
                cmd += ["--drop-debug", "--drop-step-checks", "--drop-frame-checks"]
        else:
            cmd = [a.mylang, "build", "main.my", "--project", "-o", str(d / "stub"), f"--cache-dir={cache}"] + mode_args(a.mode)
        dt, p, rss = timed(cmd, d)
        return m, dt, p.returncode, rss, (p.stderr[-300:] if p.returncode else "")
    t = time.perf_counter()
    rows = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=a.jobs) as ex:
        for r in ex.map(job, mods):
            rows.append(r)
    wall = time.perf_counter() - t
    bad = [r for r in rows if r[2] != 0]
    print(json.dumps({"modules": len(mods), "jobs": a.jobs, "frontend_only": a.frontend_only, "wall_s": round(wall, 2),
                      "sum_s": round(sum(r[1] for r in rows), 2), "max_s": round(max(r[1] for r in rows), 3),
                      "max_rss_kb": max((r[3] or 0) for r in rows), "failed": len(bad), "first_failure": bad[0] if bad else None,
                      "load": round(os.getloadavg()[0], 2)}))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd")
    ap.add_argument("src")
    ap.add_argument("module_or_out")
    ap.add_argument("out", nargs="?")
    ap.add_argument("--mylang")
    ap.add_argument("--sidecar")
    ap.add_argument("--cache")
    ap.add_argument("--mode", default="default")
    ap.add_argument("--jobs", type=int, default=12)
    ap.add_argument("--frontend-only", action="store_true")
    ap.add_argument("--edits", type=int, default=0)
    a = ap.parse_args()
    if a.cmd == "stub":
        write_stub(a.src, a.module_or_out, a.out)
    elif a.cmd == "one":
        a.module = a.module_or_out
        one(a)
    elif a.cmd == "all":
        a.out = a.module_or_out
        all_modules(a)


if __name__ == "__main__":
    main()
