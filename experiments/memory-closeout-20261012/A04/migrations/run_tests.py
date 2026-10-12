#!/usr/bin/env python3
"""Execute migrated guest assertions; preserve source-refused files as blockers."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
sys.path.insert(0, str(ROOT / "scripts"))
from build_admission import admission

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--compiler", type=Path, required=True)
parser.add_argument("--survey", type=Path, required=True)
parser.add_argument("--phase", required=True)
args = parser.parse_args()
report = HERE / (args.phase + ".json")
assert not report.exists(), "choose a new phase"
digest = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
survey = json.loads(args.survey.read_text())
result = {"compiler": str(args.compiler), "compiler_sha256": digest(args.compiler), "survey": str(args.survey),
          "rows": [], "admission": "at most two source files per shared build lease; each has ordinary and zero-RC guest-test execution"}
ready = []
for row in survey["rows"]:
    source = ROOT / row["source"]
    assert digest(source) == row["source_sha256"], "source changed since admission survey"
    names = re.findall(r"^public func (test_\w+)\(", source.read_text(), re.M)
    if row["status"]:
        result["rows"].append({"source": row["source"], "source_sha256": digest(source), "status": "source blocked", "diagnostic": row["stderr"], "public_tests": names})
    elif not names:
        result["rows"].append({"source": row["source"], "source_sha256": digest(source), "status": "helper tested through importer", "importer": "tests/lang/migrated/python_format.my", "public_tests": []})
    else:
        ready.append((row, names))
env = dict(os.environ, MYL_CORE_LEAKCHECK="1")
for first in range(0, len(ready), 2):
    with admission("build"):
        for row, names in ready[first:first + 2]:
            recorded = {"source": row["source"], "source_sha256": row["source_sha256"], "public_tests": names, "modes": {}}
            for mode, flags in (("ordinary", []), ("zero_rc", ["--experimental-zero-rc"])):
                command = [str(args.compiler), "test", str(ROOT / row["source"]), "--release", "--verify-facts", "--force", "--json", "--jobs", "1", *flags]
                ran = subprocess.run(command, cwd=ROOT, env=env, capture_output=True, text=True, timeout=600)
                recorded["modes"][mode] = {"command": command, "status": ran.returncode, "stdout": ran.stdout, "stderr": ran.stderr}
                print(row["source"], mode, ran.returncode, flush=True)
            result["rows"].append(recorded)
            assert result["compiler_sha256"] == digest(args.compiler), "compiler changed"
            report.write_text(json.dumps(result, indent=2) + "\n")
result["summary"] = {"assigned_files": len(survey["rows"]), "source_blocked": sum(row.get("status") == "source blocked" for row in result["rows"]),
                     "executed_files": len(ready), "executed_tests_per_mode": sum(len(names) for _, names in ready),
                     "failed_commands": sum(run["status"] != 0 for row in result["rows"] for run in row.get("modes", {}).values())}
report.write_text(json.dumps(result, indent=2) + "\n")
print(result["summary"], flush=True)
