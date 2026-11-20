#!/usr/bin/env python3
"""Run the fixed 60 Lox/EDA cases using ordinary build admission.

The caller owns admission. Inputs are a frozen, privately migrated copy of the
parity source-003 applications. Output and counters stay under ignored scratch.
This is an observation at the current host load, without timing qualification.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
import os
from pathlib import Path
import shutil
import statistics
import subprocess
import tarfile
import time

ROOT = Path(__file__).resolve().parents[1]
PARITY = ROOT / "experiments/lox-eda-parity-20261013"
HISTORICAL = ROOT / "experiments/lox-eda-improvements-20261012"
INPUTS = ROOT / "experiments/lox-eda-zero-rc-20261012"
PERFORMANCE_LIMIT = 1.05


def positive_seconds(raw: object) -> float | None:
    try:
        value = float(raw) if type(raw) in (str, int, float) else None
    except (ValueError, OverflowError):
        return None
    return value if value is not None and math.isfinite(value) and value > 0 else None


def baseline_protocol(archive: Path) -> dict:
    """Read CPU and per-case counts; this does not recreate alternating arms."""
    cases = {}
    with tarfile.open(archive) as records:
        for record in records:
            if ("/runtime/" not in record.name or ".chunk" not in record.name
                    or not record.name.endswith(".json") or record.name.endswith(".spec.json")):
                continue
            document = json.load(records.extractfile(record))
            for setting in ("cpu", "warmups", "rounds"):
                if type(document.get(setting)) is not int or document[setting] < 0:
                    raise ValueError(f"invalid historical sampler {setting}")
            case = document["spec"]["cell"]
            protocol = cases.setdefault(case, {"cpus": set(), "warmups": 0, "rounds": 0})
            protocol["cpus"].add(document["cpu"])
            protocol["warmups"] += document["warmups"]
            protocol["rounds"] += document["rounds"]
    settings = {(tuple(sorted(case["cpus"])), case["warmups"], case["rounds"])
                for case in cases.values()}
    if len(cases) != 60 or len(settings) != 1:
        raise ValueError("historical sampler protocol is missing or inconsistent")
    cpus, warmups, rounds = settings.pop()
    if len(cpus) != 1 or rounds == 0:
        raise ValueError("historical sampler needs one fixed CPU and measured rounds")
    return {"cpu": cpus[0], "warmups": warmups, "rounds": rounds,
            "source": str(archive), "source_sha256": digest(archive)}


def performance_result(rows: list[dict], modes: list[str],
                       baseline: dict[str, dict]) -> dict:
    """Qualify every uncensored historical case; missing observations fail closed."""
    comparable, censored, invalid_baseline = {}, [], []
    for case, row in baseline.items():
        raw = row.get("candidate_wall_seconds")
        if raw == "":
            censored.append(case)
            continue
        seconds = positive_seconds(raw)
        if seconds is None:
            invalid_baseline.append(case)
        else:
            comparable[case] = seconds
    expected = {(case, mode) for case in comparable for mode in modes}
    observed, slow, invalid = set(), [], []
    for row in rows:
        key = (row["case"], row["mode"])
        if key not in expected:
            continue
        seconds = row.get("seconds")
        if (key in observed or not row["correct"] or type(seconds) not in (int, float)
                or not math.isfinite(seconds) or seconds <= 0):
            invalid.append(list(key))
        else:
            ratio = seconds / comparable[key[0]]
            if not math.isfinite(ratio):
                invalid.append(list(key))
            elif ratio > PERFORMANCE_LIMIT:
                slow.append({"case": key[0], "mode": key[1], "ratio": ratio})
        observed.add(key)
    missing = sorted(expected - observed)
    return {"limit": PERFORMANCE_LIMIT, "comparable": len(expected),
            "historically_censored": sorted(censored), "invalid_baseline": sorted(invalid_baseline),
            "missing": missing, "invalid": invalid, "slow": slow,
            "passed": bool(expected) and not (missing or invalid or slow or invalid_baseline)}


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def check_goldens(root: Path, cases: list[dict]) -> None:
    for case in cases:
        folder = root / "cases" / case["id"]
        if digest(folder / "model.sexp") != case["model_sha256"]:
            raise ValueError(f"changed EDA input: {case['id']}")
        actual = {str(path.relative_to(folder / "expected")): digest(path)
                  for path in (folder / "expected").rglob("*") if path.is_file()}
        if actual != case["outputs"]:
            raise ValueError(f"changed EDA golden output: {case['id']}")


def build(compiler: Path, source: Path, work: Path, modes: list[str],
          environment: dict[str, str]) -> dict[tuple[str, str, bool], Path]:
    binaries = {}
    for app in ("lox", "eda"):
        for mode in modes:
            for counted in (False, True):
                name = f"{app}-{mode}" + ("-counted" if counted else "")
                binary = work / name
                flags = ["--experimental-zero-rc"] if mode == "zero-rc" else []
                if counted:
                    flags.append("--counters")
                command = [str(compiler), "build", str(source / app / "main.selka"),
                           "--release", "--cache-dir", str(work / "build-cache"),
                           "-o", str(binary), *flags]
                print("building", name, flush=True)
                result = subprocess.run(command, cwd=ROOT, env=environment,
                                        capture_output=True, text=True)
                if result.returncode:
                    raise RuntimeError(f"build {name}: {result.stdout}{result.stderr}")
                binaries[app, mode, counted] = binary
    return binaries


def case_arguments(spec: dict, golden: Path, output: Path) -> list[str]:
    result = []
    for value in spec["arms"]["selka-zero-rc"][1:]:
        if value == spec.get("out_dir"):
            result.append(str(output))
        elif "/golden/" in value:
            result.append(str(golden / value.split("/golden/", 1)[1]))
        elif "/bench/inputs/" in value:
            result.append(str(INPUTS / "bench/inputs" / Path(value).name))
        else:
            result.append(value)
    return result


def execute(binary: Path, arguments: list[str], environment: dict[str, str],
            output: Path, spec: dict, golden_case: dict | None,
            timeout: float) -> dict:
    if output.exists():
        shutil.rmtree(output)
    output.mkdir(parents=True)
    started = time.monotonic()
    try:
        result = subprocess.run([str(binary), *arguments], cwd=output,
                                env=environment, capture_output=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        return {"status": "timeout", "seconds": None}
    elapsed = time.monotonic() - started
    if result.returncode:
        return {"status": "exit", "exit_code": result.returncode,
                "stderr": result.stderr.decode(errors="replace")[-1000:], "seconds": elapsed}
    if golden_case:
        actual = {str(path.relative_to(output)): digest(path)
                  for path in output.rglob("*") if path.is_file()}
        correct = actual == golden_case["outputs"]
    else:
        expected = HISTORICAL / "input-recovery/expected" / Path(spec["expected_stdout"]).name
        correct = result.stdout == expected.read_bytes()
    return {"status": "ok" if correct else "output_mismatch", "seconds": elapsed}


def counter_values(path: Path, layout: str) -> dict:
    document = json.loads(path.read_text())
    if document["version"] != "selka-counters-v1":
        raise ValueError("unsupported counter document version")
    totals, kinds = document["totals"], document["kinds"]
    functions, sites = document["functions"], document["sites"]
    if not isinstance(totals, dict) or not isinstance(kinds, dict):
        raise ValueError("counter totals and kinds must be objects")
    if not isinstance(functions, list) or not functions or not isinstance(sites, list):
        raise ValueError("counter functions/sites are missing or malformed")

    def number(record: dict, name: str) -> int:
        value = record[name]
        if type(value) is not int or value < 0:
            raise ValueError(f"invalid nonnegative counter: {name}")
        return value

    common = ("calls", "allocs", "alloc_bytes", "frees", "free_bytes",
              "peak_live_bytes", "live_bytes_at_exit")
    observed = {name: number(totals, name) for name in common}
    if observed["calls"] == 0 or observed["allocs"] == 0:
        raise ValueError("application counters contain no calls or allocations")
    rc_totals = ("runtime_retains", "runtime_releases", "shared_retains",
                 "shared_releases", "share_marks", "share_bytes")
    rc_kinds = ("retain", "release", "unique_test")
    retired_kinds = (*rc_kinds, "release_unique")
    ordinary_totals = set("""calls allocs alloc_bytes frees free_bytes list_grows
        list_grow_bytes reallocs realloc_added_bytes realloc_moves realloc_moved_bytes
        list_copies list_copy_bytes dict_copies dict_copy_bytes buffer_copies
        buffer_copy_bytes text_copies text_copy_bytes dict_grows dict_grow_bytes
        buffer_grows buffer_grow_bytes text_grows text_grow_bytes text_appends
        text_append_bytes buffer_pushes buffer_appends buffer_append_bytes""".split())
    ordinary_kinds = set("""list_copy dict_copy buffer_copy text_copy record_copy
        list_push element_load element_store bounds_check overflow_check
        division_check shift_check other_check""".split())
    expected_totals = ordinary_totals | {"peak_live_bytes", "live_bytes_at_exit"}
    expected_kinds = ordinary_kinds
    if layout == "legacy":
        expected_totals |= set(rc_totals)
        expected_kinds |= set(retired_kinds)
    if set(totals) != expected_totals or set(kinds) != expected_kinds:
        raise ValueError(f"counter fields do not match the {layout} layout")
    for name in totals:
        number(totals, name)
    for kind in kinds.values():
        for name in ("count", "bytes", "extra"):
            number(kind, name)
    for function in functions:
        expected = expected_totals - {"peak_live_bytes", "live_bytes_at_exit"}
        if not isinstance(function, dict) or set(function) != expected | {"name"}:
            raise ValueError("invalid per-function counter fields")
        if not isinstance(function["name"], str):
            raise ValueError("invalid counter function name")
        for name in expected:
            number(function, name)
    for site in sites:
        if not isinstance(site, dict) or site["kind"] not in kinds:
            raise ValueError("invalid counter site kind")
        for name in ("count", "bytes", "extra"):
            number(site, name)
    if layout == "legacy":
        events = {name: number(totals, name) for name in rc_totals}
        zero_fields = list(events.values())
        for name in retired_kinds:
            values = [number(kinds[name], field) for field in ("count", "bytes", "extra")]
            # A proved-unique release is count-free destruction, not an RC event.
            if name != "release_unique":
                events[name] = values[0]
                zero_fields.extend(values)
        for function in functions:
            zero_fields.extend(number(function, name) for name in rc_totals)
        for site in sites:
            if site["kind"] in rc_kinds:
                zero_fields.extend(number(site, name) for name in ("count", "bytes", "extra"))
        zero_rc = all(value == 0 for value in zero_fields)
    elif layout == "retired":
        if any(name in totals for name in rc_totals) or any(name in kinds for name in retired_kinds):
            raise ValueError("retired RC totals or kinds remain in the counter document")
        if any(name in function for function in functions for name in rc_totals):
            raise ValueError("retired RC fields remain in function counters")
        if any(site["kind"] in retired_kinds for site in sites):
            raise ValueError("retired RC site kind remains in the counter document")
        events, zero_rc = {}, True
    else:
        raise ValueError(f"unknown counter layout: {layout}")
    return {"layout": layout, "rc_events": sum(events.values()), "events": events,
            "zero_rc": zero_rc, "observed": observed,
            "live_bytes_at_exit": observed["live_bytes_at_exit"]}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler", type=Path, required=True)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--work", type=Path, required=True)
    parser.add_argument("--golden", type=Path,
                        help="frozen golden input directory (default: SOURCE/golden)")
    parser.add_argument("--mode", action="append", choices=("default", "zero-rc"))
    parser.add_argument("--require-zero", action="append", choices=("default", "zero-rc"))
    parser.add_argument("--counter-layout", choices=("legacy", "retired"), default="legacy",
                        help="require the pre-retirement or retired counter fields")
    parser.add_argument("--rounds", type=int, default=3)
    parser.add_argument("--warmups", type=int, default=0,
                        help="verified warmup runs per case/mode, excluded from medians")
    parser.add_argument("--cpu", type=int,
                        help="pin native sampling to this CPU (historical parity used CPU 8)")
    parser.add_argument("--qualify-performance", action="store_true",
                        help="also fail unless every comparable required-mode median is <=1.05x parity")
    parser.add_argument("--timeout", type=float, default=120)
    args = parser.parse_args()
    for needed in (PARITY, HISTORICAL, INPUTS):
        if not needed.is_dir():
            raise SystemExit(f"ownership_applications.py: {needed.relative_to(ROOT)} is missing: the internal experiments records are not in the public tree")
    if args.rounds < 1:
        parser.error("--rounds must be positive")
    if args.warmups < 0:
        parser.error("--warmups must be nonnegative")
    if args.cpu is not None and args.cpu not in os.sched_getaffinity(0):
        parser.error("--cpu is outside the available CPU affinity")
    modes = args.mode or ["default", "zero-rc"]
    require_zero = args.require_zero or ["zero-rc"]
    if not set(require_zero) <= set(modes):
        parser.error("every --require-zero mode must also be selected by --mode")
    if len(set(modes)) != len(modes):
        parser.error("duplicate --mode")
    protocol = None
    if args.qualify_performance:
        protocol = baseline_protocol(PARITY / "archives/runtime-004.tar.xz")
        if any(getattr(args, setting) != protocol[setting] for setting in ("cpu", "warmups", "rounds")):
            parser.error("O5 qualification requires recorded historical CPU and per-case counts: "
                         f"--cpu {protocol['cpu']} --warmups {protocol['warmups']} "
                         f"--rounds {protocol['rounds']}")
    work = args.work.resolve()
    work.mkdir(parents=True, exist_ok=False)
    golden = work / "golden"
    source = args.source.resolve()
    shutil.copytree(args.golden or source / "golden", golden)
    cases = json.loads((INPUTS / "eda/golden-manifest.json").read_text())["cases"]
    check_goldens(golden, cases)
    eda_cases = {case["id"]: case for case in cases}
    frozen = {path: path.read_bytes() for path in source.rglob("*")
              if path.is_file() and (path.suffix == ".selka" or path.name == "selka.json")}
    environment = dict(os.environ, SELKA_COMPILER_SHARED_CACHE="",
                       SELKA_TEST_SHARED_CACHE="", SELKA_STAGE_SHARED_CACHE="", SELKA_JOBS="4",
                       SELKA_CORE_RUNTIME_CACHE=str(work / "runtime"))
    environment.pop("SELKA_COUNTERS", None)
    environment.pop("SELKA_CORE_LEAKCHECK", None)
    environment.pop("SELKA_OPTIONS", None)
    binaries = build(args.compiler.resolve(), source, work, modes, environment)
    with (PARITY / "coordinator/runtime-004-summary/cases.csv").open() as handle:
        baseline = {row["case"]: row for row in csv.DictReader(handle)}
    specs = sorted((HISTORICAL / "specs").glob("*.json"))
    if len(specs) != 60:
        raise ValueError(f"expected 60 cases, got {len(specs)}")
    if args.cpu is not None:
        os.sched_setaffinity(0, {args.cpu})
    report = {"load_average": os.getloadavg(), "rounds": args.rounds,
              "warmups": args.warmups, "cpu_affinity": sorted(os.sched_getaffinity(0)),
              "performance_required": args.qualify_performance,
              "baseline_protocol": protocol,
              "sampling_order": "consecutive candidate runs per case and mode",
              "historical_sampling_order": "alternating candidate and reference arms",
              "baseline": str(PARITY / "coordinator/runtime-004-summary/cases.csv"),
              "baseline_sha256": digest(PARITY / "coordinator/runtime-004-summary/cases.csv"),
              "rows": []}
    for path in specs:
        spec = json.loads(path.read_text())
        app = spec["cell"].split("/")[0]
        golden_case = eda_cases[spec["cell"].split("/")[1]] if app == "eda" else None
        for mode in modes:
            output = work / "outputs" / mode / path.stem
            arguments = case_arguments(spec, golden, output)
            warmups = [execute(binaries[app, mode, False], arguments, environment,
                               output, spec, golden_case, args.timeout)
                       for _ in range(args.warmups)]
            runs = [execute(binaries[app, mode, False], arguments, environment,
                            output, spec, golden_case, args.timeout) for _ in range(args.rounds)]
            row = {"case": path.stem, "mode": mode, "warmups": warmups, "runs": runs}
            counter = work / f"{path.stem}-{mode}-counters.json"
            counted = execute(binaries[app, mode, True], arguments,
                              dict(environment, SELKA_COUNTERS=str(counter)),
                              output, spec, golden_case, args.timeout)
            row["counted"] = counted
            if counted["status"] == "ok" and counter.exists():
                row["counters"] = counter_values(counter, args.counter_layout)
                counter.unlink()
            if all(run["status"] == "ok" for run in runs):
                row["seconds"] = statistics.median(run["seconds"] for run in runs)
                previous = positive_seconds(baseline[path.stem].get("candidate_wall_seconds"))
                row["parity_ratio"] = row["seconds"] / previous if previous is not None else None
            row["correct"] = (all(run["status"] == "ok" for run in [*warmups, *runs])
                              and counted["status"] == "ok" and "counters" in row
                              and row["counters"]["live_bytes_at_exit"] == 0
                              and (mode not in require_zero or row["counters"]["zero_rc"]))
            report["rows"].append(row)
            (work / "results.json").write_text(json.dumps(report, indent=2) + "\n")
            print(path.stem, mode, "pass" if row["correct"] else "FAIL", flush=True)
    current = {path: path.read_bytes() for path in source.rglob("*")
               if path.is_file() and (path.suffix == ".selka" or path.name == "selka.json")}
    if current != frozen:
        raise ValueError("frozen application source changed")
    report["load_average_end"] = os.getloadavg()
    report["performance"] = performance_result(report["rows"], require_zero, baseline)
    (work / "results.json").write_text(json.dumps(report, indent=2) + "\n")
    passed = sum(row["correct"] for row in report["rows"])
    slow = len(report["performance"]["slow"])
    print(f"applications: {passed}/{len(report['rows'])} correct; {slow} observations over 1.05x parity")
    if args.qualify_performance:
        print("O5 performance:", "pass" if report["performance"]["passed"] else "FAIL")
    return int(passed != len(report["rows"])
               or (args.qualify_performance and not report["performance"]["passed"]))


if __name__ == "__main__":
    raise SystemExit(main())
