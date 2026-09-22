#!/usr/bin/env python3
"""Byte/behavior qualification for matched algorithm control and probe."""
from pathlib import Path
import hashlib
import importlib.util
import json
import os
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
OUT = Path(__file__).resolve().parent
WORK = ROOT / ".tmp/svg-gap-audit-20260921/algorithm"
BASE = ROOT / ".tmp/full-svg-benchmark-20260921"
DOCS = ("lib/modules/straps-synth-lmx2595.sexp", "lib/pinouts/lmx2595rhar.sexp", "lib/interfaces/spi.sexp")
sys.path.insert(0, str(ROOT / "experiments/svg-arenas-20260921"))
import qualify_variants


def sha(data):
    return hashlib.sha256(data).hexdigest()


def env_for(project, output, issue):
    env = dict(os.environ)
    for key in list(env):
        if key.startswith("MYLANG_QBE_LLVM_") or key in ("LD_PRELOAD", "NETLISP_LIB_DIR", "NETLISP_STDLIB_DIR"):
            del env[key]
    env.update(MYLANG_MEMORY_LIMIT="268435456",
               MYLANG_SCHEMATIC_DECLARED="io::circuit_input,io::pinout_input,io::interface_input,io::length,io::byte,io::put,io::issue",
               MYLANG_SCHEMATIC_OUTPUT=str(output), MYLANG_SCHEMATIC_ISSUE=str(issue))
    env.update({f"MYLANG_SCHEMATIC_INPUT_{i}": str(project / path) for i, path in enumerate(DOCS)})
    return env


def invoke(name, project, stress=False, extra=()):
    output, issue = WORK / "qualify.svg", WORK / "qualify.issue"
    output.write_bytes(b""); issue.write_bytes(b"")
    args = [str(WORK / name), "--print-result"]
    if name.endswith("bounded") and not any(arg.startswith("--max-steps=") for arg in extra):
        args += ["--max-steps=100000000"]
    if stress:
        args += ["--gc-stress"]
    args += list(extra)
    result = subprocess.run(args, cwd=ROOT, env=env_for(project, output, issue), capture_output=True, timeout=90)
    return result.returncode, result.stdout, result.stderr, output.read_bytes(), issue.read_bytes()


def main():
    evidence = {"standard": {}, "variants": {}}
    for case in ("fixture", "changed-net", "changed-value"):
        project = BASE / "projects" / case
        expected = invoke("control-lto", project)
        assert expected[0] == 0 and expected[4] == b"", (case, expected[:3], expected[4])
        for name in ("control-lto-bounded", "indexed-lto", "indexed-lto-bounded", "normalize-lto", "normalize-lto-bounded"):
            assert invoke(name, project) == expected, (case, name)
            assert invoke(name, project, True) == expected, (case, name, "stress")
        evidence["standard"][case] = {"svg_sha256": sha(expected[3]), "bytes": len(expected[3]), "all_match": True}
    fixture = BASE / "projects/fixture"
    for case, text in qualify_variants.variants().items():
        project = WORK / f"variant-project-{case}"
        project.mkdir(exist_ok=True)
        for path in DOCS[1:]:
            target = project / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes((fixture / path).read_bytes())
        circuit = project / DOCS[0]
        circuit.parent.mkdir(parents=True, exist_ok=True)
        circuit.write_text(text)
        expected = invoke("control-lto", project)
        assert expected[0] == (13 if case == "empty_net_rejected" else 0), (case, expected[:3], expected[4])
        for name in ("control-lto-bounded", "indexed-lto", "indexed-lto-bounded", "normalize-lto", "normalize-lto-bounded"):
            assert invoke(name, project) == expected, (case, name)
            assert invoke(name, project, True) == expected, (case, name, "stress")
        evidence["variants"][case] = {"status": expected[0], "svg_sha256": sha(expected[3]), "all_match": True}
    # Bounded mode still rejects both independent budgets.
    project = BASE / "projects/fixture"
    for name in ("control-lto-bounded", "indexed-lto-bounded", "normalize-lto-bounded"):
        for flag, marker in (("--max-steps=1", b"R_STEP_LIMIT"), ("--max-frames=1", b"R_FRAME_LIMIT")):
            result = invoke(name, project, extra=(flag,))
            assert result[0] != 0 and marker in result[2], (name, flag, result[:3])
    (OUT / "qualification.json").write_text(json.dumps(evidence, indent=2) + "\n")


if __name__ == "__main__":
    main()
