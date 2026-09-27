#!/usr/bin/env python3
"""Verify the frozen combined gate archive without rebuilding or rerunning it."""
import argparse
import gzip
import hashlib
import json
import re
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--live", action="store_true")
args = parser.parse_args()
root = Path(__file__).resolve().parent
identity = json.loads((root / "identity.json").read_text())
for name, expected in identity["artifacts"].items():
    assert hashlib.sha256((root / name).read_bytes()).hexdigest() == expected, name
for step, result in identity["commands"].items():
    text = gzip.decompress((root / (step + ".log.gz")).read_bytes()).decode()
    assert result["exit_code"] == 0
    assert re.findall(r"^Build Summary:.*$", text, re.M) == [result["summary"]]
    assert "failed" not in result["summary"]
assert gzip.decompress((root / "gate-status.log.gz").read_bytes()).decode().splitlines() == [
    "test 0", "test-qbe 0", "test-qbe-build 0", "fmt-check 0"
]
assert gzip.decompress((root / "sweep-status.log.gz").read_bytes()).decode().splitlines() == ["qbe 0", "llvm 0"]
for backend in ("qbe", "llvm"):
    result = json.loads(gzip.decompress((root / ("sweep-" + backend + ".json.gz")).read_bytes()))
    assert {key: value for key, value in result.items() if key != "tests"} == identity["sweeps"][backend]
    assert result["passed"] == result["executed"] == 1049 and result["programs"] == 179
    assert all(result[key] == 0 for key in ("failed", "skipped", "cached", "dropped", "unloaded"))
assert "88 check(s) passed" in gzip.decompress((root / "guardian.log.gz").read_bytes()).decode()
assert identity["guardian_checks"] == 88 and identity["compiler_mode"] == "Debug"
failure = json.loads(gzip.decompress((root / "failed-cache-explanation.json.gz").read_bytes()))
assert failure == identity["prior_install_failure"] and failure["exit_code"] == 1
assert failure["source"] == identity["source_commit"]
assert "3 failed" in gzip.decompress((root / "failed-cache-install.log.gz").read_bytes()).decode()
if args.live:
    compiler = root.parent.parent / identity["compiler_path"]
    assert hashlib.sha256(compiler.read_bytes()).hexdigest() == identity["compiler_sha256"]
print("PASS: four gate commands, Guardian88, both uncached 1049-assertion/179-program RC sweeps, archive hashes" + (", live compiler" if args.live else ""))
