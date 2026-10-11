#!/usr/bin/env python3
"""Compare default and single-owner semantics, including cases that cost more."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
CENSUS = HERE.parent / "rc-census-20261010"
spec = importlib.util.spec_from_file_location("census", CENSUS / "census.py")
census = importlib.util.module_from_spec(spec)
spec.loader.exec_module(census)
FLAG = "--experimental-single-owner"
CONFIGS = {
    "release": ["--release", "--counters"],
    "verify": ["--release", "--verify-facts"],
    "debug": ["--unoptimized"],
    "optimized_debug": [],
    "no_facts": ["--release", "--no-facts"],
}


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def command(argv, prefix, env):
    argv = list(map(str, argv))
    ran = subprocess.run(argv, cwd=ROOT, env=env, capture_output=True, timeout=300)
    prefix.parent.mkdir(parents=True, exist_ok=True)
    prefix.with_suffix(".stdout").write_bytes(ran.stdout)
    prefix.with_suffix(".stderr").write_bytes(ran.stderr)
    prefix.with_suffix(".command.json").write_text(json.dumps(
        {"argv": argv, "status": ran.returncode}, indent=2) + "\n")
    return ran


def require(ran, label, expected=None):
    if ran.returncode or (expected is not None and
                          (ran.stdout != expected.encode() or ran.stderr)):
        raise RuntimeError(f"{label}: {ran.returncode}, {ran.stdout!r}, {ran.stderr[:3000]!r}")


def expected(name, n):
    count = n * 1000
    total = count * (count - 1) // 2
    if name == "mutate":
        return f"{total}\n"
    if name == "snapshot":
        return f"{total} {total + 3}\n"
    if name == "records":
        return f"{count * count * (count + 1) // 2}\n"
    if name == "nested_copy":
        rows = n * 100
        total = 3 * rows * (rows + 1) // 2
        return f"{total} {total + 9}\n"
    if name == "callback":
        total = 4 * n + 6
        return f"{total * (2 if n % 2 else 1)} {total}\n"
    if name == "unused_snapshot":
        return "0 0\n"
    raise ValueError(name)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--compiler", type=Path, required=True)
    parser.add_argument("--zig", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    args.compiler = args.compiler.resolve()
    args.output = args.output.resolve()
    args.output.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ, ZIG=str(args.zig), MYLANG_ZIG=str(args.zig),
               MYL_CORE_LEAKCHECK="1")
    env.pop("MYLANG_COUNTERS", None)
    result = {
        "compiler": str(args.compiler), "compiler_sha256": digest(args.compiler),
        "zig": str(args.zig), "zig_sha256": digest(args.zig),
        "harness_sha256": digest(__file__),
        "samples": {}, "rejections": {}, "census": {}, "executions": 0,
    }
    for source in sorted((HERE / "samples").glob("*.my")):
        name = source.stem
        record = {"source_sha256": digest(source), "modes": {}}
        for semantics, flags in (("default", []), ("single_owner", [FLAG])):
            raw = args.output / name / semantics
            raw.mkdir(parents=True, exist_ok=True)
            configurations = {}
            for config, build_flags in CONFIGS.items():
                binary = raw / config
                build = [args.compiler, "build", source, "-o", binary,
                         "--zig", args.zig, "--cache-dir", args.output / "cache",
                         *flags, *build_flags]
                if config == "release":
                    build += ["--emit-llvm", raw / "release.ll"]
                require(command(build, raw / ("build-" + config), env), name + "/" + config)
                runs = {}
                for n in (4, 11):
                    counts = raw / f"counts-{n}.json"
                    run_env = dict(env)
                    if config == "release":
                        run_env["MYLANG_COUNTERS"] = str(counts)
                    ran = command([binary, *(["x"] * n)], raw / f"{config}-{n}", run_env)
                    require(ran, name + "/" + config, expected(name, n))
                    result["executions"] += 1
                    runs[str(n)] = {"stdout": ran.stdout.decode()}
                    if config == "release":
                        summarized = census.summarize(json.loads(counts.read_text()))
                        runs[str(n)].update({key: summarized[key] for key in ("kernel", "whole_program")})
                configurations[config] = runs
            record["modes"][semantics] = configurations
        result["samples"][name] = record
        print("pass", name, flush=True)

    # A default-mode artifact in the same cache must not admit an invalid unique build.
    codes = {"use_after_move": "E_SINGLE_OWNER_MOVED",
             "borrow_escape": "E_SINGLE_OWNER_BORROW",
             "overlap": "E_SINGLE_OWNER_OVERLAP"}
    for source in sorted((HERE / "rejected").glob("*.my")):
        name = source.stem
        raw = args.output / "rejected" / name
        raw.mkdir(parents=True, exist_ok=True)
        common = [args.compiler, "build", source, "-o", raw / "program",
                  "--zig", args.zig, "--cache-dir", args.output / "cache"]
        require(command(common, raw / "default", env), name)
        for command_name, argv in (
            ("build", [*common, FLAG]),
            ("check", [args.compiler, "check", source, FLAG,
                       "--cache-dir", args.output / "cache"]),
            ("dump", [args.compiler, "dump-ir", source, "--facts", FLAG]),
            ("json", [*common, FLAG, "--diagnostics=json"]),
        ):
            ran = command(argv, raw / command_name, env)
            if ran.returncode != 1 or codes[name].encode() not in ran.stderr:
                raise RuntimeError(f"missing rejection {name}/{command_name}: {ran.stderr!r}")
        result["rejections"][name] = codes[name]

    # Admission of the existing, unchanged census is reported separately.
    for source in sorted((CENSUS / "samples").glob("*.my")):
        raw = args.output / "census" / source.stem
        checked = command([args.compiler, "check", source, FLAG,
                           "--cache-dir", args.output / "cache"], raw / "check", env)
        entry = {"check_status": checked.returncode}
        if checked.returncode:
            entry["diagnostic"] = checked.stderr.decode()
        else:
            binary = raw / "program"
            built = command([args.compiler, "build", source, "-o", binary, "--release",
                             "--counters", FLAG, "--zig", args.zig,
                             "--cache-dir", args.output / "cache"], raw / "build", env)
            entry["build_status"] = built.returncode
            if built.returncode:
                entry["diagnostic"] = built.stderr.decode()
            else:
                entry["runs"] = {}
                for n in (4, 11):
                    counts = raw / f"counts-{n}.json"
                    ran = command([binary, *(["x"] * n)], raw / f"run-{n}",
                                  dict(env, MYLANG_COUNTERS=str(counts)))
                    require(ran, source.stem)
                    if ran.stderr:
                        raise RuntimeError(f"unexpected leak/trap: {ran.stderr!r}")
                    # Exact prior answers are also checked against the frozen census.
                    baseline = json.loads((CENSUS / "results.json").read_text())
                    answer = next(c for c in baseline["cases"] if c["id"] == source.stem)["expected"][str(n)]
                    if ran.stdout.decode() != answer:
                        raise RuntimeError(f"census answer changed: {source.stem}")
                    summarized = census.summarize(json.loads(counts.read_text()))
                    entry["runs"][str(n)] = {"stdout": ran.stdout.decode(),
                                            "kernel": summarized["kernel"],
                                            "whole_program": summarized["whole_program"]}
                    result["executions"] += 1
        result["census"][source.stem] = entry
        print("census", source.stem, entry.get("build_status", entry["check_status"]), flush=True)
    if digest(args.compiler) != result["compiler_sha256"]:
        raise RuntimeError("compiler changed during measurement")
    (HERE / "results.json").write_text(json.dumps(result, indent=2) + "\n")
    print("qualified", result["executions"], "executions", flush=True)


if __name__ == "__main__":
    main()
