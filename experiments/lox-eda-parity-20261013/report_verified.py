#!/usr/bin/env python3
"""Run the frozen report checks with distinct artifact hashes checked twice.

Use --output NEW_DIRECTORY [--compare EXISTING_REPORT] -- report PIPELINE_ARGS.
The original pipeline and attempt remain unchanged. Every receipt's expected
identity is checked for agreement, each distinct artifact is hashed on first use
and again after reporting, and output is published only after both checks pass.
"""
import argparse
import datetime
import hashlib
import json
from pathlib import Path
import runpy
import sys
import time


def sha(path):
    with Path(path).open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--compare", type=Path)
    args, forwarded = parser.parse_known_args()
    if forwarded and forwarded[0] == "--":
        forwarded.pop(0)
    assert forwarded and forwarded[0] == "report", "Only report validation is supported"
    assert "--case" not in forwarded, "Validate the complete 60-case denominator"
    args.output.mkdir(parents=True, exist_ok=False)
    started = datetime.datetime.now(datetime.timezone.utc).isoformat()
    timer = time.monotonic()
    wrapper_digest = sha(__file__)
    pipeline = Path(__file__).resolve().with_name("pipeline.py")
    namespace = runpy.run_path(str(pipeline))
    context = namespace["main"].__globals__
    identities = {str(pipeline): sha(pipeline)}
    requests = 0
    captured = {}

    def assert_pins(pins):
        nonlocal requests
        for path, digest in pins.items():
            requests += 1
            if path in identities:
                assert identities[path] == digest, ("inconsistent receipt identity", path)
            else:
                assert sha(path) == digest, ("identity changed", path)
                identities[path] = digest

    def capture(path, value):
        assert path.name == "parity-report.json" and not captured
        assert value["scope"] == 60 and len(value["cells"]) == 60
        captured["original_output"] = str(path)
        captured["bytes"] = (json.dumps(value, indent=2) + "\n").encode()

    context["assert_pins"] = assert_pins
    context["save"] = capture
    sys.argv = [str(pipeline), *forwarded]
    namespace["main"]()
    assert captured, "Report did not complete"
    for path, digest in identities.items():
        assert sha(path) == digest, ("identity changed during report", path)
    output = captured["bytes"]
    if args.compare:
        assert output == args.compare.read_bytes(), "Frozen and optimized reports differ"
    assert sha(__file__) == wrapper_digest, "Report wrapper changed during validation"
    receipt = {
        "started_utc": started,
        "finished_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "validation_elapsed_seconds": time.monotonic() - timer,
        "method": "All expected identities checked for agreement; distinct artifacts SHA-256 checked on first use and again before output publication. Original report assertions unchanged.",
        "pipeline": str(pipeline), "pipeline_sha256": identities[str(pipeline)],
        "wrapper_sha256": wrapper_digest, "arguments": forwarded,
        "expected_identity_checks": requests, "distinct_hashed_artifacts": len(identities),
        "original_output": captured["original_output"],
        "report_sha256": hashlib.sha256(output).hexdigest(),
        "byte_identical_reference": str(args.compare.resolve()) if args.compare else None,
        "identities": identities,
    }
    # The receipt is the completion marker; a report without it is incomplete.
    receipt_bytes = (json.dumps(receipt, indent=2) + "\n").encode()
    (args.output / "parity-report.json").write_bytes(output)
    (args.output / "validation.json").write_bytes(receipt_bytes)
    print(json.dumps({key: value for key, value in receipt.items() if key != "identities"}))


if __name__ == "__main__":
    main()
