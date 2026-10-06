#!/usr/bin/env python3
"""Strict deterministic S3-C provider, grant and handle fixtures.

Launch through build-slot.sh build. Every invocation owns a new evidence directory.
"""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[4]
BASE = Path(__file__).resolve().parent


def execute(argv, log, env=None, cwd=ROOT):
    completed = subprocess.run(list(map(str, argv)), capture_output=True, cwd=cwd, env=env, timeout=600)
    record = dict(command=list(map(str, argv)), status=completed.returncode,
                  stdout=completed.stdout.decode(), stderr=completed.stderr.decode())
    log.write_text(json.dumps(record, indent=2) + "\n")
    return record


def grade(record):
    codes = re.findall(r"error\[([^]]+)\]", record["stderr"])
    return record["status"], record["stdout"], codes[-1:] if codes else record["stderr"]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run-id", required=True)
    args = parser.parse_args()
    evidence = BASE / args.run_id
    evidence.mkdir()
    cache = ROOT / ".mylang-cache/s3" / args.run_id
    cache.mkdir(exist_ok=True)
    core = ROOT / "zig-out/bin/mylang-core"
    old = ROOT / ".mylang-cache/s3/d2-oracle/mylang"
    binaries = {}
    for fixture in ("host", "raw", "trap_handles", "grants"):
        provider = None if fixture == "grants" else BASE / ("c_host_provider.c" if fixture == "host" else "c_raw_provider.c")
        for mode in ("old", "debug", "release"):
            key = f"{fixture}-{mode}"
            binary = cache / key
            source = ROOT / f"test/core/c_{fixture}.my"
            if mode == "old":
                command = [old, "build", source, "-o", binary,
                           "--qbe", ROOT / ".mylang-cache/s3/d2-oracle/qbe",
                           "--cache-dir=" + str(cache / "old-cache")]
                if provider:
                    command += ["--provider", provider]
            else:
                command = [core, "build", source, "-o", binary, "--cache-dir", cache / "core-cache"]
                if provider:
                    command += ["--link", provider]
                if mode == "release":
                    command += ["--release", "--verify-facts"]
            result = execute(command, evidence / (key + "-build.json"))
            assert result["status"] == 0, result
            binaries[fixture, mode] = binary
    checks = []
    for fixture in ("host", "raw"):
        for mode in ("old", "debug", "release"):
            result = execute([binaries[fixture, mode]], evidence / f"{fixture}-{mode}-run.json",
                             env=dict(os.environ, MYL_CORE_LEAKCHECK="1"))
            assert grade(result) == (0, "", ""), result
            checks.append(f"{fixture}-{mode}: status0 and empty stdout/stderr")
    for scenario in ("trap", "oversize", "eof", "status", "error-fields"):
        records = []
        for mode in ("old", "debug", "release"):
            with tempfile.TemporaryDirectory(prefix="mylang-s3-c-owner-") as directory:
                trace = Path(directory) / "release.txt"
                environment = dict(os.environ, MYL_CORE_LEAKCHECK="1", MYL_FIXTURE_TRACE=str(trace))
                fixture = "trap_handles" if scenario == "trap" else "raw"
                if scenario != "trap":
                    environment["MYL_FIXTURE_BAD_READ"] = scenario
                result = execute([binaries[fixture, mode]], evidence / f"owner-{scenario}-{mode}.json", env=environment)
                assert trace.read_text() == "release=1 live=0\n", result
                assert "leak:" not in result["stderr"] and "R_CORE_FACT" not in result["stderr"], result
                records.append(grade(result))
        assert records[0] == records[1] == records[2], records
        expected = (2, "", "") if scenario == "error-fields" else (1, "", ["R_ASSERT" if scenario == "trap" else "InvalidProvider"])
        assert records[0] == expected, records
        checks.append(f"{scenario}: identical verdict; resource released once, zero live")
    for scenario in ("read", "write", "default", "missing-fs", "missing-env", "missing-entropy", "missing-clock", "duplicate", "unknown", "quote", "missing-root"):
        records = []
        for mode in ("old", "debug", "release"):
            with tempfile.TemporaryDirectory(prefix="mylang-s3-c-grants-") as directory:
                parent = Path(directory)
                root = parent / "root dir"
                root.mkdir()
                (root / "input.txt").write_text("inside")
                (parent / "outside.txt").write_text("outside")
                common = '--allow-env=KEEP --allow-random=7 --allow-clock'
                grant = f'--allow-read="{root}"'
                options = {
                    "read": f"--restrict {grant} {common}",
                    "write": f'--restrict --allow-write="{root}" {common}',
                    "default": '--allow-read=absent --allow-env=IGNORED --allow-random=7',
                    "missing-fs": "--restrict",
                    "missing-env": f"--restrict {grant}",
                    "missing-entropy": f"--restrict {grant} --allow-env=KEEP",
                    "missing-clock": f"--restrict {grant} --allow-env=KEEP --allow-random=7",
                    "duplicate": "--restrict --restrict",
                    "unknown": "--unknown-option",
                    "quote": '"--restrict',
                    "missing-root": "--restrict --allow-read=absent",
                }[scenario]
                result = execute([binaries["grants", mode]], evidence / f"grant-{scenario}-{mode}.json",
                                 env=dict(os.environ, MYL_CORE_LEAKCHECK="1", MYLANG_OPTIONS=options, KEEP="visible"), cwd=root)
                assert "leak:" not in result["stderr"] and "R_CORE_FACT" not in result["stderr"], result
                if scenario == "read":
                    assert not (root / "output.txt").exists(), result
                if scenario in ("write", "default"):
                    assert (root / "output.txt").read_text() == "saved", result
                records.append(grade(result))
        assert records[0] == records[1] == records[2], records
        assert records[0][0] == (0 if scenario in ("read", "write", "default") else 2), records
        checks.append(f"{scenario}: identical status, stdout and stderr; grants and private files checked")
    (evidence / "summary.json").write_text(json.dumps(dict(source=subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(), checks=checks), indent=2) + "\n")
    print(f"{len(checks)} strict fixture checks passed", flush=True)


if __name__ == "__main__":
    main()
