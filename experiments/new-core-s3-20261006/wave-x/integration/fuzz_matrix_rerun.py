#!/usr/bin/env python3
"""Rerun the kinds of a strict S3-X matrix that stopped on old-oracle compile timeouts.

Every rerun kind uses exactly the original matrix's command:
- the same per-kind seed (`3301 + KINDS.index(kind)`), case count and harness;
- the same explicit oracles;
- the same `nice -n 10` build-slot worker.

Each kind gets a fresh evidence directory and cache. The tool refuses to run unless:
- the source is the original matrix's commit, with a clean tracked tree;
- the oracles' SHA-256 match the original manifest;
- every rerun kind stopped *only* on `compile_timeout` failures.

It then writes `combined.json`, which joins the original passing kinds with the reruns
under the original pass rule. The original matrix evidence is never modified.
"""
import argparse
import concurrent.futures
import json
from pathlib import Path
import shlex
import subprocess
import sys

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import fuzz_matrix  # noqa: E402  (same registry, harnesses and identity check)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--matrix", type=Path, required=True, help="the original matrix evidence directory")
    parser.add_argument("--evidence", type=Path, required=True, help="fresh directory for the reruns")
    parser.add_argument("--jobs", type=int, choices=(1, 2, 3), default=3)
    args = parser.parse_args()
    root = fuzz_matrix.ROOT
    matrix = args.matrix.resolve()
    manifest = json.loads((matrix / "manifest.json").read_text())
    commit = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip()
    if commit != manifest["source_commit"] or subprocess.check_output(
            ["git", "status", "--porcelain", "--untracked-files=no"], cwd=root, text=True):
        parser.error("source must be the original matrix commit with a clean tracked tree")
    oracles = manifest["oracles"]
    for item in oracles.values():
        if fuzz_matrix.identity(Path(item["path"])) != item:
            parser.error(f"oracle changed since the matrix: {item['path']}")
    area = args.evidence.resolve()
    if area.exists() or not area.is_relative_to(root / "experiments"):
        parser.error("evidence must be a fresh directory below experiments")
    original = {}
    rerun = []
    for kind in fuzz_matrix.KINDS:
        summary = json.loads((matrix / kind / "summary.json").read_text())
        passed = (summary.get("qualified") is True and summary.get("accepted") == 200
                  and summary.get("cases_requested") == 200 and summary.get("oracles") == oracles)
        original[kind] = (passed, summary)
        if not passed:
            kinds = {failure.get("kind") for failure in summary.get("failures", [])}
            if kinds != {"compile_timeout"}:
                parser.error(f"{kind} stopped for {sorted(map(str, kinds))}, not only compile timeouts: not rerunnable")
            rerun.append(kind)
    area.mkdir(parents=True)
    cache = root / ".mylang-cache/wave-x/s3-x-rerun" / area.name
    print(f"evidence={area}\nsource_commit={commit}\nrerun={rerun}", flush=True)

    def run(kind):
        command = [str(root / "scripts/build-slot.sh"), "build", "--", "nice", "-n", "10",
                   sys.executable, str(HERE / "fuzz_qualification.py"), "--kind", kind,
                   "--cases", "200", "--seed", str(3301 + fuzz_matrix.KINDS.index(kind)),
                   "--old", oracles["old"]["path"], "--new", oracles["new"]["path"],
                   "--evidence", str(area / kind), "--cache-root", str(cache / kind)]
        if kind in ("text", "number"):
            command += ["--harness", str(fuzz_matrix.TEXT_HARNESS if kind == "text" else fuzz_matrix.NUMBER_HARNESS)]
        with (area / f"{kind}.txt").open("x") as log:
            log.write(f"source_commit={commit}\n$ {shlex.join(command)}\n")
            log.flush()
            status = subprocess.run(command, cwd=root, stdout=log, stderr=subprocess.STDOUT).returncode
            log.write(f"\nexit={status}\n")
        summary = json.loads((area / kind / "summary.json").read_text())
        passed = (status == 0 and summary.get("qualified") is True and summary.get("accepted") == 200
                  and summary.get("cases_requested") == 200 and summary.get("oracles") == oracles)
        print(f"{kind}: {'PASS' if passed else 'STOP'}; {summary.get('elapsed_seconds', '?')}s", flush=True)
        return kind, passed, summary

    with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as pool:
        reran = {kind: (passed, summary) for kind, passed, summary in pool.map(run, rerun)}
    source_unchanged = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip() == commit
    oracles_unchanged = all(fuzz_matrix.identity(Path(item["path"])) == item for item in oracles.values())
    kinds = {}
    for kind in fuzz_matrix.KINDS:
        passed, summary = reran.get(kind, original[kind])
        kinds[kind] = {"passed": passed, "source": "rerun" if kind in reran else "original",
                       "accepted": summary.get("accepted"), "native_comparisons": summary.get("native_comparisons"),
                       "evidence": str((area if kind in reran else matrix) / kind)}
    report = {"source_commit": commit, "oracles": oracles, "original_matrix": str(matrix), "rerun": rerun,
              "rerun_reason": "old-oracle compile_timeout (60 s) only, under machine load",
              "source_unchanged": source_unchanged, "oracles_unchanged": oracles_unchanged,
              "accepted_total": sum(k["accepted"] or 0 for k in kinds.values()),
              "native_comparisons_total": sum(k["native_comparisons"] or 0 for k in kinds.values()),
              "qualified": source_unchanged and oracles_unchanged and all(k["passed"] for k in kinds.values()),
              "kinds": kinds}
    (area / "combined.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({k: v for k, v in report.items() if k != "kinds"}, indent=1))
    if not report["qualified"]:
        raise SystemExit("STOP: combined matrix not qualified")


if __name__ == "__main__":
    main()
