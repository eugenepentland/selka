#!/usr/bin/env python3
"""Retain tool-generation changes during runtime and number-object compilation.

Only a task-owned executable copy and its private adjacent library are changed.
The real Zig library is a read-only override. A failed native command must not
leave a new shared object under the identity captured before that change.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shlex
import shutil
import signal
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]


def compiling(cache, mode):
    for proc in Path("/proc").iterdir():
        if not proc.name.isdecimal():
            continue
        try:
            argv = (proc / "cmdline").read_bytes().split(b"\0")
        except OSError:
            continue
        if not any(str(cache).encode() in item for item in argv):
            continue
        marker = b"core_rt-" if mode == "runtime" else b"core_number_text.zig"
        operation = b"-c" if mode == "runtime" else b"build-obj"
        if operation in argv and any(marker in item and item.endswith(b".c" if mode == "runtime" else b".zig") for item in argv):
            return int(proc.name), [os.fsdecode(item) for item in argv if item]
    return None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--core", type=Path, required=True)
    parser.add_argument("--evidence", type=Path, required=True)
    parser.add_argument("--expect", choices=("defect", "refusal"), required=True)
    parser.add_argument("--reviewed-library", action="store_true", help="copy the complete reviewed library for the corrected initially reusable tool")
    args = parser.parse_args()
    area = args.evidence.resolve()
    if area.exists() or not area.is_relative_to(ROOT / "experiments"):
        parser.error("fresh evidence under experiments is required")
    area.mkdir(parents=True)
    cache = ROOT / ".mylang-cache/s4-m" / area.name
    if cache.exists():
        raise RuntimeError("fresh reducer cache is required")
    tools = cache / "tools"
    zig = Path(shutil.which("zig")).resolve()
    if args.reviewed_library:
        tools.mkdir(parents=True)
        shutil.copytree(zig.parent / "lib", tools / "lib", symlinks=True)
    else:
        (tools / "lib/std").mkdir(parents=True)
    private_zig = tools / "zig"
    shutil.copy2(zig, private_zig)
    library_input = tools / "lib/std/std.zig"
    environment = os.environ.copy()
    environment["ZIG_LIB_DIR"] = str(tools / "lib" if args.reviewed_library else zig.parent / "lib")
    original_library_input = library_input.read_text() if args.reviewed_library else "first\n"
    core = args.core.resolve()
    manifest = {"core": str(core), "sha256": hashlib.file_digest(core.open("rb"), "sha256").hexdigest(),
                "source_commit": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
                "zig": str(zig), "private_zig": str(private_zig), "qualified": False, "expect": args.expect, "trials": []}
    manifest["reviewed_library"] = args.reviewed_library
    manifest["production_sources"] = {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
                                      for path in sorted((ROOT / "src").rglob("*")) if path.is_file()}
    (area / "source.diff").write_bytes(subprocess.check_output(["git", "diff", "HEAD"], cwd=ROOT))
    for mode in ("runtime", "number"):
        library_input.write_text(original_library_input)
        trial_cache = cache / mode
        entry = area / f"{mode}.my"
        entry.write_text("def test_value() -> bool:\n    return " + ("str(1.25) == \"1.25\"\n" if mode == "number" else "True\n"))
        command = [str(ROOT / "scripts/build-slot.sh"), "build", str(core), "test", str(entry),
                   "--zig", str(private_zig), "--json", "--cache-dir", str(trial_cache)]
        (area / f"{mode}.command").write_text(shlex.join(command) + "\n")
        started = time.monotonic()
        trial = {"mode": mode, "mutated_during_compile": False}
        with (area / f"{mode}.stdout").open("w") as stdout, (area / f"{mode}.stderr").open("w") as stderr:
            child = subprocess.Popen(command, cwd=ROOT, env=environment, stdout=stdout, stderr=stderr, start_new_session=True)
            try:
                while child.poll() is None and time.monotonic() - started < 90:
                    active = compiling(trial_cache, mode)
                    if active:
                        trial["compile_process"] = {"pid": active[0], "argv": active[1]}
                        library_input.write_text(original_library_input + "\n// S4 private tool-generation reducer.\n" if args.reviewed_library else "other\n")
                        trial["mutated_during_compile"] = True
                        break
                    time.sleep(0.001)
                trial["status"] = child.wait(timeout=max(1, 90 - (time.monotonic() - started)))
            finally:
                if child.poll() is None:
                    os.killpg(child.pid, signal.SIGKILL)
                    child.wait()
        trial["seconds"] = time.monotonic() - started
        pattern = "core_rt-*.o" if mode == "runtime" else "core_number_text-*.o"
        objects = list(trial_cache.rglob(pattern))
        trial["published_objects"] = [str(path.relative_to(trial_cache)) for path in objects if "zig-local" not in path.relative_to(trial_cache).parts]
        trial["guest_private_objects"] = [str(path.relative_to(trial_cache)) for path in objects if "zig-local" in path.relative_to(trial_cache).parts]
        report = (area / f"{mode}.stdout").read_text() + (area / f"{mode}.stderr").read_text()
        trial["refused_tool_change"] = trial["status"] != 0 and ("toolchain changed" in report or "SourceChanged" in report)
        wanted_objects = bool(trial["published_objects"]) if args.expect == "defect" else not trial["published_objects"]
        trial["expected_observed"] = trial["mutated_during_compile"] and trial["refused_tool_change"] and wanted_objects
        manifest["trials"].append(trial)
        (area / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
        print(json.dumps(trial), flush=True)
    return 0 if all(trial["expected_observed"] for trial in manifest["trials"]) else 1


if __name__ == "__main__":
    raise SystemExit(main())
