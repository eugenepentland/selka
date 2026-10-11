#!/usr/bin/env python3
"""Run one migrated sample with the zero-RC stage 1 compiler."""
import argparse
import os
from pathlib import Path
import shutil

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
COMPILER = ROOT / ".tmp/zero-rc-20261011/candidate/bin/mylang"
p = argparse.ArgumentParser(description=__doc__)
p.add_argument("source", help="census sample name or path to a program")
p.add_argument("arguments", nargs="*")
args = p.parse_args()
name = args.source.removesuffix(".my") + ".my"
paths = [Path(args.source), HERE / "migrated" / name,
         HERE.parent / "single-owner-followup-20261011/migrated" / name,
         HERE.parent / "rc-census-20261010/samples" / name]
source = next((path.resolve() for path in paths if path.is_file()), None)
if source is None or not COMPILER.is_file():
    p.error("source or prototype compiler missing; see README.md")
env = dict(os.environ)
pinned = Path.home() / "zig-toolchains/0.17.0-dev.1683+5ceec001b/zig"
env.setdefault("ZIG", str(pinned) if pinned.is_file() else (shutil.which("zig") or "zig"))
os.chdir(ROOT)
os.execve(COMPILER, [str(COMPILER), "run", str(source), "--experimental-zero-rc", "--", *args.arguments], env)
