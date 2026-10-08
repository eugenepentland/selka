#!/usr/bin/env python3
"""Record one command, wall time, affinities and concurrent heavy processes."""
import json, os, pathlib, subprocess, sys, time
root = pathlib.Path(__file__).resolve().parents[1]
label, *command = sys.argv[1:]
if command and command[0] == "--": command.pop(0)
start = time.monotonic()
heavy = subprocess.run(["ps", "-eo", "pid,comm,args"], capture_output=True, text=True).stdout
heavy = [line for line in heavy.splitlines() if any(x in line for x in ("zig build", "fuzz_matrix", "bench-newcore", "test-units", "core.test")) and "time-command.py" not in line]
admission_wait = 0.0
parent = os.getppid()
for _ in range(6):
    try:
        stat = pathlib.Path(f"/proc/{parent}/stat").read_text().rsplit(")", 1)[1].split()
        name = pathlib.Path(f"/proc/{parent}/comm").read_text().strip()
        if name == "flock": admission_wait = max(admission_wait, time.clock_gettime(time.CLOCK_BOOTTIME) - int(stat[19]) / os.sysconf("SC_CLK_TCK"))
        parent = int(stat[1])
    except (OSError, ValueError): break
record = {"admission_wait_seconds": round(admission_wait, 6), "command": command, "cwd": os.getcwd(), "affinity": sorted(os.sched_getaffinity(0)), "other_heavy_processes": heavy}
out = root / "logs" / (label + ".stdout")
err = root / "logs" / (label + ".stderr")
with out.open("wb") as stdout, err.open("wb") as stderr:
    process = subprocess.Popen(command, stdout=stdout, stderr=stderr)
    record["process_affinity"] = sorted(os.sched_getaffinity(process.pid))
    observed = set()
    while True:
        try:
            observed.add(tuple(sorted(os.sched_getaffinity(process.pid))))
            status = process.wait(timeout=0.2)
            break
        except subprocess.TimeoutExpired:
            pass
        except ProcessLookupError:
            status = process.wait()
            break
    record["observed_process_affinities"] = sorted(observed)
record.update(elapsed_seconds=round(time.monotonic()-start, 6), exit_code=status)
(root / "logs" / (label + ".json")).write_text(json.dumps(record, indent=2) + "\n")
print(out.read_text(), end="")
print(err.read_text(), end="", file=sys.stderr)
print(json.dumps({"label": label, "elapsed_seconds": record["elapsed_seconds"], "exit_code": status}), file=sys.stderr)
sys.exit(status)
