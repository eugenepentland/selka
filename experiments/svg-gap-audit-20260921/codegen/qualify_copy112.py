#!/usr/bin/env python3
"""Qualify the private constant-size copy probe; this records no timings."""
import hashlib, json, os, subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
WORK = ROOT / ".tmp/svg-gap-audit-20260921/codegen"
BINARY = WORK / "gc-lto-copy112"
BASE = ROOT / ".tmp/full-svg-benchmark-20260921"
DOCS = ("lib/modules/straps-synth-lmx2595.sexp", "lib/pinouts/lmx2595rhar.sexp", "lib/interfaces/spi.sexp")

def sha(path): return hashlib.sha256(Path(path).read_bytes()).hexdigest()

refs = json.loads((ROOT / "experiments/full-svg-benchmark/qualification.json").read_text())["cases"]
rows = {}
for case in ("fixture", "changed-net", "changed-value"):
    project, runs = BASE / "projects" / case, []
    output, issue = WORK / f"copy112-{case}.svg", WORK / f"copy112-{case}.issue"
    env = dict(os.environ)
    env.update(MYLANG_MEMORY_LIMIT="268435456",
               MYLANG_SCHEMATIC_DECLARED="io::circuit_input,io::pinout_input,io::interface_input,io::length,io::byte,io::put,io::issue",
               MYLANG_SCHEMATIC_OUTPUT=str(output), MYLANG_SCHEMATIC_ISSUE=str(issue))
    env.update({f"MYLANG_SCHEMATIC_INPUT_{i}": str(project / path) for i, path in enumerate(DOCS)})
    for stress in (False, True):
        output.write_bytes(b""); issue.write_bytes(b"")
        result = subprocess.run([str(BINARY), "--print-result"] + (["--gc-stress"] if stress else []), cwd=ROOT, env=env, capture_output=True, timeout=90)
        expected = refs[case]["mylang-o3"]["svg_sha256"]
        assert result.returncode == 0 and result.stdout == b"0\n" and result.stderr == b"" and issue.read_bytes() == b"" and sha(output) == expected
        runs.append({"gc_stress": stress, "svg_sha256": sha(output), "svg_bytes": output.stat().st_size})
    rows[case] = runs
evidence = {"binary_sha256": sha(BINARY), "cases": rows,
            "contract": "Semantics-preserving runtime probe: preserves list bounds check, error return, and copy size; adds a constant memcpy arm only when the runtime element descriptor reports exactly 112 bytes.",
            "patched_runtime_source_sha256": sha(next((WORK / "cache-copy112/runtime").glob("*/native_collections.c"))),
            "runtime_archive_sha256": sha(json.loads(Path(str(BINARY) + ".qbe-manifest.json").read_text())["runtime_object"])}
(ROOT / "experiments/svg-gap-audit-20260921/codegen/copy112-qualification.json").write_text(json.dumps(evidence, indent=2) + "\n")
