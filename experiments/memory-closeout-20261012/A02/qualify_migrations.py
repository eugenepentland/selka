#!/usr/bin/env python3
"""Check and execute every unchanged test in A02's exact migration reservation."""
import argparse
import json
import os
from pathlib import Path
import re
from qualification_support import (artifact_audit, call, clean_env, counter_audit,
                                   fresh_output, mode_flags, owned_clean, save, sha)

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("phase", choices=("check", "run"))
    parser.add_argument("--compiler", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--files", nargs="*")
    parser.add_argument("--modes", nargs="+", choices=("ordinary", "zero", "default"), default=["ordinary", "zero"],
                        help="default checks owned behavior without a prototype flag")
    args = parser.parse_args()
    args.compiler = args.compiler.resolve()
    args.output = fresh_output(args.output)
    originals = json.loads((HERE / "migrations/originals.json").read_text())
    files = args.files or list(originals)
    if len(files) != len(set(files)) or len(args.modes) != len(set(args.modes)):
        raise ValueError("duplicate files or modes")
    result = {"compiler": str(args.compiler), "compiler_sha256": sha(args.compiler),
              "harness_sha256": sha(__file__), "support_sha256": sha(HERE / "qualification_support.py"),
              "phase": args.phase, "requested_files": files, "requested_modes": args.modes,
              "complete": False, "qualified": False, "cases": {}}
    save(args.output / "results.json", result)
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
        entry = {"original_sha256": originals[name]["sha256"], "source_sha256": sha(source),
                 "wrapper_sha256": sha(main_source), "test_count": len(tests), "modes": {}}
        result["cases"][name] = entry
        for mode in args.modes:
            flags = mode_flags(mode)
            if args.phase == "check":
                argv = [args.compiler, "check", main_source, *flags]
            else:
                binary = directory / mode
                llvm = directory / (mode + ".ll")
                argv = [args.compiler, "build", main_source, "--release", "--counters", *flags,
                        "--zig", os.environ["ZIG"], "--cache-dir", args.output / "cache", "-o", binary,
                        "--emit-llvm", llvm]
            argv = list(map(str, argv))
            env = clean_env()
            row = call(argv, cwd=ROOT, env=env)
            entry["modes"][mode] = row
            row["qualified"] = args.phase == "check" and row["status"] == 0 and not row["stderr"]
            if args.phase == "run" and row["status"] == 0:
                counts = directory / (mode + "-counts.json")
                env.update(MYLANG_COUNTERS=str(counts), MYL_CORE_LEAKCHECK="1")
                row["run"] = call([binary], env=env, cwd=ROOT, timeout=120)
                row.update(counter_audit(counts))
                if row["counts_present"]:
                    row["counters"] = row.pop("counts")
                row.update(artifact_audit(binary, llvm))
                row["tests_passed"] = row["run"]["status"] == 0 and row["run"]["stdout"] == f"passed {len(tests)}\n" and not row["run"]["stderr"]
                row["qualified"] = row["tests_passed"] and row.get("leak_free", False)
                if mode in ("zero", "default"):
                    row["qualified"] &= owned_clean(row, row)
            print(name, mode, row["status"], row["qualified"], flush=True)
            save(args.output / "results.json", result)
    assert result["compiler_sha256"] == sha(args.compiler)
    assert all(case["source_sha256"] == sha(ROOT / name) for name, case in result["cases"].items())
    result["complete"] = True
    result["qualified"] = all(row["qualified"] for case in result["cases"].values() for row in case["modes"].values())
    result["scope"] = "source admission only" if args.phase == "check" else "all preserved zero-argument test contracts in counted native wrappers"
    save(args.output / "results.json", result)
    return 0 if result["qualified"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
