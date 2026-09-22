#!/usr/bin/env python3
"""Build and qualify a matched QBE accounting matrix without measuring time."""
import hashlib
import json
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / "experiments/svg-gap-audit-20260921/codegen"
WORK = ROOT / ".tmp/svg-gap-audit-20260921/codegen"
COMPILER = ROOT / ".tmp/svg-gap-audit-20260921/mylang-audit-compiler"
ENTRY = ROOT / ".tmp/svg-arenas-20260921/guest-gc/main.my"
PROVIDER = ROOT / "src/schematic/native_schematic.c"
BASE = ROOT / ".tmp/full-svg-benchmark-20260921"
CASES = ("fixture", "changed-net", "changed-value")
DOCS = ("lib/modules/straps-synth-lmx2595.sexp",
        "lib/pinouts/lmx2595rhar.sexp", "lib/interfaces/spi.sexp")
POLICIES = {
    "none": ("--drop-step-checks", "--drop-frame-checks"),
    "step": ("--drop-frame-checks",),
    "frame": ("--drop-step-checks",),
    "both": (),
}

def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def env():
    result = dict(os.environ)
    for key in list(result):
        if key.startswith("MYLANG_QBE_LLVM_") or key in ("LD_PRELOAD",):
            del result[key]
    result["MYLANG_HOST_COMPILER"] = str(COMPILER)
    result["MYLANG_MEMORY_LIMIT"] = "268435456"
    return result

def build():
    OUT.mkdir(parents=True, exist_ok=True)
    WORK.mkdir(parents=True, exist_ok=True)
    records = {}
    for name, emit_policy in POLICIES.items():
        binary = WORK / f"gc-lto-{name}"
        emitted = WORK / f"emitted-{name}.json"
        emit_command = [str(COMPILER), "emit-project-qbe", str(ENTRY),
                        "--drop-debug", *emit_policy, "--no-cache"]
        emission = subprocess.run(emit_command, cwd=ROOT, env=env(), capture_output=True)
        if emission.returncode:
            raise RuntimeError(f"{name} emission failed: {emission.stderr.decode(errors='replace')}")
        emitted.write_bytes(emission.stdout)
        command = [str(COMPILER), "build", str(ENTRY), "--project",
                   "--provider", str(PROVIDER), "--backend", "llvm",
                   "--llvm-adapter", str(ROOT / "experiments/llvm-backend/qbe_llvm.py"),
                   "--zig", "/home/epentland/.local/bin/zig",
                   "--llvm-opt", "3", "--lto", "--keep-symbols",
                   f"--manifest-file={emitted}",
                   "--cache-dir", str(WORK / f"cache-{name}"), "--report",
                   "-o", str(binary)]
        result = subprocess.run(command, cwd=ROOT, env=env(), capture_output=True)
        (WORK / f"build-{name}.stdout").write_bytes(result.stdout)
        (WORK / f"build-{name}.stderr").write_bytes(result.stderr)
        if result.returncode:
            raise RuntimeError(f"{name} build failed: {result.stderr.decode(errors='replace')}")
        manifest = Path(str(binary) + ".qbe-manifest.json")
        records[name] = {
            "argv": command,
            "emit_argv": emit_command,
            "emitted_manifest_sha256": sha(emitted),
            "binary": str(binary.relative_to(ROOT)),
            "binary_sha256": sha(binary),
            "manifest_sha256": sha(manifest),
            "manifest": str(manifest.relative_to(ROOT)),
        }
    sources = [COMPILER, ENTRY, PROVIDER, ROOT / "src/qbe.zig",
               ROOT / "src/qbe_aggregate.zig", ROOT / "src/qbe_runtime.c",
               ROOT / "src/native_collections.c", ROOT / "src/native_heap.c"]
    evidence = {"compiler_sha256": sha(COMPILER),
                "sources": {str(p.relative_to(ROOT)): sha(p) for p in sources},
                "builds": records}
    (OUT / "accounting-builds.json").write_text(json.dumps(evidence, indent=2) + "\n")

def qualify():
    refs = json.loads((ROOT / "experiments/full-svg-benchmark/qualification.json").read_text())["cases"]
    evidence = {}
    for name in POLICIES:
        binary = WORK / f"gc-lto-{name}"
        rows = {}
        for case in CASES:
            project = BASE / "projects" / case
            output, issue = WORK / f"{name}-{case}.svg", WORK / f"{name}-{case}.issue"
            case_env = env()
            case_env.update(MYLANG_SCHEMATIC_DECLARED="io::circuit_input,io::pinout_input,io::interface_input,io::length,io::byte,io::put,io::issue",
                            MYLANG_SCHEMATIC_OUTPUT=str(output), MYLANG_SCHEMATIC_ISSUE=str(issue))
            case_env.update({f"MYLANG_SCHEMATIC_INPUT_{i}": str(project / path) for i, path in enumerate(DOCS)})
            results = []
            for stress in (False, True):
                output.write_bytes(b""); issue.write_bytes(b"")
                argv = [str(binary), "--print-result"] + (["--gc-stress"] if stress else [])
                run = subprocess.run(argv, cwd=ROOT, env=case_env, capture_output=True, timeout=90)
                expected = refs[case]["mylang-o3"]["svg_sha256"]
                ok = run.returncode == 0 and run.stdout == b"0\n" and run.stderr == b"" and issue.read_bytes() == b"" and sha(output) == expected
                if not ok:
                    raise RuntimeError(f"qualification failed: {name}/{case}/stress={stress}: {run}")
                results.append({"gc_stress": stress, "svg_sha256": sha(output), "svg_bytes": output.stat().st_size})
            rows[case] = results
        evidence[name] = {"binary_sha256": sha(binary), "cases": rows}
    (OUT / "accounting-qualification.json").write_text(json.dumps(evidence, indent=2) + "\n")

if __name__ == "__main__":
    build()
    qualify()
