#!/usr/bin/env python3
"""Differential test: turn each guest test module into a program whose main
prints every test's result, build it with two compilers (and optionally two
backends), run both, and compare exit status, stdout and stderr.

usage: difftest.py OUTDIR MYLANG_A MYLANG_B [--qbe] FILE.my...
  --qbe  build B with `--qbe=<qbe>` (QBE backend) instead of the LLVM default
"""
import os
import re
import subprocess
import sys

out, compiler_a, compiler_b, *rest = sys.argv[1:]
qbe = "--qbe" in rest
files = [f for f in rest if f != "--qbe"]
os.makedirs(out, exist_ok=True)
env = dict(os.environ, TMPDIR="/home/epentland/.cache/mylang-tmp")
root = "/home/epentland/ai/canopy/mylang/.claude/worktrees/agent-ad59f229cfd824c2d"


def program(path):
    text = open(path).read()
    if re.search(r"^def main\(", text, re.M):
        return text, True
    names = re.findall(r"^(?:public )?def (test_\w+)\(\) -> bool:", text, re.M)
    if not names:
        return None, False
    text = re.sub(r"^module \w+\n", "", text, flags=re.M)
    text = re.sub(r"^public ", "", text, flags=re.M)
    body = "".join(f"    out.print(\"{n}\", {n}())\n" for n in names)
    return text + "\n\ndef main(out: Stream) -> int:\n" + body + "    return 0\n", False


def build(compiler, source, binary, extra):
    r = subprocess.run([compiler, "build", source, "-o", binary, f"--cache-dir={out}/cache"] + extra,
                       capture_output=True, text=True, env=env)
    return r.returncode == 0, r.stderr


def run(binary):
    try:
        r = subprocess.run(["taskset", "-c", "0-3,6-19", binary], capture_output=True, text=True, timeout=120)
        return r.returncode, r.stdout, r.stderr.replace(binary, "BIN")
    except subprocess.TimeoutExpired:
        return "timeout", "", ""


same = differ = skipped = 0
for path in files:
    name = os.path.splitext(os.path.basename(path))[0]
    text, runnable = program(path)
    if text is None:
        skipped += 1
        continue
    source = os.path.join(out, name + ".my") if not runnable else path
    if not runnable:
        # A private copy of the module's directory keeps sibling modules
        # importable without writing into the source tree.
        mirror = os.path.join(out, "src", os.path.basename(os.path.dirname(os.path.abspath(path))))
        if not os.path.isdir(mirror):
            import shutil
            shutil.copytree(os.path.dirname(os.path.abspath(path)), mirror)
        source = os.path.join(mirror, f"difftest_{name}.my")
        open(source, "w").write(text)
    try:
        ok_a, err_a = build(compiler_a, source, os.path.join(out, name + ".a"), [])
        extra = [f"--qbe={root}/zig-out/bin/qbe"] if qbe else []
        ok_b, err_b = build(compiler_b, source, os.path.join(out, name + ".b"), extra)
    finally:
        if not runnable:
            os.unlink(source)
    if not ok_a or not ok_b:
        print(f"SKIP {name}: build {'A' if not ok_a else 'B'} failed: {(err_a if not ok_a else err_b).strip().splitlines()[:1]}")
        skipped += 1
        continue
    ra = run(os.path.join(out, name + ".a"))
    rb = run(os.path.join(out, name + ".b"))
    ra = (ra[0], ra[1], ra[2].replace(".a", ""))
    rb = (rb[0], rb[1], rb[2].replace(".b", ""))
    if ra == rb:
        same += 1
        if "False" in ra[1] or "false" in ra[1]:
            print(f"SAME-but-false {name}")
    else:
        differ += 1
        print(f"DIFF {name}: status {ra[0]} vs {rb[0]}")
        for label, r in (("A", ra), ("B", rb)):
            print(f"  {label} stdout: {r[1][-300:]!r}")
            print(f"  {label} stderr: {r[2][-300:]!r}")
print(f"same {same}, differ {differ}, skipped {skipped}")
