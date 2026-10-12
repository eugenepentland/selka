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
parser.add_argument("--resume", action="store_true")
args = parser.parse_args()
report = HERE / (args.phase + ".json")
digest = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
survey = json.loads(args.survey.read_text())
result = {"compiler": str(args.compiler), "compiler_sha256": digest(args.compiler), "survey": str(args.survey),
          "rows": [], "admission": "at most two source files per shared build lease; each has ordinary and zero-RC guest-test execution"}
if report.exists():
    assert args.resume, "choose a new phase or --resume"
    previous = json.loads(report.read_text())
    assert 'summary' not in previous, 'completed evidence is immutable; choose a new phase'
    assert all(previous[key] == result[key] for key in ('compiler', 'compiler_sha256', 'survey')), "resume identity changed"
    result = previous
recorded_sources = {row['source']: row for row in result['rows']}
ready = []
total_ready = []
for row in survey["rows"]:
    source = ROOT / row["source"]
    assert digest(source) == row["source_sha256"], "source changed since admission survey"
    names = re.findall(r"^public func (test_\w+)\(", source.read_text(), re.M)
    if not row['status'] and names:
        total_ready.append((row, names))
    if row['source'] in recorded_sources:
        assert recorded_sources[row['source']]['source_sha256'] == digest(source), "recorded source changed"
        continue
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
                counts = json.loads(ran.stdout) if ran.stdout.startswith('{') else {}
                executed_names = {test['name'].rsplit('::', 1)[-1] for test in counts.get('tests', [])}
                qualified = ran.returncode == 0 and not ran.stderr and counts.get('passed') == len(names) and counts.get('failed') == 0 and counts.get('unsupported') == 0 and executed_names == set(names)
                recorded["modes"][mode] = {"command": command, "status": ran.returncode, "stdout": ran.stdout, "stderr": ran.stderr,
                                            "qualified": qualified, 'passed': counts.get('passed'), 'failed': counts.get('failed'), 'unsupported': counts.get('unsupported')}
                print(row["source"], mode, ran.returncode, 'qualified' if qualified else 'FAILED QUALIFICATION', flush=True)
            result["rows"].append(recorded)
            assert result["compiler_sha256"] == digest(args.compiler), "compiler changed"
            report.write_text(json.dumps(result, indent=2) + "\n")
result["summary"] = {"assigned_files": len(survey["rows"]), "source_blocked": sum(row.get("status") == "source blocked" for row in result["rows"]),
                     "executed_files": len(total_ready), "executed_tests_per_mode": sum(len(names) for _, names in total_ready),
                     "failed_commands": sum(run["status"] != 0 for row in result["rows"] for run in row.get("modes", {}).values())}
result['summary']['execution_totals'] = {}
for mode in ('ordinary', 'zero_rc'):
    totals = dict(passed=0, failed=0, unsupported=0)
    for row in result['rows']:
        if mode not in row.get('modes', {}):
            continue
        data = json.loads(row['modes'][mode]['stdout'])
        for key in totals:
            totals[key] += data[key]
    result['summary']['execution_totals'][mode] = totals
report.write_text(json.dumps(result, indent=2) + "\n")
print(result["summary"], flush=True)
raise SystemExit(int(any(total['failed'] or total['unsupported'] for total in result['summary']['execution_totals'].values()) or bool(result['summary']['source_blocked'])))
