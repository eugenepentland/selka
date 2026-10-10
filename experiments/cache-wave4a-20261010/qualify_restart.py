#!/usr/bin/env python3
"""Kill an owned indexed campaign after publication and check its resumed oracle.

Developer-only qualification. Run through build-slot.sh build; elapsed times
are operational observations, not isolated performance measurements.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import resource
import signal
import struct
import subprocess
import tempfile
import time


MAGIC = b"core-property-prefix-v1\n"
SOURCE = "public func test_generated(n: int) -> bool:\n    return n == n\n"


def read_prefix(path):
    data = path.read_bytes()
    assert data.startswith(MAGIC)
    payload = data[len(MAGIC) + 32:]
    assert payload[:32].hex() == path.stem
    ordinal, passed, discarded, clauses = struct.unpack_from("<QQQI", payload, 32)
    assert ordinal == passed + discarded
    assert discarded == clauses == 0  # This fixture has no preconditions.
    assert len(payload) == 60
    return {"next_ordinal": ordinal, "passed": passed,
            "checksum": data[len(MAGIC):len(MAGIC) + 32].hex()}


def completed(command, environment):
    result = subprocess.run(command, env=environment, text=True,
                            capture_output=True, timeout=180)
    assert result.returncode == 0, result.stderr
    report = json.loads(result.stdout)
    assert report["failed"] == 0, report
    return report["tests"][0]


def source_change(command, environment, source, prefix_path):
    extended = command.copy()
    extended[extended.index("--property-runs") + 1] = "1000000"
    process = subprocess.Popen(extended, env=environment, stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE, text=True, start_new_session=True)
    try:
        deadline = time.monotonic() + 120
        while time.monotonic() < deadline:
            if read_prefix(prefix_path)["passed"] > 4096:
                os.killpg(process.pid, signal.SIGSTOP)
                break
            if process.poll() is not None:
                raise AssertionError(("campaign exited before source edit", process.communicate()))
            time.sleep(0.005)
        else:
            raise AssertionError("no extended prefix before deadline")
        source.write_text(SOURCE.replace("n == n", "n == 0"))
        os.killpg(process.pid, signal.SIGCONT)
        stdout, stderr = process.communicate(timeout=30)
        assert process.returncode != 0, (stdout, stderr)
        assert "SourceChanged" in stderr, (stdout, stderr)
        assert not stdout.strip(), "changed-source campaign emitted a completed report"
        return {"exit": process.returncode, "stdout_bytes": len(stdout),
                "stderr": stderr, "last_prefix": read_prefix(prefix_path)}
    finally:
        if process.poll() is None:
            os.killpg(process.pid, signal.SIGKILL)
            process.communicate(timeout=30)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler", type=Path, required=True)
    parser.add_argument("--scratch", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    compiler = args.compiler.resolve()
    with compiler.open("rb") as binary:
        compiler_digest = hashlib.file_digest(binary, "sha256").hexdigest()
    args.scratch.mkdir(parents=True, exist_ok=True)
    environment = os.environ.copy()
    environment["MYL_CORE_LEAKCHECK"] = "0"
    environment["MYLANG_CACHE_PLAN_MODE"] = "shadow"
    started = time.monotonic()
    with tempfile.TemporaryDirectory(prefix="restart-", dir=args.scratch.resolve()) as temporary:
        root = Path(temporary)
        source = root / "app.my"
        source.write_text(SOURCE)
        cache = root / "cache"
        command = [str(compiler), "test", str(source), "--json", "--seed", "42",
                   "--property-policy", "indexed-v1", "--property-runs", "4096",
                   "--cache-dir", str(cache)]
        process = subprocess.Popen(command, env=environment, stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE, text=True, start_new_session=True)
        observed = None
        try:
            deadline = time.monotonic() + 120
            while time.monotonic() < deadline:
                paths = list((cache / "tests/property-prefix-v1").glob("*.bin"))
                if paths:
                    observed = paths[0]
                    os.killpg(process.pid, signal.SIGSTOP)
                    break
                if process.poll() is not None:
                    raise AssertionError(("campaign exited before interruption", process.communicate()))
                time.sleep(0.005)
            assert observed is not None, "no committed prefix before deadline"
            os.killpg(process.pid, signal.SIGKILL)
            stdout, stderr = process.communicate(timeout=30)
            assert process.returncode == -signal.SIGKILL, process.returncode
            assert not stdout.strip(), "unfinished campaign emitted a completed report"
            prefix = read_prefix(observed)
            assert 0 < prefix["passed"] < 4096, prefix
        finally:
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGKILL)
                process.communicate(timeout=30)
        resumed = completed(command, environment)
        evidence = resumed["property"]
        assert evidence["campaign"]["reused"] == prefix["next_ordinal"], evidence
        assert evidence["campaign"]["fresh_classified"] == 4096 - prefix["passed"], evidence
        assert evidence["counts"]["passed"] == 4096, evidence
        warm = completed(command, environment)
        assert warm["property"]["campaign"]["reused"] == 4096, warm
        assert warm["property"]["campaign"]["fresh_classified"] == 0, warm
        assert warm["property"]["counts"]["processes"] == 0, warm
        forced = completed(command + ["--force"], environment)
        assert forced["property"]["campaign"]["reused"] == 0, forced
        assert forced["property"]["campaign"]["fresh_classified"] == 4096, forced
        assert resumed["status"] == forced["status"] == "passed"
        assert resumed["reason"] == forced["reason"]
        for name in ("passed", "discarded"):
            assert evidence["counts"][name] == forced["property"]["counts"][name]
        changed = source_change(command, environment, source, observed)
        result = {
            "qualification": "owned-process-group SIGKILL, resume, warm, forced oracle",
            "compiler_sha256": compiler_digest,
            "fixture_sha256": hashlib.sha256(SOURCE.encode()).hexdigest(),
            "budget": 4096,
            "prefix_after_kill": prefix,
            "interrupted_exit": process.returncode,
            "interrupted_report_bytes": len(stdout),
            "interrupted_stderr": stderr,
            "resumed": evidence,
            "warm": warm["property"],
            "forced": forced["property"],
            "source_changed_during_execution": changed,
            "elapsed_seconds_unisolated": time.monotonic() - started,
            "children_max_rss_kib": resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss,
            "checksum_validation": "compiler load validates BLAKE3; harness checks framing and exact restored ordinal",
        }
        args.output.write_text(json.dumps(result, indent=2) + "\n")
        print(json.dumps({"passed": True, "restored": prefix["passed"], "budget": 4096}))


if __name__ == "__main__":
    main()
