#!/usr/bin/env python3
"""Grade one trial run directory against the hidden cases.

usage: grade.py RUN_DIR TASK   (TASK = wordfreq | calc | route | csvstats | lox)
Runs RUN_DIR/build.sh once (timed), then RUN_DIR/prog on every case.
"""
import json
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent


def main():
    run_dir, task = Path(sys.argv[1]).resolve(), sys.argv[2]
    result = {"run": run_dir.name, "task": task, "cases": {}}
    t0 = time.time()
    b = subprocess.run(["bash", "./build.sh"], cwd=run_dir, capture_output=True, text=True, timeout=900)
    result["build_s"] = round(time.time() - t0, 2)
    result["build_exit"] = b.returncode
    if b.returncode != 0 or not (run_dir / "prog").exists():
        result["build_err"] = (b.stdout + b.stderr)[-2000:]
        print(json.dumps(result, indent=1))
        return
    passed = 0
    cases = sorted((HERE / "cases" / task).iterdir())
    for cdir in cases:
        case = json.loads((cdir / "case.json").read_text())
        args = [a.replace("{dir}", str(cdir)) for a in case["args"]]
        t1 = time.time()
        try:
            p = subprocess.run([str(run_dir / "prog")] + args, cwd=run_dir, capture_output=True, timeout=case["limit_s"] * 3)
            dt = time.time() - t1
            out = p.stdout.decode("utf-8", "replace")
            err_first = p.stderr.decode("utf-8", "replace").split("\n")[0]
            problems = []
            if out != case["stdout"]:
                problems.append("stdout")
            if p.returncode != case["exit"]:
                problems.append(f"exit {p.returncode}!={case['exit']}")
            if case["stderr_first_line"] is not None and err_first != case["stderr_first_line"]:
                problems.append("stderr")
            if dt > case["limit_s"]:
                problems.append(f"slow {dt:.2f}s")
            ok = not problems
            detail = {"ok": ok, "s": round(dt, 3), "problems": problems}
            if not ok:
                detail["got_stdout"] = out[:300]
                detail["want_stdout"] = case["stdout"][:300]
                detail["got_stderr"] = err_first[:200]
                detail["want_stderr"] = case["stderr_first_line"]
        except subprocess.TimeoutExpired:
            detail = {"ok": False, "problems": ["timeout"]}
            ok = False
        passed += ok
        result["cases"][cdir.name] = detail
    result["passed"] = passed
    result["total"] = len(cases)
    print(json.dumps(result, indent=1))


if __name__ == "__main__":
    main()
