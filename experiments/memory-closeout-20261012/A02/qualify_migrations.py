#!/usr/bin/env python3
"""Check and execute every unchanged test in A02's exact migration reservation."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def save(path, value):
    path.write_text(json.dumps(value, indent=2) + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("phase", choices=("check", "run"))
    parser.add_argument("--compiler", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--files", nargs="*")
    parser.add_argument("--modes", nargs="+", choices=("ordinary", "zero"), default=["ordinary", "zero"])
    args = parser.parse_args()
    args.output = args.output.resolve()
    args.output.mkdir(parents=True, exist_ok=True)
    originals = json.loads((HERE / "migrations/originals.json").read_text())
    files = args.files or list(originals)
    result = {"compiler": str(args.compiler), "compiler_sha256": digest(args.compiler),
              "harness_sha256": digest(__file__), "phase": args.phase, "cases": {}}
    for name in files:
        source = ROOT / name
        directory = args.output / name.removesuffix(".my")
        directory.mkdir(parents=True, exist_ok=True)
        text = source.read_text()
        tests = re.findall(r"^(?:public )?func (test_\w+)\(\)\s*->\s*bool:", text, re.M)
        assert tests == [entry[0] for entry in originals[name]["tests"]], name
        if args.phase == "check":
            if not re.search(r"^func main\(", text, re.M):
                text += "\n\nfunc main() -> int:\n    return 0\n"
        else:
            text = re.sub(r"^func main\(", "func original_main(", text, flags=re.M)
            text += "\n\nfunc main(out: Stream) -> int:\n"
            for test in tests:
                text += f'    if not {test}():\n        out.print("{test}")\n        return 1\n'
            text += f'    out.print("passed {len(tests)}")\n    return 0\n'
        main_source = directory / source.name
        main_source.write_text(text)
        entry = {"original_sha256": originals[name]["sha256"], "source_sha256": digest(source),
                 "wrapper_sha256": digest(main_source), "test_count": len(tests), "modes": {}}
        result["cases"][name] = entry
        for mode in args.modes:
            flags = ["--experimental-zero-rc"] if mode == "zero" else []
            if args.phase == "check":
                argv = [args.compiler, "check", main_source, *flags]
            else:
                binary = directory / mode
                llvm = directory / (mode + ".ll")
                argv = [args.compiler, "build", main_source, "--release", "--counters", *flags,
                        "--zig", os.environ["ZIG"], "--cache-dir", args.output / "cache", "-o", binary,
                        "--emit-llvm", llvm]
            argv = list(map(str, argv))
            env = dict(os.environ)
            for key in ("MYLANG_COUNTERS", "MYLANG_OPTIONS", "MYLANG_CORE_SANITIZE"):
                env.pop(key, None)
            ran = subprocess.run(argv, cwd=ROOT, env=env, capture_output=True, text=True, timeout=300)
            row = {"argv": argv, "status": ran.returncode, "stdout": ran.stdout, "stderr": ran.stderr}
            entry["modes"][mode] = row
            if args.phase == "run" and ran.returncode == 0:
                counts = directory / (mode + "-counts.json")
                env.update(MYLANG_COUNTERS=str(counts), MYL_CORE_LEAKCHECK="1")
                run = subprocess.run([str(binary)], env=env, capture_output=True, text=True, timeout=120)
                row["run"] = {"status": run.returncode, "stdout": run.stdout, "stderr": run.stderr}
                row["binary_sha256"] = digest(binary)
                row["llvm_sha256"] = digest(llvm)
                row["tests_passed"] = run.returncode == 0 and run.stdout == f"passed {len(tests)}\n" and not run.stderr
                if counts.exists():
                    row["counters"] = json.loads(counts.read_text())
                    row["leak_free"] = row["counters"]["totals"]["live_bytes_at_exit"] == 0
                    row["rc_events"] = sum(site["count"] for site in row["counters"]["sites"] if site["kind"] in ("retain", "release", "uniqueness"))
                if mode == "zero":
                    symbols = subprocess.check_output(["nm", str(binary)], text=True)
                    row["symbols_clean"] = not any(s in symbols for s in ("myl_core_retain", "myl_core_release", "myl_core_share"))
            print(name, mode, ran.returncode, row.get("tests_passed", ""), flush=True)
            save(args.output / "results.json", result)
    assert result["compiler_sha256"] == digest(args.compiler)
    save(args.output / "results.json", result)


if __name__ == "__main__":
    main()
