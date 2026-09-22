#!/usr/bin/env python3
"""Build matched algorithm control/probe binaries; never runs timed samples."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import subprocess

ROOT = Path(__file__).resolve().parents[3]
WORK = ROOT / ".tmp/svg-gap-audit-20260921/algorithm"
OUT = Path(__file__).resolve().parent
COMPILER = ROOT / ".tmp/svg-gap-audit-20260921/mylang-audit-compiler"
ADAPTER = ROOT / "experiments/llvm-backend/qbe_llvm.py"


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("arms", nargs="*", choices=("control", "indexed", "normalize"))
    requested = parser.parse_args().arms or ["control", "indexed", "normalize"]
    env = dict(os.environ)
    for key in list(env):
        if key.startswith("MYLANG_QBE_LLVM_") or key in ("LD_PRELOAD", "NETLISP_LIB_DIR", "NETLISP_STDLIB_DIR"):
            del env[key]
    env["MYLANG_MEMORY_LIMIT"] = "268435456"
    records = []
    for arm in requested:
        for mode, extra in (("lto", ("--lto",)), ("lto-bounded", ("--lto", "--step-accounting"))):
            name = f"{arm}-{mode}"
            target = WORK / name
            command = [str(COMPILER), "build", str(WORK / arm / "guest/main.my"),
                       "--project", "--provider", "src/schematic/native_schematic.c",
                       "--backend", "llvm", "--llvm-adapter", str(ADAPTER),
                       "--llvm-opt", "3", *extra, "--keep-symbols",
                       "--cache-dir", str(WORK / f"cache-{name}"), "--report", "-o", str(target)]
            result = subprocess.run(command, cwd=ROOT, env=env, capture_output=True, timeout=1200)
            (OUT / f"{name}-build.stdout").write_bytes(result.stdout)
            (OUT / f"{name}-build.stderr").write_bytes(result.stderr)
            if result.returncode:
                raise SystemExit(f"{name} failed: {result.stderr.decode(errors='replace')}")
            records.append({"name": name, "command": command, "binary": str(target.relative_to(ROOT)),
                            "binary_sha256": sha(target), "manifest_sha256": sha(str(target) + ".qbe-manifest.json")})
    sources = {}
    for arm in requested:
        for path in sorted((WORK / arm / "guest").glob("*.my")):
            sources[str(path.relative_to(ROOT))] = sha(path)
    evidence = {"compiler": str(COMPILER.relative_to(ROOT)), "compiler_sha256": sha(COMPILER),
                "llvm_adapter": str(ADAPTER.relative_to(ROOT)), "llvm_adapter_sha256": sha(ADAPTER),
                "sources": sources, "builds": records}
    filename = "builds.json" if len(requested) == 3 else "builds-" + "-".join(requested) + ".json"
    (OUT / filename).write_text(json.dumps(evidence, indent=2) + "\n")


if __name__ == "__main__":
    main()
