#!/usr/bin/env python3
"""Full S4 conformance: strict statuses, actual execution, retired arenas only.

The historical sweep already ran propagation's nine tests; its R-3 exclusion
label was stale. This adapter removes that label and always forces Core tests,
so cached successes cannot stand in for leak or fact verification.
"""
import importlib.util
import argparse
from collections import Counter
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import threading

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))
import qualification_support as support
import qualification_provenance as provenance
INTEGRATION = ROOT.parent / "codex-new-core-s4-integration"
BASELINE = INTEGRATION / "experiments/new-core-s4-20261006/integration/base-core-run01/full-conformance.log"
CROSSCHECK = INTEGRATION / "experiments/new-core-s3-20261006/wave-x/integration/final-merge-run02/full-conformance.log"


def imported(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def validate_report(value, status, allow_cached=True, selected=lambda name: True):
    """Validate the wire report before any dictionary can collapse duplicate tests."""
    if not isinstance(value, dict) or value.get("version") != "native-tests-v1":
        raise ValueError("invalid native test report version/schema")
    tests = value.get("tests")
    if not isinstance(tests, list):
        raise ValueError("tests must be an array")
    names, counts = set(), Counter()
    allowed = {"passed", "cached", "failed", "skipped", "unsupported"}
    for test in tests:
        if not isinstance(test, dict):
            raise ValueError("test must be an object")
        name, verdict = test.get("name"), test.get("status")
        if not isinstance(name, str) or not name or name in names:
            raise ValueError("invalid or duplicate test name")
        if not isinstance(verdict, str) or verdict not in allowed:
            raise ValueError("invalid test status")
        if any(field in test and not isinstance(test[field], str) for field in ("reason", "at")):
            raise ValueError("test reason/position must be strings")
        names.add(name)
        counts[verdict] += 1
        if selected(name) and verdict == "unsupported":
            raise ValueError("selected test is unsupported")
        if selected(name) and verdict == "cached" and not allow_cached:
            raise ValueError("forced conformance test did not execute")
    for verdict in allowed:
        total = value.get(verdict, 0) if verdict == "unsupported" else value.get(verdict)
        if type(total) is not int or total < 0 or total != counts[verdict]:
            raise ValueError(f"report total disagrees with {verdict} verdicts")
    if "executed" in value:
        executed = value["executed"]
        if type(executed) is not int or executed != counts["passed"] + counts["failed"]:
            raise ValueError("invalid executed total")
    for field in ("dropped", "unloaded"):
        if field in value and (type(value[field]) is not int or value[field] != 0):
            raise ValueError(f"invalid or nonzero {field} total")
    expected = 1 if counts["failed"] else (0 if tests else 3)
    if status != expected:
        raise ValueError("compiler status disagrees with test report")
    return counts


def checked_report(original, done, what, selected):
    if done is None:
        return original(done, what)
    value = original(done, what)
    if isinstance(value, str):
        return value
    try:
        validate_report(value, done.returncode, allow_cached=not what.startswith("new core"), selected=selected)
    except (ValueError, TypeError) as error:
        return f"{what}: invalid report: {error}"
    return value


def baseline_table(text):
    source = re.search(r"^source_commit=([0-9a-f]{40})$", text, re.MULTILINE)
    if not source:
        raise ValueError("baseline must identify its frozen source commit")
    counts = {}
    for line in text.splitlines():
        found = re.fullmatch(r"(\S+)\s+(\d+)\s+\|\s*(\d+)\s+(\d+)\s+(\d+)\s+\|\s*(\d+)\s+(\d+)\s+(\d+)\s*", line)
        if not found:
            continue
        name, *numbers = found.groups()
        total, dm, dx, du, rm, rx, ru = map(int, numbers)
        if name in counts or (dm, dx, du, rm, rx, ru) != (total, 0, 0, total, 0, 0):
            raise ValueError("baseline has duplicate or nonqualifying file rows")
        counts[name] = total
    if not counts or sum(counts.values()) != 1518:
        raise ValueError("authoritative baseline must contain exactly 1518 comparisons")
    return {"source_commit": source.group(1), "counts": counts}


def baseline_inputs(root, commit):
    """Bind actual corpus bytes, including case/provider assets, to the baseline tree."""
    entries = support.git(root, "ls-tree", "-r", commit, "--", "tests/lang").splitlines()
    expected = {}
    algorithm = support.git(root, "rev-parse", "--show-object-format")
    for entry in entries:
        info, name = entry.split("\t", 1)
        mode, kind, oid = info.split()
        if kind != "blob":
            raise ValueError("unexpected non-file corpus entry")
        path = root / name
        data = os.readlink(path).encode() if mode == "120000" else path.read_bytes()
        blob = hashlib.new(algorithm, f"blob {len(data)}\0".encode() + data).hexdigest()
        if blob != oid:
            raise ValueError(f"baseline input bytes changed: {name}")
        expected[name] = support.identity(path)
    actual = {str(path.relative_to(root)) for path in (root / "tests/lang").rglob("*") if path.is_file()}
    if actual != set(expected):
        raise ValueError("corpus file inventory differs from the frozen baseline")
    return expected


def coverage(rows, expected, modes, expected_total):
    """Per-file coverage distinguishes retained support rows from lost selections."""
    names = [row["file"] for row in rows]
    if len(names) != len(set(names)) or set(names) != set(expected):
        raise ValueError("selected file coverage differs or has duplicate rows")
    if expected_total <= 0:
        raise ValueError("an aggregate empty selection cannot qualify")
    total = 0
    for row in rows:
        wanted = expected[row["file"]]
        if wanted is None and row["tests"] == 0:
            raise ValueError("zero-test files require a retained baseline support row")
        if wanted is not None and row["tests"] != wanted:
            raise ValueError(f"{row['file']}: selected test count differs from baseline")
        if row["problems"] or set(row["modes"]) != set(modes):
            raise ValueError(f"{row['file']}: missing mode or comparison problem")
        total += row["tests"]
        for mode in modes:
            stats = row["modes"][mode]
            if (stats["match"], stats["mismatch"], stats["unsupported"]) != (row["tests"], 0, 0):
                raise ValueError(f"{row['file']}: {mode} does not cover every selected test")
    if total != expected_total:
        raise ValueError(f"expected {expected_total} comparisons per mode, observed {total}")


def selection(sweep, args, baseline, expected_total):
    if args.set == "all":
        names = [sweep.short(str(path)) for path in sorted(Path(sweep.LANG).rglob("*.my"))]
    elif args.set == "clean13":
        names = sweep.CLEAN13
    elif args.set == "excluded":
        names = list(sweep.EXCLUDED)
    elif args.files:
        names = [sweep.short(sweep.resolve(name)) for name in args.files]
    else:
        names = sweep.S1
    if not args.include_arena:
        names = [name for name in names if name not in sweep.ARENA_FILES]
    if len(names) != len(set(names)):
        raise ValueError("duplicate selected files")
    if args.set == "all" and set(names) != set(baseline):
        raise ValueError("full discovered file set differs from frozen baseline")
    expected = {name: baseline.get(name) for name in names}
    if any(count is None for count in expected.values()) and expected_total is None:
        raise ValueError("nonbaseline selections require --expected-tests")
    total = expected_total if expected_total is not None else sum(expected.values())
    if total <= 0:
        raise ValueError("an aggregate empty selection cannot qualify")
    modes = args.modes.split(",")
    if args.set == "all" and (total != 1518 or len(modes) != 2 or set(modes) != {"debug", "release"}):
        raise ValueError("full conformance requires debug/release and exactly 1518 comparisons each")
    if args.set == "all" and not (args.leakcheck and args.verify):
        raise ValueError("full conformance requires leakcheck and verify")
    return expected, total


def arguments(argv=None):
    """Keep historical flags intact while parsing this adapter's receipt flags."""
    parser = argparse.ArgumentParser(add_help=False, allow_abbrev=False)
    parser.add_argument("--evidence", type=Path, required=True)
    parser.add_argument("--baseline", type=Path, default=BASELINE)
    parser.add_argument("--baseline-crosscheck", type=Path, default=CROSSCHECK)
    parser.add_argument("--expected-tests", type=int, help="Required for nonbaseline selections; otherwise baseline counts apply")
    support.receipt_arguments(parser)
    provenance.arguments(parser)
    options, historical = parser.parse_known_args(argv)
    return parser, options, historical


def main():
    parser, options, historical = arguments()
    if options.evidence.exists() or support.git(ROOT, "status", "--porcelain", "--untracked-files=no"):
        parser.error("fresh evidence and clean frozen tracked sources are required")
    try:
        baseline = baseline_table(options.baseline.read_text())
        crosscheck = baseline_table(options.baseline_crosscheck.read_text())
        if baseline["counts"] != crosscheck["counts"]:
            raise ValueError("retained S3/S4 per-file baselines disagree")
        if support.git(ROOT, "diff", "--name-only", baseline["source_commit"], "HEAD", "--", "tests/lang"):
            raise ValueError("tests/lang changed since the retained authoritative baseline")
        input_identities = baseline_inputs(ROOT, baseline["source_commit"])
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        parser.error(str(error))
    options.evidence.mkdir(parents=True)
    for name, path in (("baseline.log", options.baseline), ("crosscheck.log", options.baseline_crosscheck)):
        (options.evidence / name).write_bytes(path.read_bytes())
    inputs = support.snapshot(ROOT / "tests/lang", options.evidence / "inputs")
    sweep = imported("s4_conformance", ROOT / "experiments/new-core-s1-20261005/conformance.py")
    original = sweep.parse
    selected = lambda name: sweep.keep(name, "--include-arena" in historical)
    sweep.parse = lambda done, what: checked_report(original, done, what, selected)
    sweep.EXCLUDED.pop("migrated/propagation", None)
    parent = sweep.Tool
    original_compare = sweep.compare
    rows, receipt, state = [], {}, {}
    lock = threading.Lock()

    def compared(*args, **kwargs):
        row = original_compare(*args, **kwargs)
        with lock:
            rows.append(row)
        return row

    sweep.compare = compared

    class Fresh(parent):
        def __init__(self, args):
            super().__init__(args)
            state["expected"], state["total"] = selection(sweep, args, baseline["counts"], options.expected_tests)
            state["modes"] = args.modes.split(",")
            if not state["modes"] or len(set(state["modes"])) != len(state["modes"]) or set(state["modes"]) - {"debug", "release"}:
                raise ValueError("modes must be distinct debug/release selections")
            receipt.update(provenance.manifest(ROOT, args.mylang, args.core, options,
                [Path(__file__), Path(support.__file__), Path(provenance.__file__), Path(sweep.__file__), options.baseline, options.baseline_crosscheck], ("taskset",)))
            provenance.bind_scope(receipt, "final" if args.set == "all" else "diagnostic")
            provenance.bind_compilers(self, receipt)
            receipt.update(baseline=baseline, inputs=inputs, selected=state["expected"],
                           baseline_inputs=input_identities,
                           baseline_tests_tree=support.git(ROOT, "rev-parse", baseline["source_commit"] + ":tests/lang"),
                           current_tests_tree=support.git(ROOT, "rev-parse", "HEAD:tests/lang"),
                           expected_tests=state["total"], modes=state["modes"],
                           leakcheck=args.leakcheck, verify=args.verify,
                           scope="final" if args.set == "all" else "diagnostic", component="conformance")
            (options.evidence / "manifest.json").write_text(json.dumps(receipt, indent=2) + "\n")
            self.capture = support.Capture(options.evidence / "processes", ROOT)

        def run(self, argv, timeout=600, env=None):
            if len(argv) > 1 and argv[0] == self.core and argv[1] == "test":
                argv = [*argv, "--force"]
            if self.cpus and os.path.exists("/usr/bin/taskset"):
                argv = [receipt["tools"]["taskset"]["path"], "-c", self.cpus, *argv]
            try:
                return self.capture.run(argv, capture_output=True, text=True, timeout=timeout, env=env)
            except subprocess.TimeoutExpired as error:
                return subprocess.CompletedProcess(argv, 124, error.stdout.decode("utf-8", "replace"), error.stderr.decode("utf-8", "replace"))

    sweep.Tool = Fresh
    original_argv = sys.argv
    status, error = 1, None
    try:
        sys.argv = [original_argv[0], *historical]
        status = sweep.main()
        coverage(rows, state["expected"], state["modes"], state["total"])
        if baseline_inputs(ROOT, baseline["source_commit"]) != input_identities:
            raise ValueError("corpus identities changed during qualification")
        if not provenance.unchanged(ROOT, receipt):
            raise ValueError("compiler/source/tool/harness identities changed during qualification")
    except (OSError, ValueError, KeyError, subprocess.SubprocessError) as failure:
        error = str(failure)
        print(f"STOP: {error}", file=sys.stderr)
    finally:
        sys.argv = original_argv
    summary = {**receipt, "results": rows, "error": error, "qualified": status == 0 and error is None}
    (options.evidence / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    return 0 if summary["qualified"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
