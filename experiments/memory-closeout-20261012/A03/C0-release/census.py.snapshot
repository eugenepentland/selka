#!/usr/bin/env python3
"""Fresh, failure-preserving census; historical evidence is read-only.

Bounded groups of compiler invocations share one build admission lease. Do not
wrap this harness in build-slot.sh. Writes are only below --output.
"""
import argparse
import atexit
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import time
import signal

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
MODES = {"release": ["--release"], "debug": ["--unoptimized"],
         "verify": ["--release", "--verify-facts"], "optimized_debug": [],
         "no_facts": ["--release", "--no-facts"]}
RC_SYMBOLS = ("myl_core_retain", "myl_core_release", "myl_core_share",
              "myl_core_free_block")
LEASE = None
STOP_REQUESTED = False


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def save(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2) + "\n")


class AdmissionLease:
    """A cooperating child holds the slot while this parent runs bounded work."""

    def __init__(self, output, env, limit):
        self.output, self.env, self.limit = output, env, limit
        self.child = None
        self.count = 0
        self.serial = len(list((output / "raw/admission").glob("lease-*.json")))

    def close(self):
        if self.child is None:
            return
        self.child.stdin.close()
        status = self.child.wait(timeout=30)
        self.child.stdout.close()
        self.log.close()
        self.record.update(release_status=status, compiler_invocations=self.count,
                           admitted_work_ns=time.monotonic_ns() - self.admitted_at)
        save(self.receipt, self.record)
        self.child = None

    def command(self):
        if self.child is not None and (self.count >= self.limit or time.monotonic_ns() - self.admitted_at >= 60_000_000_000):
            self.close()
        if self.child is None:
            self.serial += 1
            directory = self.output / "raw/admission"
            directory.mkdir(parents=True, exist_ok=True)
            self.receipt = directory / f"lease-{self.serial}.json"
            self.log = (directory / f"lease-{self.serial}.stderr").open("w")
            code = "import sys; print('admitted', flush=True); sys.stdin.buffer.read()"
            argv = [str(ROOT / "scripts/build-slot.sh"), "build", sys.executable, "-u", "-c", code]
            started = time.monotonic_ns()
            self.child = subprocess.Popen(argv, cwd=ROOT, env=self.env, stdin=subprocess.PIPE,
                                          stdout=subprocess.PIPE, stderr=self.log)
            ready = self.child.stdout.readline()
            if ready != b"admitted\n":
                self.child.stdin.close()
                self.child.wait(timeout=30)
                self.child.stdout.close()
                self.log.close()
                self.child = None
                raise RuntimeError("build admission lease failed: " + ready.decode(errors="replace"))
            self.admitted_at = time.monotonic_ns()
            self.record = {"argv": argv, "queue_wait_ns": self.admitted_at - started,
                           "limit_compiler_invocations": self.limit, "release_after_ns": 60_000_000_000,
                           "note": "Release happens at a safe command boundary; an individual compile may exceed 60 seconds."}
            save(self.receipt, self.record)
            self.count = 0
        if self.child.poll() is not None:
            raise RuntimeError("admission holder exited before compilation")
        self.count += 1
        return str(self.receipt.relative_to(self.output))


def read(relative):
    return json.loads((ROOT / relative).read_text())


def identity(path):
    path = Path(path)
    if not path.is_absolute():
        path = ROOT / path
    return {"path": str(path.relative_to(ROOT)), "sha256": digest(path)}


def manifest():
    originals = {}
    for group in ("lists", "composites", "containers"):
        for case in read(f"experiments/rc-census-20261010/{group}.json"):
            originals[case["id"]] = case
    cases = []
    historical = read("experiments/zero-rc-final-20261011/results.json")["cases"]
    assert len(historical) == 48
    for name, modes in historical.items():
        prior = modes["release"]
        case = {"id": name, "family": "historical-48", "source": identity(prior["source"]),
                "runs": [{"id": n, "argv": ["x"] * int(n), "stdout": run["stdout"], "exit": 0}
                         for n, run in prior["runs"].items()], "modes": list(MODES)}
        linked = (ROOT / prior["source"]).with_suffix(".c")
        if linked.exists():
            case["link"] = identity(linked)
        if name.startswith("census/"):
            case_id = name.split("/")[1]
            original = originals[case_id]
            case.update(original_id=case_id, original=identity("experiments/rc-census-20261010/" + original["source"]),
                        oracle=original["oracle"], intent=original["intent"], category=original["category"])
        cases.append(case)
    assert sum("original_id" in case for case in cases) == 30
    for source in sorted((ROOT / "src/stdlib/fixtures").glob("*.my")):
        if source.stem == "time_random_provider":
            continue
        migrated = ROOT / "experiments/zero-rc-closeout-20261011/samples" / source.name
        cases.append({"id": "library/" + source.stem, "family": "migrated-library-10",
                      "original": identity(source), "source": identity(migrated if migrated.exists() else source),
                      "runs": [{"id": "0", "argv": [], "stdout": "", "exit": 0 if source.stem == "time_random" else 42}],
                      "modes": list(MODES)})
    assert sum(case["family"] == "migrated-library-10" for case in cases) == 10
    for name, answer in (("parallel_map", "2016 item-0! 16\n"), ("parallel_outcome", "416\n")):
        cases.append({"id": "tasks/" + name, "family": "source-tasks", "source": identity("experiments/zero-rc-closeout-20261011/samples/" + name + ".my"),
                      "runs": [{"id": "workers-" + str(n), "argv": [], "stdout": answer, "exit": 0,
                                "env": {"MYLANG_THREADS": str(n)}} for n in (1, 2, 8)], "modes": list(MODES)})
    for kind in ("array", "object"):
        for size in (1, 16, 128):
            for action in ("control", "hit", "miss"):
                name = f"{kind}_{size}_{action}"
                cases.append({"id": "batch/" + name, "family": "json-field-batch", "source": identity("experiments/zero-rc-batch-20261011/samples/" + name + ".my"),
                              "runs": [{"id": "0", "argv": [], "stdout": f"{kind} {4096 if action == 'hit' else 32}\n", "exit": 0}], "modes": list(MODES)})
    for phase in ("before", "after"):
        cases.append({"id": "batch/record_" + phase, "family": "json-field-batch", "source": identity(f"experiments/zero-rc-batch-20261011/samples/record_{phase}.my"),
                      "runs": [{"id": "0", "argv": [], "stdout": "267560\n", "exit": 0}], "modes": list(MODES)})
    cases.append({"id": "owned-payload/json_nested", "family": "owned-payload", "source": identity("experiments/owned-payload-20261011/samples/json_nested.my"),
                  "runs": [{"id": "0", "argv": [], "stdout": "121000\n", "exit": 0}], "modes": list(MODES)})
    assert len({case["id"] for case in cases}) == len(cases)
    return {"schema": "memory-closeout-census-manifest-v1", "c0": "fbfcaa7a923186a8e773c3760f81c10aa345a432",
            "historical_inputs_are_read_only": True, "original_denominator": 30, "historical_matrix_denominator": 48,
            "cases": cases}


def load_helper(name, relative):
    spec = importlib.util.spec_from_file_location(name, ROOT / relative)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def invoke(argv, prefix, env, admitted=False, timeout=1200):
    argv = list(map(str, argv))
    admission = None
    if admitted:
        if LEASE is None:
            argv = [str(ROOT / "scripts/build-slot.sh"), "build", *argv]
        else:
            admission = LEASE.command()
    prefix.parent.mkdir(parents=True, exist_ok=True)
    start = time.monotonic_ns()
    try:
        ran = subprocess.run(argv, cwd=ROOT, env=env, capture_output=True, timeout=timeout)
        record = {"argv": argv, "exit": ran.returncode, "stdout": ran.stdout.decode(errors="replace"),
                  "stderr": ran.stderr.decode(errors="replace"), "wall_ns_including_admission": time.monotonic_ns() - start}
    except subprocess.TimeoutExpired as error:
        record = {"argv": argv, "exit": None, "error": "timeout", "stdout": (error.stdout or b"").decode(errors="replace"),
                  "stderr": (error.stderr or b"").decode(errors="replace"), "wall_ns_including_admission": time.monotonic_ns() - start}
    if admission:
        record["admission_receipt"] = admission
        record["wall_ns_excludes_admission_wait"] = True
    save(prefix.with_suffix(".json"), record)
    return record


def structural(binary, llvm, directory, env):
    ir = llvm.read_text()
    violations = []
    if "; mylang-zero-rc-v2" not in ir:
        violations.append("zero-RC ABI marker absent")
    for line in ir.splitlines():
        if "load atomic i32" in line or ("store i32" in line and "!tbaa !3" in line) or any("@" + name in line for name in RC_SYMBOLS):
            violations.append(line.strip())
    nm = invoke(["nm", binary], directory / "nm", env)
    symbols = [line for line in nm["stdout"].splitlines() if any(name in line for name in RC_SYMBOLS)]
    return {"passed": not violations and nm["exit"] == 0 and not symbols,
            "llvm_sha256": digest(llvm), "llvm_violations": violations, "legacy_symbols": symbols,
            "nm_sha256": digest(directory / "nm.json"),
            "scope": "Emitted guest LLVM and linked symbols; runtime preprocessor/layout proof belongs to A07."}


def lane(args, env, case, mode, audit, census):
    directory = args.output / "raw" / case["id"] / mode
    directory.mkdir(parents=True, exist_ok=True)
    source = ROOT / case["source"]["path"]
    assert digest(source) == case["source"]["sha256"]
    # Keep fixture names from shadowing standard modules such as json and path.
    copied = directory / "main.my"
    copied.write_bytes(source.read_bytes())
    binary, llvm = directory / "program", directory / "program.ll"
    flags = ["--experimental-zero-rc"] if args.ownership == "opt-in" else []
    command = [args.compiler, "build", copied, *flags, "--zig", args.zig,
               "--cache-dir", args.output / "cache", "--counters", *MODES[mode], "-o", binary, "--emit-llvm", llvm]
    if "link" in case:
        command += ["--link", ROOT / case["link"]["path"]]
    build = invoke(command, directory / "build", env, admitted=True)
    result = {"source": case["source"], "build": build, "runs": {}, "status": "refused"}
    if build["exit"] != 0:
        if build["exit"] is None or build["exit"] < 0:
            result["status"] = "build_failed"
        return result
    result.update(status="failed", binary_sha256=digest(binary), structural=structural(binary, llvm, directory, env))
    for run in case["runs"]:
        counts = directory / ("counts-" + run["id"] + ".json")
        ran = invoke([binary, *run["argv"]], directory / ("run-" + run["id"]),
                     dict(env, MYLANG_COUNTERS=str(counts), **run.get("env", {})))
        ran["output_matches"] = ran["stdout"] == run["stdout"] and ran["exit"] == run["exit"] and not ran["stderr"]
        if counts.exists():
            try:
                ran["audit"] = audit.audit(counts)
                raw = json.loads(counts.read_text())
                # Keep failures as records even if historical summarizer rejects a leak.
                ran["whole_program"] = raw["totals"]
                if ran["audit"]["managed_leak_free"]:
                    ran["workload"] = census.summarize(raw)["kernel"]
            except (ValueError, KeyError, TypeError) as error:
                ran["counter_error"] = str(error)
        ran["passed"] = (ran["output_matches"] and ran.get("audit", {}).get("observed_rc_free", False)
                         and ran.get("audit", {}).get("managed_leak_free", False))
        result["runs"][run["id"]] = ran
    if result["structural"]["passed"] and all(run["passed"] for run in result["runs"].values()):
        result["status"] = "passed"
    return result


def summarize(result, cases):
    original = [case for case in cases if "original_id" in case]
    summary = {"manifest_cases": len(cases), "original_denominator": 30,
               "planned_builds": sum(len(case["modes"]) for case in cases),
               "planned_executions": sum(len(case["modes"]) * len(case["runs"]) for case in cases),
               "completed_builds": 0,
               "case_status": {}, "original_30": {}, "original_source_checks": {"admitted": 0, "refused": 0, "unmeasured": 30},
               "executions": 0, "passed_executions": 0,
               "executions_with_rc": 0, "executions_with_managed_leaks": 0}
    for case in cases:
        lanes = result["cases"].get(case["id"], {}).get("modes", {})
        for mode, row in lanes.items():
            summary["completed_builds"] += 1
            key = mode + "/" + row["status"]
            summary["case_status"][key] = summary["case_status"].get(key, 0) + 1
            for run in row["runs"].values():
                summary["executions"] += 1
                summary["passed_executions"] += run["passed"]
                if "audit" in run:
                    summary["executions_with_rc"] += not run["audit"]["observed_rc_free"]
                    summary["executions_with_managed_leaks"] += not run["audit"]["managed_leak_free"]
    for n in ("4", "11"):
        counts = dict(denominator=30, allocating=0, allocation_free=0, executed_rc=0, refused=0, failed=0, unmeasured=0)
        for case in original:
            release = result["cases"].get(case["id"], {}).get("modes", {}).get("release")
            if not release:
                counts["unmeasured"] += 1
            elif release["status"] == "refused":
                counts["refused"] += 1
            elif release["status"] != "passed" or n not in release["runs"] or not release["runs"][n].get("passed"):
                counts["failed"] += 1
            else:
                run = release["runs"][n]
                workload = run["workload"]
                counts["allocating" if workload["allocs"] or workload["reallocs"] else "allocation_free"] += 1
            if release and n in release["runs"] and "audit" in release["runs"][n]:
                counts["executed_rc"] += not release["runs"][n]["audit"]["observed_rc_free"]
        counts["unmeasured"] += 30 - len(original)
        summary["original_30"][n] = counts
    for case in original:
        checked = result["cases"].get(case["id"], {}).get("original_admission")
        if checked:
            summary["original_source_checks"]["admitted" if checked["exit"] == 0 else "refused"] += 1
            summary["original_source_checks"]["unmeasured"] -= 1
    summary["complete_matrix"] = summary["completed_builds"] == summary["planned_builds"]
    return summary


def main():
    global LEASE, STOP_REQUESTED
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write-manifest", action="store_true")
    parser.add_argument("--compiler", type=Path)
    parser.add_argument("--compiler-commit")
    parser.add_argument("--zig", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--ownership", choices=("opt-in", "default"), default="opt-in")
    parser.add_argument("--case", action="append", default=[])
    parser.add_argument("--family", action="append", default=[])
    parser.add_argument("--modes", nargs="+", choices=MODES, default=list(MODES))
    parser.add_argument("--resume", action="store_true")
    parser.add_argument("--batch-size", type=int, default=10, help="compiler calls per shared build lease (1..10)")
    args = parser.parse_args()
    if not 1 <= args.batch_size <= 10:
        parser.error("batch size must be 1..10")
    if args.write_manifest:
        save(HERE / "manifest.json", manifest())
        return
    if not all((args.compiler, args.compiler_commit, args.zig, args.output)):
        parser.error("--compiler, --compiler-commit, --zig and --output are required")
    for key in ("compiler", "zig", "output"):
        setattr(args, key, getattr(args, key).resolve())
    args.output.mkdir(parents=True, exist_ok=args.resume)
    cases = read(str((HERE / "manifest.json").relative_to(ROOT)))["cases"]
    if args.case or args.family:
        cases = [case for case in cases if case["id"] in args.case or case["family"] in args.family]
    if not cases:
        parser.error("no matching cases")
    env = dict(os.environ, ZIG=str(args.zig), MYLANG_ZIG=str(args.zig), MYL_CORE_LEAKCHECK="1")
    for key in ("MYLANG_COUNTERS", "MYLANG_OPTIONS", "MYLANG_CORE_SANITIZE"):
        env.pop(key, None)
    LEASE = AdmissionLease(args.output, env, args.batch_size)
    atexit.register(LEASE.close)
    def request_checkpoint(_signum, _frame):
        global STOP_REQUESTED
        STOP_REQUESTED = True
    signal.signal(signal.SIGUSR1, request_checkpoint)
    audit = load_helper("a03_audit", "experiments/zero-rc-20261011/audit.py")
    census = load_helper("a03_historical_census", "experiments/rc-census-20261010/census.py")
    identities = {"compiler": {"path": str(args.compiler), "sha256": digest(args.compiler), "commit": args.compiler_commit},
                  "zig": {"path": str(args.zig), "sha256": digest(args.zig)}, "harness_sha256": digest(__file__),
                  "manifest_sha256": digest(HERE / "manifest.json"), "ownership": args.ownership}
    result_path = args.output / "results.json"
    if args.resume and result_path.exists():
        result = json.loads(result_path.read_text())
        assert result["identities"] == identities, "resume identity mismatch"
    else:
        result = {"schema": "memory-closeout-census-v1", "identities": identities,
                  "limitations": ["Managed counts omit native scratch, provider buffers, stacks, and allocator overhead; not RSS.",
                                  "Admission receipts preserve queue wait separately; command receipts flag its exclusion. No compile/runtime speed claims.",
                                  "Emitted/runtime RC events can overlap and are not added.",
                                  "Original source refusals are recorded separately from migrated workload results."], "cases": {}}
    for case in cases:
        record = result["cases"].setdefault(case["id"], {"manifest": case, "modes": {}})
        if "original_id" in case and "original_admission" not in record:
            original = ROOT / case["original"]["path"]
            flags = ["--experimental-zero-rc"] if args.ownership == "opt-in" else []
            record["original_admission"] = invoke([args.compiler, "check", original, *flags], args.output / "raw" / case["id"] / "original-check", env, admitted=True)
        for mode in args.modes:
            if mode in record["modes"]:
                continue
            try:
                row = lane(args, env, case, mode, audit, census)
            except Exception as error:
                row = {"status": "harness_failed", "error": repr(error), "runs": {}}
            record["modes"][mode] = row
            result["summary"] = summarize(result, cases)
            save(result_path, result)
            print(row["status"], case["id"], mode, flush=True)
            if STOP_REQUESTED:
                print("checkpoint requested; all completed lanes saved", flush=True)
                LEASE.close()
                return 3
    LEASE.close()
    for key in ("compiler", "zig"):
        assert digest(getattr(args, key)) == identities[key]["sha256"], "tool changed during run"
    print(json.dumps(result["summary"], indent=2), flush=True)
    return int(any(lane["status"] != "passed" for case in result["cases"].values() for lane in case["modes"].values()))


if __name__ == "__main__":
    sys.exit(main())
