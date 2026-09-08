"""Contract runner regression checks; no agent evaluations."""
import argparse
import json
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts/test_contract.py"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--runner", type=Path, help="also test real mylang-io byte boundary")
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="contract-runner-test-") as temporary:
        root = Path(temporary)
        fixtures = root / "cases.json"
        report = root / "report.json"
        (root / "input").write_bytes(b'{"x": 1}\n')
        (root / "expected").write_bytes(b'{"x":1}')
        base = {"id": "echo", "input": "input", "expected": "expected"}

        def check(code="import sys;sys.stdout.buffer.write(sys.stdin.buffer.read())", cases=None, flags=(), status=0, argv=None):
            report.unlink(missing_ok=True)
            fixtures.write_text(json.dumps({"version": 1, "cases": [base] if cases is None else cases}))
            result = subprocess.run([sys.executable, str(SCRIPT), "--fixtures", str(fixtures),
                                     "--report", str(report), *flags, "--",
                                     *(argv or [sys.executable, "-c", code])], capture_output=True, timeout=15)
            assert result.returncode == status, (result.returncode, result.stdout, result.stderr)
            data = json.loads(report.read_text())
            assert len(result.stdout.splitlines()) == 1, result.stdout
            if status == 0:
                assert data["selected"] == data["executed"] == data["passed"] > 0, data
            return data

        check()
        existing = report.read_bytes()
        refused = subprocess.run([sys.executable, str(SCRIPT), "--fixtures", str(fixtures),
                                  "--report", str(report), "--", sys.executable, "-c",
                                  f"from pathlib import Path;Path({str(root / 'must-not-run')!r}).touch()"],
                                 capture_output=True, timeout=10)
        assert refused.returncode == 2 and report.read_bytes() == existing
        assert not (root / "must-not-run").exists()
        check(cases=[], status=2)
        check(cases=[base, base], status=2)
        check(flags=["--case", "missing"], status=2)
        check(cases=[dict(base, expected="absent")], status=2)
        check(cases=[dict(base, surprise=True)], status=2)
        check(code="raise SystemExit(4)", status=1)
        check(argv=[str(root / "missing")], status=2)
        for actual, expected in [(b"1.00000000000000001", b"1.00000000000000002"), (b"1e999", b"2e999"), (b"[]", b"[1]"), (b"[1]", b"[]"), (b"true", b"1"),
                                 (b'{"a":1,"a":2}', b'{"a":2}'), (b"NaN", b"null"), (b"1e99999999999999999999999999", b"null"),
                                 (b"[" * 1100 + b"0" + b"]" * 1100, b"null"),
                                 (b"1\n2", b"1"), (b"\xff", b"null"), (b"", b"null")]:
            (root / "input").write_bytes(actual)
            (root / "expected").write_bytes(expected)
            check(status=1)
        for invalid in (b"NaN", b"1e99999999999999999999999999", b"[" * 1100 + b"0" + b"]" * 1100):
            (root / "expected").write_bytes(invalid)
            check(status=2)
        # Arbitrary raw bytes and nonzero exits remain explicitly testable.
        raw = b"\x00\xff\xc0\x80{broken}"
        (root / "input").write_bytes(raw)
        (root / "expected").write_bytes(raw)
        byte_case = dict(base, compare="bytes")
        check(cases=[byte_case])
        check(code="import sys;sys.stdout.buffer.write(sys.stdin.buffer.read());sys.exit(3)",
              cases=[dict(byte_case, expect_exit=3)])
        (root / "stderr").write_bytes(b"diagnostic")
        check(code="import sys;sys.stdout.buffer.write(sys.stdin.buffer.read());sys.stderr.write('diagnostic')",
              cases=[dict(byte_case, expected_stderr="stderr")])
        check(cases=[dict(byte_case, expected_stderr="stderr")], status=1)
        timed = check(code="import time;time.sleep(10)", cases=[byte_case],
                      flags=["--timeout", "0.1"], status=1)
        assert timed["cases"][0]["timed_out"]
        for stream in ("stdout", "stderr"):
            bounded = check(code=f"import sys;sys.{stream}.buffer.write(b'x'*10000000)",
                            cases=[byte_case], flags=["--max-output-bytes", "128"], status=1)
            row = bounded["cases"][0]
            assert row["output_limit_exceeded"] and row["actual"]["bytes"] <= 128 and row["stderr"]["bytes"] <= 128
        # Output before input consumption would deadlock a synchronous pipe writer.
        (root / "input").write_bytes(b"x" * 200000)
        (root / "expected").write_bytes(b"y" * 200000 + b"x" * 200000)
        check(code="import sys;sys.stdout.buffer.write(b'y'*200000);sys.stdout.flush();sys.stdout.buffer.write(sys.stdin.buffer.read())", cases=[byte_case])
        # A surviving child must not hold pipes open until the timeout.
        (root / "expected").write_bytes(b"")
        descendant = check(code="import os,time;pid=os.fork();time.sleep(10) if pid==0 else None", cases=[byte_case], flags=["--timeout", "2"])
        assert descendant["cases"][0]["elapsed_seconds"] < 2
        if args.runner:
            project = root / "project"
            project.mkdir()
            (project / "io.my").write_text("module io;export length;export byte;export put;host fn length()->i64 effects(host);host fn byte(index:i64)->u8 effects(host);host fn put(value:u8)->i64 effects(host);")
            (project / "main.my").write_text("module main;import io;fn main()->i64{let mut i=0;while i<io::length(){discard io::put(io::byte(i));i+=1;}return 0;}")
            argv = [str(args.runner.resolve()), "--project", str(project)]
            (root / "input").write_bytes(raw)
            (root / "expected").write_bytes(raw)
            check(cases=[byte_case], argv=argv)
            (root / "input").write_bytes(b'{"x":1}\n')
            (root / "expected").write_bytes(b'{"x": 1}')
            check(argv=argv)
    print("contract runner: all regression checks passed")


if __name__ == "__main__":
    main()
