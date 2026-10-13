#!/usr/bin/env python3
"""Resume inspected, paused timing windows using the original frozen measurer."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys

import windowed_schedule as schedule


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--attempt", required=True)
    parser.add_argument("--freeze", type=Path, required=True)
    parser.add_argument("--pause", type=Path, required=True)
    parser.add_argument("--resume-id", required=True)
    parser.add_argument("--inspect", action="store_true")
    args = parser.parse_args()
    args.root = args.root.resolve()
    assert args.root == schedule.HERE.parent.parent
    args.freeze = args.freeze.resolve()
    destination = schedule.HERE / "attempts" / args.attempt
    schedule.validate_pins(destination, args.freeze)
    orchestration = destination / "windows/orchestrator.json"
    original = json.loads(orchestration.read_text())
    assert original["harness_sha256"] == schedule.sha(Path(schedule.__file__).resolve())
    pause = json.loads(args.pause.read_text())
    assert pause["wrapper_exited"] and not pause["foreign_jobs_signaled"]
    paused_window = destination / "windows" / pause["queued_window"]
    assert not (paused_window / "progress.json").exists()
    assert not (paused_window / "result.json").exists()
    assert "timing slot 1," not in (paused_window / "admission.log").read_text()
    completed = len(list((destination / "runtime").glob("*.chunk[0-9][0-9].json")))
    assert completed == pause["completed_chunks"], "inspect newer receipts before resuming"
    remaining = schedule.pending(destination)
    index = max(int(p.name) for p in (destination / "windows").iterdir() if p.is_dir() and p.name.isdigit()) + 1
    print(json.dumps({"completed_chunks": completed, "remaining_chunks": len(remaining), "next_window": index}), flush=True)
    if args.inspect:
        return
    assert os.environ.get("MYLANG_SLOT_DIR"), "source shared development environment"
    receipt = destination / "windows" / (args.resume_id + ".json")
    assert not receipt.exists(), "inspect previous resume before restarting"
    evidence = {"harness_sha256": schedule.sha(Path(__file__)), "original_orchestrator_sha256": schedule.sha(orchestration),
                "pause_receipt": str(args.pause.resolve()), "pause_sha256": schedule.sha(args.pause),
                "completed_chunks_at_resume": completed, "windows": []}
    schedule.save(receipt, evidence)
    while schedule.pending(destination):
        folder = destination / "windows" / f"{index:03d}"
        folder.mkdir(exist_ok=False)
        command = [str(args.root / "scripts/build-slot.sh"), "timing", sys.executable, "-B", schedule.__file__,
                   "--root", str(args.root), "--attempt", args.attempt, "--freeze", str(args.freeze),
                   "--cpu", "8", "--window-seconds", str(original["window_seconds"]), "--admitted", str(index)]
        schedule.save(folder / "command.json", command)
        with (folder / "admission.log").open("x") as log:
            result = subprocess.run(command, cwd=args.root, stdout=log, stderr=subprocess.STDOUT)
        evidence["windows"].append({"index": index, "returncode": result.returncode})
        schedule.save(receipt, evidence)
        assert result.returncode == 0 and (folder / "result.json").exists(), ("window failed", index)
        index += 1
    schedule.validate_pins(destination, args.freeze)
    evidence["complete"] = True
    schedule.save(receipt, evidence)


if __name__ == "__main__":
    main()
