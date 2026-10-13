#!/usr/bin/env python3
"""Wait for the frozen C1 scheduler, then collect separate counters and report."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[4]
EVIDENCE = Path(__file__).resolve().parent
RUN = ROOT / "experiments/lox-eda-parity-20261013"
ATTEMPT = RUN / "attempts/runtime-001"
RESUME = ATTEMPT / "windows/resume-001.json"
SCHEDULER_PID = 217780


def save(value):
    (EVIDENCE / "status.json").write_text(json.dumps(value, indent=2) + "\n")


def main():
    assert ROOT.name == "mylang-text-gaps-main-20261012"
    process = Path(f"/proc/{SCHEDULER_PID}/stat")
    start = process.read_text().split()[21]
    status = {"phase": "waiting for C1 runtime completion", "scheduler_pid": SCHEDULER_PID,
              "scheduler_start_ticks": start, "commands": [],
              "harness_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}
    save(status)
    while True:
        if RESUME.exists() and json.loads(RESUME.read_text()).get("complete"):
            break
        assert process.exists() and process.read_text().split()[21] == start, "scheduler exited before completion"
        time.sleep(10)
    assert len(list((ATTEMPT / "runtime").glob("*.chunk[0-9][0-9].json"))) == 780
    configuration = json.loads((ATTEMPT / "configuration.json").read_text())
    common = ["--root", str(ROOT), "--compiler", configuration["compiler"],
              "--install", configuration["installation"], "--attempt", "runtime-001",
              "--prior-root", configuration["prior_root"],
              "--lox-build", str(RUN / "attempts/native-001/build/lox/build-receipt.json"),
              "--eda-build", str(RUN / "attempts/native-001/build/eda/build-receipt.json")]
    commands = [(stage, [sys.executable, "-B", str(RUN / "pipeline.py"), stage, *common])
                for stage in ("count", "report")]
    commands.append(("summary", [sys.executable, "-B", str(RUN / "summarize.py"),
                                str(ATTEMPT / "parity-report.json"), str(ATTEMPT / "summary")]))
    for stage, command in commands:
        status["phase"] = stage
        entry = {"stage": stage, "command": command}
        status["commands"].append(entry)
        save(status)
        with (EVIDENCE / (stage + ".log")).open("x") as log:
            result = subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
        entry["returncode"] = result.returncode
        save(status)
        assert result.returncode == 0, (stage, result.returncode)
    status["phase"] = "complete"
    save(status)


if __name__ == "__main__":
    main()
