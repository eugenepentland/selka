#!/usr/bin/env python3
"""Compare unchanged lifetime probes and scaled workloads using private artifacts."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
CENSUS = HERE.parent / "rc-census-20261010"
spec = importlib.util.spec_from_file_location("prior_census", CENSUS / "census.py")
census = importlib.util.module_from_spec(spec)
spec.loader.exec_module(census)
MODES = (("plain", []), ("counted", ["--counters"]), ("verify", ["--verify-facts"]))


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def write(path, value):
    path.write_text(json.dumps(value, indent=2) + "\n")


def run(argv, prefix, env, expected=None, status=0, error=None):
    argv = list(map(str, argv))
    result = subprocess.run(argv, cwd=ROOT, env=env, capture_output=True, timeout=300)
    prefix.with_suffix(".stdout").write_bytes(result.stdout)
    prefix.with_suffix(".stderr").write_bytes(result.stderr)
    write(prefix.with_suffix(".command.json"), {"argv": argv, "status": result.returncode})
    if result.returncode != status or (expected is not None and result.stdout != expected.encode()):
        raise RuntimeError(f"unexpected result {prefix}: {result.returncode} {result.stdout!r} {result.stderr[:1200]!r}")
    if expected is not None and status == 0 and result.stderr:
        raise RuntimeError(f"unexpected stderr/leak report: {prefix}: {result.stderr!r}")
    if error is not None and error.encode() not in result.stderr:
        raise RuntimeError(f"expected trap absent: {prefix}")
    return result


def constructor_answer(rounds, seed, snapshot):
    # Weighted sum of seed+i, i=0..7, is 36*seed+168. Batch offsets repeat
    # every 257 iterations. Snapshot mode includes both versions, with +1 at index 0.
    periods, tail = divmod(rounds, 257)
    offsets = periods * 257 * 256 // 2 + tail * (tail - 1) // 2
    total = rounds * (36 * seed + 168) + 36 * offsets
    return str(((2 * total + rounds) if snapshot else total) % 1000000007) + "\n"


def replacement_answer(rounds, seed, snapshot):
    # Three values per batch: seed+b, seed+b+1, seed+b+2; score adds length.
    total = 3 * rounds * (seed + 2) + 3 * rounds * (rounds - 1) // 2
    if snapshot:
        # Nonempty previous snapshots contribute length=3*b and last=seed+b+1.
        total += 2 * rounds * (rounds - 1) + (seed + 1) * (rounds - 1)
    return str(total) + "\n"


def targets():
    answer = {"constructor": constructor_answer, "replacement": replacement_answer}
    result = {}
    for name, sizes in (("constructor", (10000, 1000000)), ("replacement", (2000, 8000))):
        cases = []
        for rounds in sizes:
            for mode in ("replace", "snapshot"):
                cases.append({"id": f"{mode}-{rounds}", "argv": [mode, str(rounds), "7"],
                              "stdout": answer[name](rounds, 7, mode == "snapshot"), "status": 0})
        cases.append({"id": "overflow", "argv": ["trap", "1", "9223372036854775807"],
                      "stdout": "", "status": 1, "error": "R_OVERFLOW"})
        result[name] = cases
    return result


def capture_target(name, cases, args, env):
    source = HERE / (name + ".my")
    raw = args.output / name
    raw.mkdir(exist_ok=True)
    completed = raw / "result.json"
    identity = {"source_sha256": sha(source), "compiler_sha256": sha(args.compiler),
                "harness_sha256": args.harness_sha256, "zig_sha256": args.zig_sha256}
    if args.resume and completed.exists():
        previous = json.loads(completed.read_text())
        if all(previous.get(k) == v for k, v in identity.items()) and previous["cases"] == cases:
            print(f"reuse {name}", flush=True)
            return previous
    result = dict(identity, source=str(source.relative_to(ROOT)), cases=cases, binaries={}, runs={})
    result["static"] = json.loads(run([args.compiler, "cost", source, "--json"], raw / "cost", env).stdout)
    for mode, flags in MODES:
        binary = raw / mode
        command = [args.compiler, "build", source, "--release", "--zig", args.zig,
                   "--cache-dir", args.output / "cache", "-o", binary] + flags
        if mode == "plain":
            command += ["--emit-llvm", raw / "plain.ll"]
        run(command, raw / ("build-" + mode), env)
        result["binaries"][mode] = {"path": str(binary), "sha256": sha(binary)}
        for case in cases:
            prefix = raw / (mode + "-" + case["id"])
            count_path = raw / ("counts-" + case["id"] + ".json")
            running = dict(env, MYL_CORE_LEAKCHECK="1")
            if mode == "counted":
                running["MYLANG_COUNTERS"] = str(count_path)
            observed = run([binary] + case["argv"], prefix, running, case["stdout"],
                           case["status"], case.get("error"))
            entry = result["runs"].setdefault(case["id"], {"stdout": case["stdout"],
                "status": case["status"], "argv": case["argv"], "qualified_modes": []})
            entry["qualified_modes"].append(mode)
            if case["status"]:
                entry.setdefault("trap_stderr", {})[mode] = observed.stderr.decode(errors="replace")
            if mode == "counted":
                counts = json.loads(count_path.read_text())
                entry.update(census.summarize(counts) if case["status"] == 0 else {"whole_program": counts["totals"]})
    if sha(source) != identity["source_sha256"]:
        raise RuntimeError("target source changed during capture")
    write(completed, result)
    print(f"pass {name}: {len(cases) * 3} executions", flush=True)
    return result


def cache_parity(args, env, cases):
    result = {}
    selected = {c["id"]: (CENSUS / c["source"], [
        {"id": str(n), "argv": ["x"] * n, "stdout": c["expected"][str(n)], "status": 0}
        for n in (4, 11)]) for c in cases if c["id"] in ("04_returned_list", "20_loop_carried")}
    for name, inputs in targets().items():
        selected[name] = (HERE / (name + ".my"), [inputs[0], inputs[1], inputs[-1]])
    for name, (source, inputs) in selected.items():
        raw = args.output / "cache-parity" / name
        raw.mkdir(parents=True, exist_ok=True)
        completed = raw / "result.json"
        if args.resume and completed.exists():
            previous = json.loads(completed.read_text())
            if previous["compiler_sha256"] == sha(args.compiler) and previous["source_sha256"] == sha(source):
                result[name] = previous
                continue
        # Preserve interrupted caches rather than describing them as cold.
        attempt = 0
        while (raw / f"attempt-{attempt}").exists():
            attempt += 1
        work = raw / f"attempt-{attempt}"
        work.mkdir()
        cache = work / "cache"
        binary = work / "program"
        entry = {"compiler_sha256": sha(args.compiler), "source_sha256": sha(source), "phases": {}}
        for phase in ("cold", "warm"):
            command = [args.compiler, "build", source, "--release", "--zig", args.zig,
                       "--cache-dir", cache, "--report", "-o", binary]
            run(command, work / ("build-" + phase), env)
            phase_result = {"binary_sha256": sha(binary), "qualified_inputs": []}
            for case in inputs:
                run([binary] + case["argv"], work / (phase + "-" + case["id"]),
                    dict(env, MYL_CORE_LEAKCHECK="1"), case["stdout"], case["status"], case.get("error"))
                phase_result["qualified_inputs"].append(case["id"])
            entry["phases"][phase] = phase_result
        entry["binary_hashes_equal"] = entry["phases"]["cold"]["binary_sha256"] == entry["phases"]["warm"]["binary_sha256"]
        write(completed, entry)
        result[name] = entry
        print(f"cache parity {name}: ordinary outputs/traps preserved", flush=True)
    return result


def capture(args):
    args.compiler = args.compiler.resolve()
    args.zig = args.zig.resolve()
    args.output = args.output.resolve()
    args.output.mkdir(parents=True, exist_ok=args.resume)
    args.harness_sha256 = hashlib.sha256((sha(__file__) + sha(CENSUS / "census.py")).encode()).hexdigest()
    args.zig_sha256 = sha(args.zig)
    frozen = json.loads(args.frozen.read_text())
    cases = sorted([c for group in census.GROUPS for c in json.loads((CENSUS / group).read_text())], key=lambda c: c["id"])
    if len(cases) != 30 or len({c["id"] for c in cases}) != 30:
        raise ValueError("expected exactly 30 unchanged census samples")
    for case in cases:
        if sha(CENSUS / case["source"]) != frozen["samples"][case["id"]]:
            raise ValueError("prior sample changed: " + case["id"])
    env = dict(os.environ, ZIG=str(args.zig), MYLANG_ZIG=str(args.zig))
    for key in ("MYLANG_COUNTERS", "MYL_CORE_LEAKCHECK"):
        env.pop(key, None)
    source_manifest = args.output / "compiler-sources.json"
    if args.source_manifest:
        shutil.copyfile(args.source_manifest, source_manifest)
    else:
        write(source_manifest, {str(p.relative_to(ROOT)): sha(p) for p in sorted((ROOT / "src").rglob("*"))
                                if p.is_file() and not p.name.endswith("_test.zig")})
    install = args.compiler.parent.parent
    result = {"version": "caller-consume-capture-v1", "compiler": str(args.compiler),
              "compiler_sha256": sha(args.compiler), "compiler_source_manifest_sha256": sha(source_manifest),
              "compiler_base_revision": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
              "installed_files": {str(p.relative_to(install)): sha(p) for p in sorted(install.rglob("*")) if p.is_file()},
              "harness_sha256": args.harness_sha256, "zig_sha256": args.zig_sha256,
              "baseline_compiler_sha256": frozen["baseline_compiler_sha256"],
              "cases": [], "targets": {}, "failures": []}
    for case in cases:
        try:
            result["cases"].append(census.capture_case(case, args, env))
        except (RuntimeError, ValueError, subprocess.TimeoutExpired) as error:
            result["failures"].append({"case": case["id"], "error": str(error)})
            print(f"FAIL {case['id']}: {error}", flush=True)
        write(args.output / "results.json", result)
    for name, inputs in targets().items():
        try:
            result["targets"][name] = capture_target(name, inputs, args, env)
        except (RuntimeError, ValueError, subprocess.TimeoutExpired) as error:
            result["failures"].append({"target": name, "error": str(error)})
            print(f"FAIL {name}: {error}", flush=True)
        write(args.output / "results.json", result)
    if not result["failures"]:
        result["cache_parity"] = cache_parity(args, env, cases)
        result["qualified_executions"] = 180 + sum(len(c) * 3 for c in targets().values()) + 20
        if sha(args.compiler) != result["compiler_sha256"]:
            raise RuntimeError("compiler changed during capture")
        for case in cases:
            if sha(CENSUS / case["source"]) != frozen["samples"][case["id"]]:
                raise RuntimeError("prior source changed during capture")
    write(args.output / "results.json", result)
    return 1 if result["failures"] else 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler", type=Path, required=True)
    parser.add_argument("--zig", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--frozen", type=Path, required=True)
    parser.add_argument("--source-manifest", type=Path)
    parser.add_argument("--resume", action="store_true")
    return capture(parser.parse_args())


if __name__ == "__main__":
    sys.exit(main())
