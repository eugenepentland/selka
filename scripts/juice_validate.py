#!/usr/bin/env python3
"""Qualify real collectors on controlled changes, including unrelated CPU load.

Run through scripts/build-slot.sh build. All mutations are in private copies;
the output directory must be new. Timings are loop-duration observations only.
"""
from __future__ import annotations

import argparse
import contextlib
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time

from juice_tool.collectors import Collector
from juice_tool.common import read_json, write_json
from juice_tool.engine import capture
from juice_tool.manifest import Manifest
from juice_tool.report import compare_records, load_record, render, validate_scenarios

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--valgrind", default="valgrind")
    parser.add_argument("--compiler", type=Path)
    parser.add_argument("--base-compiler", type=Path)
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    project = output / "native"
    shutil.copytree(ROOT / "examples/juice/native", project)
    original = (project / "kernel.c").read_text()
    manifest_text = (project / "juice.toml").read_text()
    native = Collector("perf")
    reference = Collector("callgrind", native.cpu, valgrind=args.valgrind)
    cachegrind = Collector("cachegrind", native.cpu, valgrind=args.valgrind)
    results = {"version": "juice-qualification-v1", "checks": {}, "reports": {}, "records": {},
               "scope": "work sensitivity and repeatability; no elapsed-time calibration"}

    def record(label, collector=native, root=project, compiler=None, tier="all"):
        options = argparse.Namespace(name=label, repeats=3, tier=tier, workload=None,
                    cache_dir=output / "cache", compiler=str(compiler) if compiler else None, static=compiler is not None)
        start = time.monotonic()
        path = capture(Manifest(root / "juice.toml"), collector, options)
        results["records"][label] = {"path": str(path.relative_to(output)), "seconds_including_build": time.monotonic() - start}
        return load_record(path)

    def compare(label, base, candidate, mode="combined"):
        report = compare_records(base, candidate, mode)
        write_json(output / (label + ".json"), report)
        (output / (label + ".md")).write_text(render(report))
        results["reports"][label] = {k: {"juice": v["juice"], "assessment": v["assessment"], "risks": v["risks"]}
                                      for k, v in report["workloads"].items()}
        return report

    baseline = record("native-baseline")
    repeat = record("native-repeat")
    same = compare("identical", baseline, repeat)
    results["checks"]["identical_build"] = all(c["assessment"] == "unchanged" for c in same["workloads"].values())

    # These processes are unrelated to the counted program and pinned to the
    # exact same non-reserved CPU, so they force scheduling interference.
    burners = [subprocess.Popen([sys.executable, "-c", "while True: pass"],
               preexec_fn=lambda: os.sched_setaffinity(0, {native.cpu}),
               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL) for _ in range(2)]
    try:
        loaded = record("native-loaded")
    finally:
        for process in burners:
            process.terminate()
        for process in burners:
            process.wait(timeout=10)
    load = compare("under-load", baseline, loaded)
    results["checks"]["unrelated_cpu_load"] = all(c["assessment"] == "unchanged" for c in load["workloads"].values())

    (project / "kernel.c").write_text(original.replace("#define SLOW 1", "#define SLOW 0"))
    improved = record("native-improved")
    improvement = compare("application-improvement", baseline, improved, "application")
    results["checks"]["algorithm_improvement"] = all(c["juice"] < 75 for c in improvement["workloads"].values())
    scenario_check = validate_scenarios(improvement, improvement)
    write_json(output / "scenario-validation.json", scenario_check)
    results["checks"]["short_scenario_agreement"] = scenario_check["passed"]
    stable_reference = record("reference-improved", reference)
    repeat_reference = record("reference-repeat", reference)
    ref_repeat = compare("reference-identical", stable_reference, repeat_reference)
    results["checks"]["software_count_repeatability"] = all(c["assessment"] == "unchanged" for c in ref_repeat["workloads"].values())

    (project / "kernel.c").write_text(original.replace("#define SLOW 1", "#define SLOW 0").replace("#define ATOMIC 0", "#define ATOMIC 1"))
    atomic = record("reference-atomic", reference)
    atomic_report = compare("atomic-regression", stable_reference, atomic)
    results["checks"]["atomic_sensitivity"] = all(
        c["metrics"]["atomics"]["candidate"]["median"] > c["metrics"]["atomics"]["base"]["median"]
        and c["risks"] for c in atomic_report["workloads"].values())

    (project / "kernel.c").write_text(original.replace("#define SLOW 1", "#define SLOW 0").replace("#define EXTRA_COPY 0", "#define EXTRA_COPY 1"))
    copying = record("native-copy")
    copy_report = compare("copy-regression", improved, copying, "application")
    results["checks"]["extra_copy_sensitivity"] = all(c["juice"] > 110 for c in copy_report["workloads"].values())

    (project / "kernel.c").write_text(original)
    (project / "juice.toml").write_text(manifest_text.replace('"-O2"', '"-O0"'))
    unoptimized = record("native-unoptimized")
    backend = compare("backend-regression", baseline, unoptimized, "backend")
    results["checks"]["backend_sensitivity"] = all(c["juice"] > 120 for c in backend["workloads"].values())
    (project / "juice.toml").write_text(manifest_text)

    # A function region counts the measured phase, excluding setup. It still
    # executes setup; skipping expensive setup requires a saved-input harness.
    (project / "juice.toml").write_text(manifest_text.replace('unit = "record"', 'region = "process_records"\nunit = "record"'))
    region = record("reference-region", reference)
    results["checks"]["phase_collection"] = all(c["metrics"]["instructions"]["median"] > 0 and
        any("process_records" in f["function"] for f in c["functions"]) for c in region["workloads"].values())
    (project / "juice.toml").write_text(manifest_text)
    cg = record("cachegrind", cachegrind, tier="quick")
    results["checks"]["cachegrind_source_attribution"] = any(
        f["file"].endswith("kernel.c") and f["instructions"] > 0 for f in cg["workloads"]["bits-quick"]["functions"])

    # A vectorizable reduction, keeping data shape and completed records fixed.
    vector = output / "vector"
    vector.mkdir()
    (vector / "kernel.c").write_text('''#include <stdint.h>
#include <stdio.h>
__attribute__((noinline)) uint64_t sum(const uint32_t *a) {
    uint64_t s=0; for(unsigned i=0;i<4096;i++) s+=a[i]; return s;
}
int main(void) {
    uint32_t a[4096]; for(unsigned i=0;i<4096;i++) a[i]=i%97;
    uint64_t s=0; for(unsigned r=0;r<128;r++) { __asm__ volatile("" ::: "memory"); s+=sum(a); }
    printf("%llu\\n", (unsigned long long)s); return 0;
}
''')
    vector_manifest = '''version=1
name="juice-vector-example"
sources=["kernel.c"]
[build]
compiler="cc"
command=["{compiler}", "-O3", "-g", "{root}/kernel.c", "-o", "{binary}"]
[[workloads]]
name="vector"
unit="record"
units=524288
expected_stdout="25060224\\n"
'''
    (vector / "juice.toml").write_text(vector_manifest)
    vectorized = record("vectorized", root=vector)
    (vector / "juice.toml").write_text(vector_manifest.replace('"-O3"', '"-O3", "-fno-tree-vectorize"'))
    scalar = record("scalar", root=vector)
    vector_report = compare("vectorization-regression", vectorized, scalar, "backend")
    results["checks"]["missed_vectorization"] = vector_report["workloads"]["vector"]["juice"] > 120

    if args.compiler:
        selka = output / "selka"
        shutil.copytree(ROOT / "examples/juice/selka", selka)
        my_base = record("selka-baseline", root=selka, compiler=args.compiler)
        my_repeat = record("selka-repeat", root=selka, compiler=args.compiler)
        my_same = compare("selka-identical", my_base, my_repeat, "application")
        results["checks"]["selka_repeatability"] = all(c["assessment"] == "unchanged" for c in my_same["workloads"].values())
        program = (selka / "main.selka").read_text()
        replacement = '''    result = 0
    for i in range(count):
        result += i % 97
    return result
'''
        start = program.index("    values: list[int]")
        end = program.index("\ndef number(")
        (selka / "main.selka").write_text(program[:start] + replacement + "\n" + program[end:])
        my_edit = record("selka-improved", root=selka, compiler=args.compiler)
        my_report = compare("selka-copy-removal", my_base, my_edit, "application")
        results["checks"]["selka_counter_explanation"] = all(
            c["juice"] < 100 and c["semantic"]["status"] == "compatible" and "allocs" in c["semantic"]["totals"]
            for c in my_report["workloads"].values())
        my_scenarios = validate_scenarios(my_report, my_report)
        write_json(output / "selka-scenario-validation.json", my_scenarios)
        results["checks"]["selka_short_scenario_agreement"] = my_scenarios["passed"]
        if args.base_compiler:
            (selka / "main.selka").write_text(program)
            (selka / "juice.toml").write_text((selka / "juice.toml").read_text().replace(
                "core-count-p1-c26c95de7", "core-count-main-35df839be"))
            pre_p1 = record("pre-p1", root=selka, compiler=args.base_compiler)
            p1_report = compare("p1-backend-change", pre_p1, my_base, "backend")
            results["checks"]["p1_counter_contract_boundary"] = all(
                c["semantic"]["status"] == "incompatible" for c in p1_report["workloads"].values())
    results["passed"] = all(results["checks"].values())
    write_json(output / "qualification.json", results)
    print(results["checks"])
    return int(not results["passed"])


if __name__ == "__main__":
    raise SystemExit(main())
