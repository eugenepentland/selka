#!/usr/bin/env python3
"""Qualify checked aggregate-inline probes without collecting timings."""
import hashlib, json, os, subprocess
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
WORK = ROOT / ".tmp/svg-gap-audit-20260921/codegen"
BASE = ROOT / ".tmp/full-svg-benchmark-20260921"
DOCS = ("lib/modules/straps-synth-lmx2595.sexp", "lib/pinouts/lmx2595rhar.sexp", "lib/interfaces/spi.sexp")
def sha(path): return hashlib.sha256(Path(path).read_bytes()).hexdigest()
refs = json.loads((ROOT / "experiments/full-svg-benchmark/qualification.json").read_text())["cases"]
evidence = {}
for accounting in ("none", "both"):
    binary, cases = WORK / f"gc-lto-{accounting}-aggregate-inline", {}
    for case in ("fixture", "changed-net", "changed-value"):
        project, runs = BASE / "projects" / case, []
        output, issue = WORK / f"aggregate-inline-{accounting}-{case}.svg", WORK / f"aggregate-inline-{accounting}-{case}.issue"
        env = dict(os.environ, MYLANG_MEMORY_LIMIT="268435456",
                   MYLANG_SCHEMATIC_DECLARED="io::circuit_input,io::pinout_input,io::interface_input,io::length,io::byte,io::put,io::issue",
                   MYLANG_SCHEMATIC_OUTPUT=str(output), MYLANG_SCHEMATIC_ISSUE=str(issue))
        env.update({f"MYLANG_SCHEMATIC_INPUT_{i}": str(project / path) for i, path in enumerate(DOCS)})
        for stress in (False, True):
            output.write_bytes(b""); issue.write_bytes(b"")
            argv = [str(binary), "--print-result"] + (["--gc-stress"] if stress else [])
            result = subprocess.run(argv, cwd=ROOT, env=env, capture_output=True, timeout=90)
            expected = refs[case]["mylang-o3"]["svg_sha256"]
            assert result.returncode == 0 and result.stdout == b"0\n" and result.stderr == b"" and issue.read_bytes() == b"" and sha(output) == expected
            runs.append({"gc_stress": stress, "svg_sha256": sha(output), "svg_bytes": output.stat().st_size})
        cases[case] = runs
    evidence[accounting] = {"binary_sha256": sha(binary), "cases": cases}
(ROOT / "experiments/svg-gap-audit-20260921/codegen/aggregate-inline-qualification.json").write_text(json.dumps(evidence, indent=2) + "\n")
