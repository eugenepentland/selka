#!/usr/bin/env python3
"""Reproduce the qualified, semantics-preserving 112-byte list-copy probe.

Requires accounting_matrix.py to have produced the frozen `none` control.
The script copies that cache, changes one runtime-source line, and asks the same
compiler/link path to rebuild. It deliberately refuses an existing probe cache.
"""
import hashlib, json, os, shutil, subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
WORK = ROOT / ".tmp/svg-gap-audit-20260921/codegen"
OUT = ROOT / "experiments/svg-gap-audit-20260921/codegen"
COMPILER = ROOT / ".tmp/svg-gap-audit-20260921/mylang-audit-compiler"
ENTRY = ROOT / ".tmp/svg-arenas-20260921/guest-gc/main.my"
CONTROL_CACHE, PROBE_CACHE = WORK / "cache-none", WORK / "cache-copy112-reproduced"
MANIFEST = WORK / "emitted-none.json"
CONTROL, PROBE = WORK / "gc-lto-none", WORK / "gc-lto-copy112-reproduced"
OLD = "    case 64: memcpy(destination,source,64); return;\n    default: memcpy(destination,source,size); return;"
NEW = "    case 64: memcpy(destination,source,64); return;\n    case 112: memcpy(destination,source,112); return;\n    default: memcpy(destination,source,size); return;"

def sha(path): return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def object_hashes(manifest):
    doc = json.loads(Path(manifest).read_text())
    return {row["symbol"]: sha(row["object"]) for row in doc["functions"]}

if PROBE_CACHE.exists() or PROBE.exists():
    raise SystemExit("refusing existing reproduced probe artifacts")
shutil.copytree(CONTROL_CACHE, PROBE_CACHE)
sources = list((PROBE_CACHE / "runtime").glob("*/native_collections.c"))
assert len(sources) == 1
text = sources[0].read_text()
assert text.count(OLD) == 1 and "case 112:" not in text
sources[0].write_text(text.replace(OLD, NEW))

command = [str(COMPILER), "build", str(ENTRY), "--project", "--provider",
           "src/schematic/native_schematic.c", "--backend", "llvm",
           "--llvm-adapter", str(ROOT / "experiments/llvm-backend/qbe_llvm.py"),
           "--zig", "/home/epentland/.local/bin/zig", "--llvm-opt", "3", "--lto",
           "--keep-symbols", f"--manifest-file={MANIFEST}", "--cache-dir",
           str(PROBE_CACHE), "--report", "-o", str(PROBE)]
env = dict(os.environ, MYLANG_HOST_COMPILER=str(COMPILER), MYLANG_MEMORY_LIMIT="268435456")
result = subprocess.run(command, cwd=ROOT, env=env, capture_output=True)
(WORK / "copy112-reproduced-build.stdout").write_bytes(result.stdout)
(WORK / "copy112-reproduced-build.stderr").write_bytes(result.stderr)
if result.returncode: raise SystemExit(result.returncode)

control_objects = object_hashes(Path(str(CONTROL) + ".qbe-manifest.json"))
probe_objects = object_hashes(Path(str(PROBE) + ".qbe-manifest.json"))
assert control_objects == probe_objects, "guest objects changed"
evidence = {"command": command, "compiler_sha256": sha(COMPILER),
            "emitted_manifest_sha256": sha(MANIFEST),
            "control_binary_sha256": sha(CONTROL), "probe_binary_sha256": sha(PROBE),
            "control_and_probe_guest_objects_identical": True,
            "native_collections_before_sha256": sha(next((CONTROL_CACHE / "runtime").glob("*/native_collections.c"))),
            "native_collections_after_sha256": sha(sources[0]),
            "only_intended_source_delta": "+    case 112: memcpy(destination,source,112); return;"}
(OUT / "copy112-reproduced-build.json").write_text(json.dumps(evidence, indent=2) + "\n")
