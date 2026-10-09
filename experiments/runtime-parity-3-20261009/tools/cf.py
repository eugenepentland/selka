#!/usr/bin/env python3
"""Counterfactual builds of one mylang program (wave PM, PM-2/PM-4).

The release build's LLVM text (`--emit-llvm`) is edited to remove one kind of
work, recompiled with the exact flags the driver uses (`zig cc -c -O3 -target
x86_64-linux-gnu.2.31 -march=native ...`), linked with the same runtime objects,
run, checked against the real build's output, and measured with `perf stat` on
CPU 8, interleaved with the unedited rebuild. Each variant is an upper bound on
what one lever can win, never a proposal: removing a check or a count update is
only measured, and a variant whose output differs is reported as invalid.

Variants (combine with '+'):
  base      the unedited text, rebuilt (must match the real build)
  bounds    conditional traps of index/pop/substring kinds never taken
  overflow  overflow traps never taken
  divshift  division-by-zero and shift traps never taken
  checks    every conditional trap never taken
  unique    every `is_unique` test is true
  norc      every inline retain and release skipped (blocks leak)
  srem      `urem`/`udiv` by a constant emitted as `srem`/`sdiv` (valid where the
            operands are non-negative, which is why the core chose unsigned)
  tail      `notail call` emitted as plain `call` (lets LLVM eliminate tail
            recursion and make tail calls)
  inline    the unit compiled with `-mllvm -inline-threshold=1000` (default 225 at
            -O3): how much a larger inlining budget would buy
  tbaa      element data tagged by scalar type (`myl.data.double`, `.ptr`, ...)
            instead of one `myl.data` tag

usage: cf.py --program P.my --mylang M --work DIR --name N [--cwd DIR] [--rounds 3]
             [--variants base,checks,...] [--case LABEL='["arg", ...]' ...]
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import random
import re
import statistics
import subprocess
from pathlib import Path

ZIG_FLAGS = ["-O3", "-target", "x86_64-linux-gnu.2.31", "-march=native", "-mllvm",
             "-x86-experimental-pref-innermost-loop-alignment=6", "-Wno-override-module"]
BOUNDS_KINDS = {2, 6, 11, 16, 19}
OVERFLOW_KINDS = {0}
DIVSHIFT_KINDS = {1, 17}
EVENTS = ["instructions", "cycles", "branch-misses", "L1-dcache-load-misses"]


def site_kinds(text: str) -> dict[str, int]:
    return {m.group(1): int(m.group(2)) for m in re.finditer(r"^@(myl\.site\.\d+) = private constant %myl\.site \{ i32 (\d+),", text, re.M)}


def trap_kinds(text: str, kinds: dict[str, int]) -> dict[str, int]:
    """Label of each trap block -> the kind of the site it reports."""
    found = {}
    for m in re.finditer(r"^(trap[.\w]*):\n((?:  .*\n)*?)  call void @myl_core_trap\(ptr @(myl\.site\.\d+)", text, re.M):
        found[m.group(1)] = kinds.get(m.group(3), -1)
    return found


def edit(text: str, variant: str) -> str:
    parts = set(variant.split("+"))
    drop: set[int] = set()
    if "bounds" in parts: drop |= BOUNDS_KINDS
    if "overflow" in parts: drop |= OVERFLOW_KINDS
    if "divshift" in parts: drop |= DIVSHIFT_KINDS
    if "checks" in parts: drop = None  # every kind
    if drop is None or drop:
        traps = trap_kinds(text, site_kinds(text))

        def branch(m: re.Match) -> str:
            kind = traps.get(m.group(2))
            if kind is None or (drop is not None and kind not in drop):
                return m.group(0)
            return f"  br label %{m.group(3)}"
        text = re.sub(r"^  br i1 (\S+), label %(trap[.\w]*), label %([.\w]+), !prof !0$", branch, text, flags=re.M)
    if "unique" in parts:
        # isUnique: `%rcN = load i32 ... !tbaa !3 ...` then `%v = icmp eq i32 %rcN, 1`.
        text = re.sub(r"^(  %\S+ = icmp eq i32 )(%rc[.\d]*), 1$", r"\g<1>1, 1", text, flags=re.M)
    if "norc" in parts:
        text = re.sub(r"^  br i1 (%rs[.\d]*), label %([.\w]+), label %rc\.(inc|dec)[.\d]*$", r"  br label %\2", text, flags=re.M)
    if "srem" in parts:
        text = re.sub(r"= urem i64 (%\S+), (\d+)$", r"= srem i64 \1, \2", text, flags=re.M)
        text = re.sub(r"= udiv i64 (%\S+), (\d+)$", r"= sdiv i64 \1, \2", text, flags=re.M)
    if "tail" in parts:
        text = text.replace(" notail call ", " call ")
    if "tbaa" in parts:
        types: dict[str, int] = {}
        nodes = [int(n) for n in re.findall(r"^!(\d+) = ", text, re.M)]
        nxt = max(nodes) + 1 if nodes else 100

        def tag(ty: str) -> str:
            nonlocal nxt
            if ty not in types:
                types[ty] = nxt
                nxt += 2
            return f"!{types[ty] + 1}"

        def retag(m: re.Match) -> str:
            return m.group(1) + tag(m.group(2) or m.group(3))
        text = re.sub(r"^(  (?:%\S+ = load (\S+), ptr \S+|store (\S+) \S+, ptr \S+), align \d+, !tbaa )!7\b", retag, text, flags=re.M)
        extra = "".join(f'!{n} = !{{!"myl.data.{ty}", !6, i64 0}}\n!{n + 1} = !{{!{n}, !{n}, i64 0}}\n' for ty, n in types.items())
        text = text.rstrip("\n") + "\n" + extra
    return text


def run(argv, **kw):
    return subprocess.run(argv, check=True, **kw)


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--program", required=True)
    p.add_argument("--mylang", required=True)
    p.add_argument("--zig", default="zig")
    p.add_argument("--work", required=True)
    p.add_argument("--name", required=True)
    p.add_argument("--cwd", default=None)
    p.add_argument("--rounds", type=int, default=3)
    p.add_argument("--variants", default="base,bounds,overflow,checks,unique,norc,tbaa,checks+tbaa,checks+tbaa+unique")
    p.add_argument("--case", action="append", default=[], help="LABEL=JSON argv list; repeat for several runs of one build")
    p.add_argument("--cpu", type=int, default=8)
    p.add_argument("--keep", action="store_true")
    p.add_argument("--outdir-check", default=None, help="a directory the program writes; its files join the output hash")
    a = p.parse_args()
    work = Path(a.work).resolve() / a.name
    work.mkdir(parents=True, exist_ok=True)
    rtc = Path(a.work).resolve() / "runtime-store"
    env = dict(os.environ, MYLANG_CORE_RUNTIME_CACHE=str(rtc))
    program = Path(a.program).resolve()
    cwd = a.cwd or str(program.parent)
    real = work / "real"
    ll = work / "base.ll"
    run([a.mylang, "build", str(program), "-o", str(real), "--release", "--emit-llvm", str(ll), "--cache-dir", str(work / "cache")],
        cwd=cwd, env=env, stdout=subprocess.DEVNULL)
    objects = sorted(str(o) for o in rtc.glob("*.o") if "count" not in o.name)
    text = ll.read_text()
    binaries = {"real": real}
    notes = {}
    for variant in a.variants.split(","):
        edited = edit(text, variant)
        src = work / f"{variant}.ll"
        src.write_text(edited)
        obj = work / f"{variant}.o"
        exe = work / f"{variant}.exe"
        extra = ["-mllvm", "-inline-threshold=1000"] if "inline" in variant.split("+") else []
        run([a.zig, "cc", "-c", *ZIG_FLAGS, *extra, "-o", str(obj), str(src)], env=env)
        run([a.zig, "cc", "-O3", "-target", "x86_64-linux-gnu.2.31", "-march=native", "-mllvm",
             "-x86-experimental-pref-innermost-loop-alignment=6", "-Wno-override-module", "-o", str(exe), *objects, str(obj), "-lm"], env=env)
        binaries[variant] = exe
        notes[variant] = {"llvm_lines_changed": sum(1 for x, y in zip(text.splitlines(), edited.splitlines()) if x != y)}
        if not a.keep:
            src.unlink(); obj.unlink()
    cases = [(c.split("=", 1)[0], json.loads(c.split("=", 1)[1])) for c in a.case] or [("run", [])]
    result = {"program": str(program), "name": a.name, "cases": {}}
    for case, args in cases:
        outputs = {}
        for label, exe in binaries.items():
            if a.outdir_check:
                subprocess.run(["rm", "-rf", a.outdir_check])
            proc = subprocess.run(["taskset", "-c", str(a.cpu), str(exe), *args], cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            digest = hashlib.sha256(proc.stdout)
            if a.outdir_check:
                for f in sorted(Path(a.outdir_check).rglob("*")):
                    if f.is_file():
                        digest.update(str(f.relative_to(a.outdir_check)).encode() + f.read_bytes())
            outputs[label] = (proc.returncode, digest.hexdigest())
        rng = random.Random(7)
        samples = {k: [] for k in binaries}
        for _ in range(a.rounds):
            order = list(binaries)
            rng.shuffle(order)
            for label in order:
                proc = subprocess.run(["taskset", "-c", str(a.cpu), "perf", "stat", "-x,", "-e", ",".join(f"cpu_core/{e}/u" for e in EVENTS),
                                       "--", str(binaries[label]), *args], cwd=cwd, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
                row = {}
                for line in proc.stderr.splitlines():
                    f = line.split(",")
                    if len(f) > 2 and f[2].startswith("cpu_core/"):
                        try: row[f[2][9:].rsplit("/", 1)[0]] = int(f[0])
                        except ValueError: pass
                samples[label].append(row)
        variants = {}
        for label in binaries:
            med = {e: statistics.median([s[e] for s in samples[label] if e in s]) for e in EVENTS}
            variants[label] = {"median": med, "status": outputs[label][0], "output_matches_real": outputs[label] == outputs["real"], **notes.get(label, {})}
        result["cases"][case] = {"args": args, "variants": variants}
        base = variants.get("base", variants["real"])["median"]
        print(f"## {a.name} {case}")
        print("| variant | Minstr | Mcycles | instr ÷ base | cycles ÷ base | output | lines edited |")
        print("|---|---:|---:|---:|---:|---|---:|")
        for label, v in variants.items():
            m = v["median"]
            print(f"| {label} | {m['instructions']/1e6:.0f} | {m['cycles']/1e6:.0f} | {m['instructions']/base['instructions']:.3f} | {m['cycles']/base['cycles']:.3f} | {'ok' if v['output_matches_real'] else 'DIFFERS'} | {v.get('llvm_lines_changed', '')} |")
    (work / "result.json").write_text(json.dumps(result, indent=1))
    if not a.keep:
        for exe in binaries.values():
            if exe != real: exe.unlink()


if __name__ == "__main__":
    main()
