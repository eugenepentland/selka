#!/usr/bin/env python3
"""Run under shared build admission; results never write historical evidence."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

p = argparse.ArgumentParser()
p.add_argument("--compiler", type=Path, required=True)
p.add_argument("--output", type=Path, required=True)
p.add_argument("--scratch", type=Path, required=True)
p.add_argument("--default", action="store_true")
p.add_argument("--start", type=int, default=0)
p.add_argument("--limit", type=int, default=1000)
a = p.parse_args()
compiler = a.compiler.resolve()
compiler_hash = hashlib.sha256(compiler.read_bytes()).hexdigest()
root = Path(__file__).resolve().parent
scratch = a.scratch.resolve()
scratch.mkdir(parents=True, exist_ok=True)
env = dict(os.environ, MYL_CORE_LEAKCHECK="1")
flag = [] if a.default else ["--experimental-zero-rc"]
rows = []
case_index = 0
def run(name, args, expected=0, owned=True, extra=None):
    global case_index
    index = case_index
    case_index += 1
    if not a.start <= index < a.start + a.limit:
        return subprocess.CompletedProcess([], 255, "", "")
    cmd = [str(compiler)] + args + (["--seed", "7"] if args[0] == "test" else []) + (flag if owned else [])
    result = subprocess.run(cmd, capture_output=True, text=True, env=dict(env, **(extra or {})))
    if hashlib.sha256(compiler.read_bytes()).hexdigest() != compiler_hash:
        raise RuntimeError("compiler changed during qualification")
    passed = result.returncode == expected
    if args[0] == "test" and expected == 0 and result.returncode == 0:
        report = json.loads(result.stdout)
        count = 6 if name.startswith("directory") else (1 if name == "invalid-rc-control" else 3)
        passed = passed and report.get("passed", 0) + report.get("cached", 0) == count
        passed = passed and report.get("unsupported", 0) == 0 and report.get("failed", 0) == 0
    if name in {"check-library-invalid", "invalid-cold", "invalid-repeat"}:
        passed = passed and "E_SINGLE_OWNER_MOVED" in result.stderr
    if name in {"run", "run-project"}:
        passed = passed and result.stdout == "value-7\n"
    scope = 'diagnostic-core' if args[0] == 'dump-ir' else 'source-admission' if args[0] == 'check' else 'executable-emission' if args[0] == 'build' else 'guest-execution-or-receipt'
    rows.append(dict(name=name, qualification_scope=scope, argv=cmd, expected=expected, status=result.returncode,
                     passed=passed, stdout=result.stdout, stderr=result.stderr))
    return result
source = str(root / "fixtures/guest_tests.my")
invalid = str(root / "fixtures/invalid_move.my")
cache = str(scratch / "cache")
for name, mode in [("debug", ["--unoptimized"]), ("release", ["--release"]),
                   ("verified-release", ["--release", "--verify-facts"]),
                   ("optimized-debug", ["--optimize-debug"]), ("release-no-facts", ["--release", "--no-facts"])]:
    run("test-" + name, ["test", source, "--json", "--force", "--property-runs", "5", "--cache-dir", cache] + mode)
run("test-cold", ["test", source, "--json", "--cache-dir", cache], extra={"MYL_CORE_LEAKCHECK": "0"})
warm = run("test-warm", ["test", source, "--json", "--cache-dir", cache], extra={"MYL_CORE_LEAKCHECK": "0"})
if warm.returncode == 0:
    report = json.loads(warm.stdout)
    rows[-1]["passed"] = report.get("cached", 0) == 3
for planner in ["reference", "shadow"]:
    run("test-planner-" + planner, ["test", source, "--json", "--force", "--property-runs", "5", "--cache-dir", cache], extra={"MYLANG_CACHE_PLAN_MODE": planner})
run("check-library", ["check", str(root / "fixtures/library.my"), "--cache-dir", cache, "--report", "--diagnostics=json"])
run("check-library-invalid", ["check", str(root / "fixtures/invalid_library.my"), "--cache-dir", cache, "--diagnostics=json"], expected=1)
run("check", ["check", source, "--cache-dir", cache])
run("dump-ir", ["dump-ir", source])
run("build", ["build", source, "-o", str(scratch / "guest"), "--cache-dir", cache])
run("run", ["run", source, "--cache-dir", cache])
run("run-project", ["run-project", source, "--cache-dir", cache])
run("result-ok", ["run", str(root / "fixtures/result_ok.my"), "--cache-dir", cache])
run("result-error", ["run", str(root / "fixtures/result_error.my"), "--cache-dir", cache], expected=1)
# A previous successful ordinary receipt may never bypass the source ownership check.
if not a.default:
    run("invalid-rc-control", ["test", invalid, "--json", "--cache-dir", cache], owned=False, extra={"MYL_CORE_LEAKCHECK": "0"})
run("invalid-cold", ["test", invalid, "--json", "--cache-dir", cache], expected=1, extra={"MYL_CORE_LEAKCHECK": "0"})
run("invalid-repeat", ["test", invalid, "--json", "--cache-dir", cache], expected=1, extra={"MYL_CORE_LEAKCHECK": "0"})
suite = scratch / "suite"
suite.mkdir(exist_ok=True)
for retired in ["alpha.my", "beta.my"]:
    (suite / retired).unlink(missing_ok=True)
for name in ["alpha_test", "beta_test"]:
    (suite / (name + ".my")).write_text(Path(source).read_text())
run("directory", ["test", str(suite), "--json", "--cache-dir", cache, "--property-runs", "5"])
run("directory-children", ["test", str(suite), "--json", "--cache-dir", cache, "--force", "--property-runs", "5"], extra={"MYLANG_TEST_CHILDREN": "1"})
result = dict(compiler=str(compiler), compiler_sha256=compiler_hash, start=a.start, complete_matrix_cases=case_index,
              sources={str(x.relative_to(root)):hashlib.sha256(x.read_bytes()).hexdigest() for x in sorted((root / "fixtures").glob("*.my"))},
              default=a.default, results=rows, success=bool(rows) and all(row["passed"] for row in rows))
a.output.parent.mkdir(parents=True, exist_ok=True)
a.output.write_text(json.dumps(result, indent=2) + "\n")
for row in rows:
    print(row["name"], row["status"], "PASS" if row["passed"] else "FAIL", flush=True)
raise SystemExit(0 if result["success"] else 1)
