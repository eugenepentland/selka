#!/usr/bin/env python3
"""Replay a captured `ld.lld` link (capture_link.py) under variants, and prototype
thin-link and dynamic-link development builds.

usage: linkbench.py LINK.json SCRATCH --module mNNN --expect STDOUT [--samples 3] [--variants a,b,...]

Variants
  base        the captured link, output into SCRATCH
  nogc        without --gc-sections
  t1          --threads=1
  nometa      without the per-batch metadata objects (unresolved symbols ignored; the
              output does not run; an upper bound for shrinking the position tables)
  prelink     `ld.lld -r` every guest object outside --module into one relocatable
              (timed once), then the final link of that relocatable plus the module's
              objects (timed per sample); the output must run and print --expect
  dynamic     a development layout: every guest object outside --module in librest.so,
              the module's objects in libmod.so, and a thin executable of the entry,
              the shared metadata unit and the runtime. Times the one-time links, the
              per-edit relink of libmod.so alone, and the program's start-up; the
              output must print --expect
  permodule   like dynamic, but one shared object per module (the fully modular
              development build): times the per-edit relink of one module's object and
              the start-up with every module loaded

Objects are attributed to modules by the functions they define (`myl_f_*` code and
`*_meta` metadata symbols), using the sidecar written next to the executable.
Prints one JSON line per measurement.
"""
import argparse
import json
import os
import re
import shutil
import struct
import subprocess
import sys
import time
from pathlib import Path


def defined_globals(path):
    b = Path(path).read_bytes()
    if b[:4] != b"\x7fELF":
        return []
    shoff, = struct.unpack_from("<Q", b, 0x28)
    shentsize, shnum, _ = struct.unpack_from("<HHH", b, 0x3A)
    hdrs = [struct.unpack_from("<IIQQQQIIQQ", b, shoff + i * shentsize) for i in range(shnum)]
    out = []
    for (name, typ, flags, addr, off, size, link, info, align, entsize) in hdrs:
        if typ != 2:
            continue
        stroff = hdrs[link][4]
        for i in range(size // 24):
            st_name, st_info, st_other, st_shndx, st_value, st_size = struct.unpack_from("<IBBHQQ", b, off + i * 24)
            if st_shndx == 0 or (st_info >> 4) == 0:
                continue
            e = b.index(b"\0", stroff + st_name)
            out.append(b[stroff + st_name:e].decode())
    return out


def run(cmd, label, cwd=None, env=None, check=True):
    t = time.perf_counter()
    p = subprocess.run(["taskset", "-c", os.environ.get("SCALE_CPUS", "0-11")] + cmd, cwd=cwd, env=env, capture_output=True, text=True)
    dt = time.perf_counter() - t
    rec = {"label": label, "s": round(dt, 4), "rc": p.returncode, "load": round(os.getloadavg()[0], 2)}
    if p.returncode != 0:
        rec["err"] = (p.stderr or p.stdout)[-800:]
    return rec, p


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("link")
    ap.add_argument("scratch")
    ap.add_argument("--module", required=True)
    ap.add_argument("--expect", required=True)
    ap.add_argument("--samples", type=int, default=3)
    ap.add_argument("--variants", default="base,nogc,t1,nometa,prelink,dynamic")
    ap.add_argument("--sidecar")
    a = ap.parse_args()
    cap = json.load(open(a.link))
    argv = cap["link"]
    scratch = Path(a.scratch)
    scratch.mkdir(parents=True, exist_ok=True)
    oi = argv.index("-o")
    objs = [x for x in argv if x.endswith(".o") and "/objects/" in x]
    crt = [x for x in argv if x.endswith(".o") and "/objects/" not in x]
    sidecar = a.sidecar or (argv[oi + 1].rsplit("/.pending/", 1)[0] + "/big.qbe-manifest.json")
    fn = json.load(open(sidecar))["functions"]
    sym_module = {f["symbol"]: f["name"].split("::")[0] for f in fn}
    obj_module, kinds = {}, {}
    for o in objs:
        mods, kind = set(), "other"
        for s in defined_globals(o):
            if s.endswith("_meta") and s[:-5] in sym_module:
                mods.add(sym_module[s[:-5]])
                kind = "meta" if kind == "other" else kind
            elif s in sym_module:
                mods.add(sym_module[s])
                kind = "code"
        obj_module[o] = mods
        kinds[o] = kind
    shared = [o for o in objs if not obj_module[o]]
    mine = [o for o in objs if obj_module[o] == {a.module}]
    rest = [o for o in objs if obj_module[o] and obj_module[o] != {a.module}]
    print(json.dumps({"objects": len(objs), "shared_or_entry": len(shared), "module_objects": len(mine), "rest": len(rest),
                      "mixed": sum(1 for o in objs if len(obj_module[o]) > 1)}), flush=True)
    zig = argv[0]
    variants = a.variants.split(",")

    def with_output(args, out):
        args = list(args)
        args[args.index("-o") + 1] = str(out)
        return args

    def check_output(exe, label, env=None):
        rec, p = run([str(exe)], label + ":run", env=env)
        rec["ok"] = p.stdout.strip() == a.expect
        return rec

    def sample(label, cmd, out=None, n=None):
        best = None
        if out and Path(out).exists():
            Path(out).unlink()
        for _ in range(n or a.samples):
            rec, _ = run(cmd, label)
            if rec["rc"] != 0:
                print(json.dumps(rec), flush=True)
                return None
            best = rec if best is None or rec["s"] < best["s"] else best
        if out:
            best["output_bytes"] = Path(out).stat().st_size
        print(json.dumps(best), flush=True)
        return best

    out = scratch / "program"
    if "base" in variants:
        sample("base", with_output(argv, out), out)
        print(json.dumps(check_output(out, "base")), flush=True)
    if "nogc" in variants:
        sample("nogc", [x for x in with_output(argv, out) if x != "--gc-sections"], out)
    if "t1" in variants:
        sample("t1", with_output(argv, out) + ["--threads=1"], out)
    if "nometa" in variants:
        keep = [x for x in with_output(argv, out) if not (x in kinds and kinds[x] == "meta")]
        sample("nometa", keep + ["--unresolved-symbols=ignore-all", "--noinhibit-exec"], out)
    if "prelink" in variants:
        rest_o = scratch / "rest.o"
        r = sample("prelink:ld-r-rest (once)", [zig, "ld.lld", "-r", "-o", str(rest_o)] + rest, rest_o, n=1)
        final = [x for x in with_output(argv, out) if x not in rest]
        pos = final.index(mine[0]) if mine else len(final)
        final = final[:pos] + [str(rest_o)] + final[pos:]
        sample("prelink:final", final, out)
        print(json.dumps(check_output(out, "prelink")), flush=True)
    if "dynamic" in variants or "permodule" in variants:
        # The thin executable: crt, entry and shared metadata units, the runtime archive
        # (kept whole and exported so the shared objects resolve into it).
        base = with_output(argv, out)
        tail_start = min(i for i, x in enumerate(base) if x.endswith(".a"))
        head = [x for x in base[:tail_start] if not x.endswith(".o") and x != "--gc-sections" and x != "-s"]
        tail = base[tail_start:]
        lib = [zig, "ld.lld", "-shared", "-Bsymbolic", "-z", "undefs", "--build-id=none", "-m", "elf_x86_64", "-z", "now"]
        if "dynamic" in variants:
            librest = scratch / "librest.so"
            libmod = scratch / "libmod.so"
            r1 = sample("dynamic:librest.so (once)", lib + ["-o", str(librest)] + rest, librest, n=1)
            r2 = sample("dynamic:libmod.so (per edit)", lib + ["-o", str(libmod)] + mine, libmod)
            exe = head + crt[:2] + shared + ["--export-dynamic", "--whole-archive"] + [tail[0]] + ["--no-whole-archive"] + tail[1:-1] + \
                [str(librest), str(libmod), "-rpath", str(scratch)] + [tail[-1]] + crt[2:]
            exe = [x for x in exe if x != "--as-needed"]
            sample("dynamic:exe (once)", exe, out, n=1)
            print(json.dumps(check_output(out, "dynamic")), flush=True)
            for i in range(a.samples):
                print(json.dumps(check_output(out, f"dynamic-startup-{i}")), flush=True)
        if "permodule" in variants:
            libdir = scratch / "mods"
            libdir.mkdir(exist_ok=True)
            by_mod = {}
            for o in objs:
                if len(obj_module[o]) == 1:
                    by_mod.setdefault(next(iter(obj_module[o])), []).append(o)
            libs = []
            t = time.perf_counter()
            for m, os_ in sorted(by_mod.items()):
                so = libdir / f"lib{m}.so"
                rec, _ = run(lib + ["-o", str(so)] + os_, f"permodule:{m}")
                if rec["rc"] != 0:
                    print(json.dumps(rec), flush=True)
                    return
                libs.append(str(so))
            print(json.dumps({"label": "permodule:all libs (once, serial)", "s": round(time.perf_counter() - t, 3), "libs": len(libs)}), flush=True)
            sample("permodule:one module relink (per edit)", lib + ["-o", str(libdir / f"lib{a.module}.so")] + by_mod[a.module])
            exe = head + crt[:2] + shared + ["--export-dynamic", "--whole-archive"] + [tail[0]] + ["--no-whole-archive"] + tail[1:-1] + \
                libs + ["-rpath", str(libdir)] + [tail[-1]] + crt[2:]
            exe = [x for x in exe if x != "--as-needed"]
            sample("permodule:exe (once)", exe, out, n=1)
            for i in range(a.samples):
                print(json.dumps(check_output(out, f"permodule-startup-{i}")), flush=True)


if __name__ == "__main__":
    main()
