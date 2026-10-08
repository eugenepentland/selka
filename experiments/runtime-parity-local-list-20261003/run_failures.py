"""Compare exact public trap/refusal order against a supplied frozen compiler."""
import argparse
import json
import os
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument("--compiler", type=Path, required=True)
parser.add_argument("--baseline", type=Path, required=True)
parser.add_argument("--qbe", type=Path, required=True)
parser.add_argument("--baseline-qbe", type=Path, required=True)
parser.add_argument("--output", type=Path, required=True)
parser.add_argument("--host-mode", choices=("Debug", "ReleaseFast"), required=True)
options = parser.parse_args()
options.output.mkdir(parents=True, exist_ok=True)
guest_environment = dict(os.environ)
guest_environment.pop("MYLANG_OPTIONS", None)
guest_environment.pop("MYLANG_MEMORY_LIMIT", None)


def environment(arguments):
    result = dict(guest_environment)
    result["MYLANG_OPTIONS"] = " ".join(argument for argument in arguments if not argument.startswith("--max-memory="))
    for argument in arguments:
        if argument.startswith("--max-memory="):
            result["MYLANG_MEMORY_LIMIT"] = argument.split("=", 1)[1]
    return result

body = """def closed(value: int, index: int) -> int:
    values = [value, value + 1, value + 2]
    alias = values
    return alias[index] + values[1] + alias[-1] + len(values)


def main() -> int:
    assert closed(12, 0) == 42
    return FINAL
"""
checked = 0
receipts = []
mode_receipts = []
triggered = {backend: set() for backend in ("qbe", "llvm")}
for backend, mode in (("qbe", "Debug"), ("llvm", "Debug"), ("qbe", "ReleaseFast"), ("llvm", "ReleaseFast")):
    for name, final in (
        ("success", "0"), ("overflow", "closed(9223372036854775807, 0)"),
        ("bounds", "closed(13, 3)"), ("negative", "closed(13, -4)"),
    ):
        source = options.output / f"{name}.my"
        source.write_text(body.replace("FINAL", final))
        programs = []
        for lane, compiler, qbe in (
            ("baseline", options.baseline, options.baseline_qbe),
            ("candidate", options.compiler, options.qbe),
        ):
            executable = options.output / f"{lane}-{backend}-{mode}-{name}"
            subprocess.run([
                str(compiler), "build", str(source), "--mode", mode, "--qbe", str(qbe),
                "--backend", backend, "--keep-symbols", f"--cache-dir={options.output / (lane + '-cache-' + backend + '-' + mode)}",
                "-o", str(executable),
            ], check=True)
            manifest = json.loads(Path(f"{executable}.qbe-manifest.json").read_text())
            assert manifest["backend"] == backend, manifest["backend"]
            mode_probe = subprocess.run([str(executable)], capture_output=True, env=environment(("--max-steps=1",)))
            expected = b"R_STEP_LIMIT" if mode == "Debug" else b"R_NO_STEP_ACCOUNTING"
            assert expected in mode_probe.stderr, (mode, mode_probe.stderr)
            mode_receipts.append({"backend": manifest["backend"], "guest_mode": mode, "lane": lane,
                                  "case": name, "mode_probe": expected.decode(),
                                  "manifest": str(Path(f"{executable}.qbe-manifest.json"))})
            programs.append(executable)
        trials = [()]
        if mode == "Debug":
            trials += [("--max-frames=1",), ("--max-frames=2",)]
            trials += [(f"--max-steps={steps}",) for steps in (1, 20, 60, 100, 150, 200)]
            trials += [(f"--max-memory={memory}",) for memory in (4096, 32768, 65536, 131072, 262144, 524288, 1048576)]
        for arguments in trials:
            results = [subprocess.run([str(executable)], capture_output=True, env=environment(arguments)) for executable in programs]
            actual = [(result.returncode, result.stdout, result.stderr) for result in results]
            if actual[0] != actual[1]:
                raise AssertionError((backend, mode, name, arguments, actual))
            if not arguments:
                expected = {"success": b"", "overflow": b"R_OVERFLOW", "bounds": b"R_LIST_BOUNDS", "negative": b"R_LIST_BOUNDS"}[name]
                assert expected in actual[1][2], (backend, mode, name, actual[1])
                assert (actual[1][0] == 0) == (name == "success"), (backend, mode, name, actual[1])
            for control, failures in (("--max-steps=", (b"R_STEP_LIMIT",)), ("--max-frames=", (b"R_FRAME_LIMIT",)),
                                      ("--max-memory=", (b"R_MEMORY_BUDGET", b"OutOfMemory"))):
                if any(argument.startswith(control) for argument in arguments) and any(failure in actual[1][2] for failure in failures):
                    triggered[backend].add(control)
            receipts.append({"backend": backend, "guest_mode": mode, "case": name,
                             "controls": list(arguments), "exit": actual[1][0],
                             "stdout": actual[1][1].decode(), "stderr": actual[1][2].decode()})
            checked += 1
for backend, failures in triggered.items():
    assert failures == {"--max-steps=", "--max-frames=", "--max-memory="}, (backend, failures)
(options.output / "comparisons.json").write_text(json.dumps({"host_mode": options.host_mode, "matches": checked,
                                                           "triggered": {key: sorted(value) for key, value in triggered.items()},
                                                           "mode_probes": mode_receipts,
                                                           "outcomes": receipts}, indent=2) + "\n")
print(f"local list public failures: {checked} exact baseline/candidate matches")
