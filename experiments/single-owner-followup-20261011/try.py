#!/usr/bin/env python3
"""Run a migrated census or focused sample with the nested-cleanup prototype."""
import argparse
import os
from pathlib import Path
import shutil

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
COMPILER = ROOT / ".tmp/single-owner-followup-20261011/candidate/bin/mylang"

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--default", action="store_true")
parser.add_argument("source", help="sample name or path to a .my program")
parser.add_argument("arguments", nargs="*")
args = parser.parse_args()
name = args.source.removesuffix(".my") + ".my"
candidates = [Path(args.source), HERE / "migrated" / name,
              HERE.parent / "single-owner-20261010/samples" / name,
              HERE.parent / "rc-census-20261010/samples" / name]
source = next((path for path in candidates if path.is_file()), None)
if source is None:
    parser.error("source file or sample does not exist")
if not COMPILER.is_file():
    parser.error("build the prototype compiler first; see README.md")
environment = dict(os.environ)
if not environment.get("ZIG"):
    pinned = Path.home() / "zig-toolchains/0.17.0-dev.1683+5ceec001b/zig"
    environment["ZIG"] = str(pinned) if pinned.is_file() else (shutil.which("zig") or "zig")
argv = [str(COMPILER), "run", str(source.resolve())]
if not args.default:
    argv.append("--experimental-single-owner")
argv.extend(["--", *args.arguments])
os.chdir(ROOT)
os.execve(COMPILER, argv, environment)
