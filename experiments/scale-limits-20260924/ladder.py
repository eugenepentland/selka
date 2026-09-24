#!/usr/bin/env python3
"""The scale-limits edit ladder for one tier and one compiler (mylang only).

usage: ladder.py TIER_DIR COMPILER LABEL [--samples 3] [--skip-test] [--steps cold,noop,...]

Steps (the generated project copied fresh into TIER_DIR/work-LABEL, caches empty):
  cold_build   first `build --project` (default mode: ReleaseFast, QBE)
  noop_build   the same build again
  edit_check   body edit in the middle module, then `check`
  edit_build   body edit, then build
  edit_test    body edit, then `mylang test main.my`
  iface_build  a new public function appended to the middle module, then build
Before the edit rows one untimed `test` and one `check` warm their caches, as run_scale.py
does. Afterwards two untimed `check --report` runs of the unchanged project record the
frontend cache receipt (`evicted` on the second is the retention acceptance), and one
`build --report` after an interface edit records `metadata_reused`.

Each row: wall seconds (min of samples), max RSS in MB of the command's process tree
(/usr/bin/time %M), exit status and the tail of a failure. The 1-minute load average
is recorded before and after every step. JSON Lines on stdout and in TIER_DIR/ladder-LABEL.jsonl.
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import time
from pathlib import Path

TIME = "/usr/bin/time"
CPUS = os.environ.get("SCALE_CPUS", "0-11")


def run(cmd, cwd, env, timeout=3600):
    wrapped = ["taskset", "-c", CPUS, TIME, "-f", "__RSS__ %M"] + cmd
    load = os.getloadavg()[0]
    start = time.perf_counter()
    try:
        p = subprocess.run(wrapped, cwd=cwd, env=env, capture_output=True, text=True, timeout=timeout)
        code, out, err = p.returncode, p.stdout, p.stderr
    except subprocess.TimeoutExpired as e:
        code, out, err = -1, "", f"timeout after {timeout}s"
    wall = time.perf_counter() - start
    m = re.search(r"__RSS__ (\d+)", err)
    return {"s": round(wall, 3), "rss_mb": round(int(m.group(1)) / 1024) if m else None, "ok": code == 0, "code": code,
            "load": round(load, 2), "stdout": out, "stderr": err, "tail": "" if code == 0 else (out + err)[-2000:]}


def body_edit(path, token):
    s = path.read_text()
    s2, n = re.subn(r"(\+ ?)(\d+)(\)[^\n]*EDIT_BODY)", lambda m: f"{m.group(1)}{token}{m.group(3)}", s, count=1)
    assert n == 1, path
    path.write_text(s2)


def iface_edit(path, token):
    with path.open("a") as f:
        f.write(f"\n\npublic def extra_{token}(n: int) -> int:\n    return n + {token}\n")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("tier")
    ap.add_argument("compiler")
    ap.add_argument("label")
    ap.add_argument("--samples", type=int, default=3)
    ap.add_argument("--skip-test", action="store_true")
    ap.add_argument("--keep", action="store_true", help="reuse an existing work dir and caches (no cold row)")
    ap.add_argument("--cold-env", action="append", default=[], help="KEY=VALUE for the cold build and cold test only")
    a = ap.parse_args()
    tier = Path(a.tier).resolve()
    src = tier / "mylang"
    work = tier / f"work-{a.label}"
    cache = tier / f"work-{a.label}-cache"
    if not a.keep:
        shutil.rmtree(work, ignore_errors=True)
        shutil.rmtree(cache, ignore_errors=True)
        shutil.copytree(src, work)
        cache.mkdir(parents=True)
    (cache / "bin").mkdir(exist_ok=True)
    env = dict(os.environ, TMPDIR="/home/epentland/.cache/mylang-tmp")
    M = len(list(src.glob("m*.my")))
    target = work / f"m{M // 2:03d}.my"
    out = cache / "bin" / "big"
    C = a.compiler
    build = [C, "build", "main.my", "--project", "-o", str(out), f"--cache-dir={cache / 'mylang'}"]
    check = [C, "check", "main.my"]
    test = [C, "test", "main.my", "--cache-dir", str(cache / "mytest")]
    log = open(tier / f"ladder-{a.label}.jsonl", "a")

    def emit(row):
        row = {k: v for k, v in row.items() if k not in ("stdout", "stderr")}
        row.update({"tier": tier.name, "label": a.label})
        print(json.dumps(row), flush=True)
        log.write(json.dumps(row) + "\n")
        log.flush()

    cold_env = dict(env, **dict(kv.split("=", 1) for kv in a.cold_env))
    if not a.keep:
        emit({"step": "cold_build", "env": a.cold_env, **run(build, work, cold_env)})
        emit({"step": "noop_build", **run(build, work, env)})
        if not a.skip_test:
            emit({"step": "cold_test_untimed", "env": a.cold_env, **run(test, work, cold_env)})
        emit({"step": "warm_check_untimed", **run(check, work, env)})
    steps = [("edit_check", check, 1), ("edit_build", build, 2)] + ([] if a.skip_test else [("edit_test", test, 3)])
    for s in range(a.samples):
        for step, cmd, k in steps:
            body_edit(target, 7000 + 10 * s + k + (100 if a.keep else 0))
            emit({"step": step, "sample": s, **run(cmd, work, env)})
        iface_edit(target, 9000 + s + (100 if a.keep else 0))
        emit({"step": "iface_build", "sample": s, **run(build, work, env)})
    # Receipts: the retention acceptance and the shared-metadata reuse after an interface edit.
    first = run(check + ["--report"], work, env)
    second = run(check + ["--report"], work, env)
    receipt = re.search(r'\{"version":"frontend-cache-v1".*', second["stdout"] + second["stderr"])
    emit({"step": "check_receipt", "first": {k: first[k] for k in ("s", "rss_mb", "ok")}, **{k: second[k] for k in ("s", "rss_mb", "ok", "tail")},
          "receipt": receipt.group(0)[:600] if receipt else None})
    iface_edit(target, 9500)
    built = run(build + ["--report"], work, env)
    m = re.search(r'"metadata_reused":(true|false)', built["stdout"])
    c = re.search(r'"compiled_functions":(\d+)', built["stdout"])
    cs = re.search(r'"codegen_seconds":([0-9.e-]+)', built["stdout"])
    emit({"step": "iface_build_receipt", **{k: built[k] for k in ("s", "rss_mb", "ok", "tail")},
          "metadata_reused": m.group(1) if m else None, "compiled_functions": int(c.group(1)) if c else None,
          "codegen_seconds": float(cs.group(1)) if cs else None})


if __name__ == "__main__":
    main()
