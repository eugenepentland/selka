#!/usr/bin/env python3
"""Strict S4 cases of all nine inherited kinds: 50/package or 200/final exit.

Launch the entire command under core-qualification.lock so the old gate and
this matrix cannot overlap. Each worker also obtains a normal build slot.
"""
import argparse
import concurrent.futures
import importlib.util
import json
from pathlib import Path
import shlex
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))
import qualification_support as support
import qualification_provenance as provenance
WRAPPER = ROOT / "experiments/new-core-s3-20261006/wave-x/integration/fuzz_qualification.py"
KINDS = ("s0", "s1", "rc", "rebinding", "iteration", "dict", "text", "number", "functions")
HARNESSES = {
    "text": ROOT / "experiments/new-core-s3-20261006/wave-c/s3-char/fuzz_char.py",
    "number": ROOT / "experiments/new-core-s2-20261005/wave-b/s2-t2/fuzz_number.py",
}


def git(*argv):
    return subprocess.check_output(["git", *argv], cwd=ROOT, text=True).strip()


identity = support.identity


def strict_wrapper():
    spec = importlib.util.spec_from_file_location("s4_local_strict_fuzz", WRAPPER)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def guarded_monitor(parent):
    class OwnedMonitor(parent):
        def __init__(self, args, original_run):
            self.capture = support.Capture(args.evidence / "processes", ROOT)
            self.inputs = provenance.FuzzInputs(args)
            super().__init__(args, self.capture.run)

        def run(self, argv, *arguments, **options):
            argv = list(map(str, argv))
            if len(argv) > 2 and argv[1] == "build" and str(Path(argv[2]).absolute()) not in self.inputs.sources:
                expected_arguments = 3 if self.args.kind == "rc" else 5
                for case, builds in self.cases.items():
                    outcomes = [values for (source, _), values in self.outcomes.items() if source == case]
                    if (not builds["old"] or builds["core"] != {"debug", "release", "verify"}
                            or len(outcomes) != expected_arguments
                            or any(set(values) != {"old", "debug", "release", "verify"} for values in outcomes)):
                        raise ValueError("next fuzz input phase arrived before the prior case completed")
            self.inputs.before(argv)
            result = super().run(argv, *arguments, **options)
            self.inputs.check()
            return result

    return OwnedMonitor


def worker(argv):
    """Use the frozen strict monitor with a local process-group capture underneath."""
    wrapper = strict_wrapper()
    monitor_type = guarded_monitor(wrapper.Monitor)
    original_qualify = wrapper.s2.qualify
    hooks = []

    class HookedMonitor(monitor_type):
        def __init__(self, args, original_run):
            super().__init__(args, original_run)
            producers = [ROOT / path for path in wrapper.HARNESSES.values()]
            producers += list(HARNESSES.values())
            if args.harness:
                producers.append(args.harness)
            hook = provenance.GeneratorCleanup(self.inputs, producers)
            hook.__enter__()
            hooks.append(hook)

    def checked_qualification(args, monitor, status, output, error):
        input_error = None
        try:
            monitor.inputs.finish()
        except (OSError, ValueError) as failure:
            input_error = str(failure)
            monitor.failures.append({"kind": "input_changed", "reason": input_error})
        result = original_qualify(args, monitor, status, output, error or input_error)
        result.update(inputs_unchanged=input_error is None,
                      input_inventory=support.identity(monitor.inputs.directory / "inventory.json"),
                      intentional_cleanups=monitor.inputs.cleanup_proofs,
                      schema="s4-fuzz-kind-v2", component="fuzz-kind-worker",
                      scope=provenance.scope(args.cases, final=args.cases == 200),
                      parent_origin_binding_required=True)
        return result

    wrapper.Monitor, wrapper.s2.qualify = HookedMonitor, checked_qualification
    original = sys.argv
    try:
        sys.argv = [str(WRAPPER), *argv]
        return wrapper.main()
    finally:
        sys.argv = original
        wrapper.s2.qualify = original_qualify
        for hook in reversed(hooks):
            hook.__exit__(None, None, None)


def qualified_kind(status, summary, kind, cases, oracles):
    comparisons = cases * (9 if kind == "rc" else 15)
    counts = {"cases_requested": cases, "cases_seen": cases, "accepted": cases,
              "comparisons_expected": comparisons, "native_comparisons": comparisons,
              "old_rejected": 0, "core_refused": 0, "core_build_failed": 0, "harness_status": 0}
    return (status == 0 and isinstance(summary, dict) and summary.get("kind") == kind
            and all(summary.get(key) is True for key in ("qualified", "complete", "native_complete", "oracle_unchanged", "inputs_unchanged"))
            and all(type(summary.get(key)) is int and summary[key] == wanted for key, wanted in counts.items())
            and summary.get("failures") == [] and summary.get("error") is None
            and summary.get("oracles") == oracles)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--old", type=Path, required=True)
    parser.add_argument("--core", type=Path, required=True)
    parser.add_argument("--evidence", type=Path, required=True)
    parser.add_argument("--cache", type=Path, required=True)
    parser.add_argument("--jobs", type=int, choices=(1, 2, 3), default=3)
    parser.add_argument("--cases", type=int, choices=(50, 200), default=50)
    support.receipt_arguments(parser)
    provenance.arguments(parser)
    args = parser.parse_args()
    if git("status", "--porcelain", "--untracked-files=no"):
        parser.error("tracked files must be clean for the whole matrix")
    args.evidence, args.cache = args.evidence.resolve(), args.cache.resolve()
    if args.evidence.exists() or args.cache.exists():
        parser.error("fresh evidence and cache paths are required")
    wrapper = strict_wrapper()
    sources = [Path(__file__), Path(support.__file__), Path(provenance.__file__), WRAPPER, wrapper.S2_WRAPPER,
               ROOT / "scripts/build-slot.sh", *HARNESSES.values(),
               *(ROOT / path for path in wrapper.HARNESSES.values())]
    try:
        receipt = provenance.manifest(ROOT, args.old, args.core, args, sources, ("nice", "taskset"))
        provenance.bind_scope(receipt, provenance.scope(args.cases, final=args.cases == 200))
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        parser.error(str(error))
    oracles = {"old": receipt["oracles"]["old"], "new": receipt["oracles"]["core"]}
    receipt["oracles"] = oracles
    commit = receipt["source_commit"]
    args.evidence.mkdir(parents=True)
    args.cache.mkdir(parents=True)
    manifest = {**receipt, "cases_per_kind": args.cases, "scope": provenance.scope(args.cases, final=args.cases == 200),
                "component": "fuzz-matrix", "kinds": list(KINDS), "jobs": args.jobs}
    (args.evidence / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    capture = support.Capture(args.evidence / "matrix-processes", ROOT)

    def run(kind):
        command = [str(ROOT / "scripts/build-slot.sh"), "build", "--", receipt["tools"]["nice"]["path"], "-n", "10",
                   sys.executable, str(Path(__file__).resolve()), "--worker", "--kind", kind, "--cases", str(args.cases),
                   "--seed", str(4401 + KINDS.index(kind)),
                   "--old", oracles["old"]["path"], "--new", oracles["new"]["path"],
                   "--evidence", str(args.evidence / kind), "--cache-root", str(args.cache / kind)]
        if kind in HARNESSES:
            command.extend(["--harness", str(HARNESSES[kind])])
        with (args.evidence / f"{kind}.log").open("x") as stream:
            stream.write(f"source_commit={commit}\n$ {shlex.join(command)}\n")
            stream.flush()
            # Inner commands have 60s/30s limits; this cap also owns an accidentally stuck worker.
            try:
                result = capture.run(command, cwd=ROOT, stdout=stream, stderr=subprocess.STDOUT, timeout=7200)
            except subprocess.TimeoutExpired as error:
                stream.write((error.stdout or b"").decode("utf-8", "replace"))
                stream.write("\nworker timeout; raw output and process-group cleanup retained\n")
                result = subprocess.CompletedProcess(command, 124)
            stream.write(f"\nexit={result.returncode}\n")
        path = args.evidence / kind / "summary.json"
        summary = json.loads(path.read_text()) if path.exists() else {"missing_summary": True}
        passed = qualified_kind(result.returncode, summary, kind, args.cases, oracles)
        print(f"{kind}: {'PASS' if passed else 'STOP'}; {summary.get('elapsed_seconds', '?')}s", flush=True)
        return kind, {"passed": passed, "summary": summary}

    order = ("number",) + tuple(kind for kind in KINDS if kind != "number")
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as workers:
        results = dict(workers.map(run, order))
    unchanged = provenance.unchanged(ROOT, receipt)
    same_oracles = all(identity(Path(item["path"])) == item for item in oracles.values())
    input_error = None
    try:
        same_inputs = all(item["passed"] and provenance.fuzz_unchanged(item["summary"]) for item in results.values())
    except (OSError, ValueError, KeyError) as failure:
        input_error, same_inputs = str(failure), False
    summary = {**manifest, "source_unchanged": unchanged, "oracles_unchanged": same_oracles,
               "inputs_unchanged": same_inputs, "input_error": input_error,
               "results": results, "qualified": unchanged and same_oracles and same_inputs and all(item["passed"] for item in results.values())}
    (args.evidence / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    return 0 if summary["qualified"] else 1


if __name__ == "__main__":
    raise SystemExit(worker(sys.argv[2:]) if len(sys.argv) > 1 and sys.argv[1] == "--worker" else main())
