#!/usr/bin/env python3
"""Native persistent-value and CSV recovery qualification; not a timing benchmark.

The caller owns admission (scripts/build-slot.sh build, or the full build gate).
No inherited descriptor is required and this driver never acquires another slot.
Product sources remain untouched;
application variants, executables and stores live in the supplied ignored output.
The optional preload shim injects faults at real native storage syscalls.
"""
import argparse
import csv
import hashlib
import io
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import tempfile
import time


ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "test/fixtures/application-cache/application.my"
SHIM = ROOT / "test/fixtures/application-cache/faults.c"
INPUT = b"".join(f"{index},{index * 10}\n".encode() for index in range(1, 13))
MAX_RECORD = 16 << 20


def digest(data):
    return hashlib.sha256(data).hexdigest()


def file_digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def csv_oracle(data, multiplier=3, total_multiplier=1):
    """Independent Python parsing and aggregation, compared byte for byte."""
    output = io.StringIO(newline="")
    writer = csv.writer(output, lineterminator="\n")
    writer.writerow(["id", "input", "mapped", "running_total"])
    total = 0
    for identifier, value in csv.reader(io.StringIO(data.decode("ascii"))):
        mapped = int(value) * multiplier + 1
        total += mapped * total_multiplier
        writer.writerow([int(identifier), value, mapped, total])
    return output.getvalue().encode("ascii"), str(total).encode("ascii")


def decode_record(data):
    """Read the real native record format independently, with bounded input."""
    assert len(data) <= MAX_RECORD
    prefix, checksum, payload = data.split(b"\n", 2)
    assert prefix == b"SELKA-RECORD-1" and checksum.decode("ascii") == digest(payload)
    fields = json.loads(payload)
    assert isinstance(fields, list) and all(isinstance(field, str) for field in fields)
    assert json.dumps(fields, ensure_ascii=False, separators=(",", ":")).encode() == payload
    return fields


def encode_record(fields):
    payload = json.dumps(fields, ensure_ascii=False, separators=(",", ":")).encode()
    return b"SELKA-RECORD-1\n" + digest(payload).encode() + b"\n" + payload


def committed(store):
    journal = store / "run.json"
    if not journal.exists():
        return 0
    fields = decode_record(journal.read_bytes())
    assert len(fields) >= 4 and fields[0] == "durable-journal-v1"
    prior_state = b"0"
    for ordinal, expected in enumerate(fields[4:]):
        data = (store / f"chunk-{ordinal}.entry").read_bytes()
        assert digest(data) == expected
        artifact = decode_record(data)
        assert len(artifact) == 7 and artifact[:3] == ["durable-step-v1", fields[1], str(ordinal)]
        assert artifact[4] == digest(prior_state)
        bytes.fromhex(artifact[5])
        prior_state = bytes.fromhex(artifact[6])
    return len(fields) - 4


class Harness:
    def __init__(self, compiler, zig, output):
        self.compiler = compiler.resolve()
        self.zig = zig.resolve()
        self.output = output.resolve()
        self.output.mkdir(parents=True, exist_ok=False)
        self.work = self.output / "work"
        self.work.mkdir()
        self.source = self.work / "application.my"
        self.original = FIXTURE.read_text()
        self.source.write_text(self.original)
        self.env = os.environ.copy()
        for name in list(self.env):
            if name.startswith(("W7_FAULT_", "WAVE7_")) or name == "LD_PRELOAD":
                self.env.pop(name)
        self.env.update(MYLANG_ZIG=str(self.zig), ZIG=str(self.zig),
                        PYTHONDONTWRITEBYTECODE="1", PYTHONPYCACHEPREFIX="/dev/null")
        self.calls = []
        self.cases = []
        self.builds = []
        self.variants = {}
        self.active = set()
        self.shim = self.work / "faults.so"
        self.baseline = self.build("baseline", self.original)
        self.compile_shim()

    def build(self, name, source):
        stamp = self.source.stat()
        self.source.write_text(source)
        os.utime(self.source, ns=(stamp.st_atime_ns, stamp.st_mtime_ns))
        binary = self.work / name
        command = [str(self.compiler), "build", str(self.source), "-o", str(binary), "--release"]
        result = subprocess.run(command, cwd=ROOT, env=self.env, capture_output=True, timeout=180)
        (self.output / f"build-{name}.stdout").write_bytes(result.stdout)
        (self.output / f"build-{name}.stderr").write_bytes(result.stderr)
        self.builds.append({"name": name, "command": command, "exit": result.returncode,
                            "source_sha256": digest(source.encode())})
        assert result.returncode == 0, f"build {name}: {result.stderr.decode(errors='replace')}"
        self.builds[-1]["binary_sha256"] = file_digest(binary)
        return binary

    def compile_shim(self):
        command = [str(self.zig), "cc", "-O2", "-shared", "-fPIC", str(SHIM), "-o", str(self.shim)]
        result = subprocess.run(command, cwd=ROOT, env=self.env, capture_output=True, timeout=90)
        (self.output / "shim-build.stdout").write_bytes(result.stdout)
        (self.output / "shim-build.stderr").write_bytes(result.stderr)
        assert result.returncode == 0, result.stderr.decode(errors="replace")

    def directory(self, name, data=INPUT):
        directory = self.output / "cases" / name
        directory.mkdir(parents=True)
        (directory / "input.csv").write_bytes(data)
        (directory / "persistent").mkdir()
        (directory / "durable").mkdir()
        return directory

    def environment(self, mode, extra=None):
        env = self.env | {"WAVE7_MODE": mode}
        if extra:
            env.update(extra)
        return env

    def result(self, name, directory, binary, result, mode, extra=None):
        prefix = self.output / f"call-{len(self.calls):03d}-{name}"
        prefix.with_suffix(".stdout").write_bytes(result.stdout)
        prefix.with_suffix(".stderr").write_bytes(result.stderr)
        report = json.loads(result.stdout) if result.stdout.strip() else None
        item = {"name": name, "directory": str(directory), "binary": str(binary),
                "exit": result.returncode, "report": report, "mode": mode,
                "settings": extra or {}, "stdout_sha256": digest(result.stdout),
                "stderr_sha256": digest(result.stderr)}
        self.calls.append(item)
        return report

    def run(self, name, directory, binary=None, mode="durable", extra=None, success=True):
        binary = binary or self.baseline
        process = subprocess.Popen([str(binary)], cwd=directory, env=self.environment(mode, extra),
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True)
        self.active.add(process)
        try:
            stdout, stderr = process.communicate(timeout=30)
            result = subprocess.CompletedProcess([str(binary)], process.returncode, stdout, stderr)
        finally:
            self.stop(process)
            self.active.discard(process)
        report = self.result(name, directory, binary, result, mode, extra)
        assert report is not None, f"{name}: no application report"
        assert bool(report["ok"]) == success and (result.returncode == 0) == success, (name, result, report)
        return report

    def persistent_check(self, name, directory, expected, reused, binary=None, extra=None):
        report = self.run(name, directory, binary, "persistent", extra)
        assert bytes.fromhex(report["value_hex"]) == expected, (name, report)
        assert report["reused"] is reused, (name, report)
        assert len(report["function_digest"]) == 64
        return report

    def durable_check(self, name, directory, fresh, reused, binary=None, multiplier=3, total_multiplier=1, extra=None):
        report = self.run(name, directory, binary, extra=extra)
        expected, state = csv_oracle((directory / "input.csv").read_bytes(), multiplier, total_multiplier)
        output = (directory / "durable/final.csv").read_bytes()
        assert output == expected and bytes.fromhex(report["state_hex"]) == state, (name, report)
        assert report["output_digest"] == digest(output), (name, report)
        assert (report["fresh"], report["reused"]) == (fresh, reused), (name, report)
        assert committed(directory / "durable") == fresh + reused
        return report

    def fault_env(self, marker, operation, target, occurrence=1):
        return {"LD_PRELOAD": str(self.shim), "W7_FAULT_MARKER": str(marker),
                "W7_FAULT_OPERATION": operation, "W7_FAULT_TARGET": target,
                "W7_FAULT_OCCURRENCE": str(occurrence)}

    def stopped(self, name, directory, operation, target, occurrence=1):
        marker = self.output / f"{name}.marker"
        extra = self.fault_env(marker, operation, target, occurrence)
        process = subprocess.Popen([str(self.baseline)], cwd=directory,
                                   env=self.environment("durable", extra), stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE, start_new_session=True)
        self.active.add(process)
        try:
            deadline = time.monotonic() + 30
            while not marker.exists():
                assert process.poll() is None, f"{name}: application exited before fault checkpoint"
                assert time.monotonic() < deadline, f"{name}: fault checkpoint timed out"
                time.sleep(0.02)
            fields = marker.read_text().strip().split("\t")
            assert int(fields[0]) == process.pid and fields[1] == operation
            return process, extra
        except BaseException:
            self.stop(process)
            self.active.discard(process)
            raise

    @staticmethod
    def stop(process):
        if process.poll() is None:
            os.killpg(process.pid, signal.SIGKILL)
        return process.communicate(timeout=10)

    def crash(self, name, operation, target, occurrence=1):
        directory = self.directory(name)
        process, extra = self.stopped(name, directory, operation, target, occurrence)
        try:
            prefix = committed(directory / "durable")
            stdout, stderr = self.stop(process)
            assert process.returncode == -signal.SIGKILL
            result = subprocess.CompletedProcess([str(self.baseline)], process.returncode, stdout, stderr)
            self.result(name + "-killed", directory, self.baseline, result, "durable", extra)
            self.durable_check(name + "-recover", directory, 6 - prefix, prefix)
            self.durable_check(name + "-duplicate", directory, 0, 6)
            self.cases.append({"name": name, "kind": "crash", "operation": operation,
                               "target": target, "committed_at_crash": prefix})
        finally:
            self.stop(process)
            self.active.discard(process)

    def variant_sources(self):
        return {
            "body": (self.original.replace("return str(row.amount).encode()", "return str(row.amount + 9).encode()"), b"38"),
            "private-helper": (self.original.replace("return shared(value) + 7", "return shared(value) + 11"), b"33"),
            "shared-helper": (self.original.replace("return value * 3 + 1", "return value * 5 + 1"), b"43"),
            "schema": (self.original.replace("    amount: int\n", "    amount: int\n    revision: int\n")
                       .replace("amount=private_map(value))", "amount=private_map(value), revision=0)")
                       .replace("amount=shared(decimal(fields[1])))", "amount=shared(decimal(fields[1])), revision=0)"), b"29"),
            "pipeline-body": (self.original.replace("total += row.amount", "total += row.amount * 2"), b"29"),
        }

    def variant(self, name):
        if name not in self.variants:
            source, _expected = self.variant_sources()[name]
            assert source != self.original, f"variant {name} must actually edit the fixture"
            self.variants[name] = self.build(name, source)
        return self.variants[name]

    def persistent(self):
        scalar = {"WAVE7_KEY": "number"}
        directory = self.directory("persistent-cold-warm", b"7")
        base = self.persistent_check("persistent-cold", directory, b"29", False, extra=scalar)
        self.persistent_check("persistent-warm", directory, b"29", True, extra=scalar)
        self.persistent_check("persistent-force", directory, b"29", False,
                              extra=scalar | {"WAVE7_ENTRIES": "0"})
        for name in ("body", "private-helper", "shared-helper", "schema"):
            binary = self.variant(name)
            _source, expected = self.variant_sources()[name]
            case = self.directory("persistent-" + name, b"7")
            original = self.persistent_check(name + "-original", case, b"29", False, extra=scalar)
            changed = self.persistent_check(name + "-edit", case, expected, False, binary, scalar)
            assert changed["function_digest"] != original["function_digest"]
            self.persistent_check(name + "-edit-warm", case, expected, True, binary, scalar)
            restored = self.persistent_check(name + "-revert", case, b"29", True, extra=scalar)
            assert restored["function_digest"] == original["function_digest"]
        alternate = scalar | {"WAVE7_ALTERNATE": "1"}
        changed = self.persistent_check("callback-change", directory, b"29:alternate", False, extra=alternate)
        assert changed["function_digest"] != base["function_digest"]
        self.persistent_check("callback-warm", directory, b"29:alternate", True, extra=alternate)
        self.persistent_check("callback-revert", directory, b"29", True, extra=scalar)
        data = self.directory("persistent-input", b"7")
        self.persistent_check("input-original", data, b"29", False, extra=scalar)
        path = data / "input.csv"
        stamp = path.stat()
        path.write_bytes(b"8")
        os.utime(path, ns=(stamp.st_atime_ns, stamp.st_mtime_ns))
        self.persistent_check("input-restored-mtime-edit", data, b"32", False, extra=scalar)
        path.write_bytes(b"7")
        self.persistent_check("input-revert", data, b"29", True, extra=scalar)
        tags = self.directory("tagged-identity", b"7")
        for kind, value in (("number", b"29"), ("text", b"text:7"), ("data", b"bytes:7")):
            self.persistent_check("tag-" + kind + "-cold", tags, value, False,
                                  extra={"WAVE7_KEY": kind, "WAVE7_ENTRIES": "3"})
            self.persistent_check("tag-" + kind + "-warm", tags, value, True,
                                  extra={"WAVE7_KEY": kind, "WAVE7_ENTRIES": "3"})
        for kind, value in (("number", b"29"), ("text", b"text:7"), ("data", b"bytes:7")):
            self.persistent_check("tag-" + kind + "-retained", tags, value, True,
                                  extra={"WAVE7_KEY": kind, "WAVE7_ENTRIES": "3"})
        for label, data, kind, expected in (("empty", b"", "data", b"bytes:"),
                                             ("nul-bytes", b"\x00\xc3\xa9", "data", b"bytes:\x00\xc3\xa9"),
                                             ("nul-text", b"\x00\xc3\xa9", "text", b"text:\x00\xc3\xa9")):
            case = self.directory("persistent-" + label, data)
            self.persistent_check(label + "-cold", case, expected, False, extra={"WAVE7_KEY": kind})
            self.persistent_check(label + "-warm", case, expected, True, extra={"WAVE7_KEY": kind})
        corrupt = self.directory("persistent-corruption", b"7")
        self.persistent_check("corrupt-prime", corrupt, b"29", False, extra=scalar)
        payloads = list((corrupt / "persistent").glob("memo-*.entry"))
        assert len(payloads) == 1
        artifact = payloads[0]
        for action in ("corrupt", "truncate", "missing"):
            if action == "missing":
                artifact.unlink()
            else:
                raw = artifact.read_bytes()
                artifact.write_bytes(raw[:len(raw) // 2] if action == "truncate" else raw[:-1] + bytes([raw[-1] ^ 1]))
            self.persistent_check("payload-" + action, corrupt, b"29", False, extra=scalar)
            self.persistent_check("payload-" + action + "-repaired", corrupt, b"29", True, extra=scalar)
        bounded = self.directory("persistent-bound", b"1")
        for number in range(1, 9):
            (bounded / "input.csv").write_text(str(number))
            self.persistent_check("bounded-" + str(number), bounded, str(number * 3 + 8).encode(), False, extra=scalar)
            assert len(list((bounded / "persistent").glob("memo-*.entry"))) <= 2
        self.persistent_check("bounded-last-hit", bounded, b"32", True, extra=scalar)
        oversized = self.directory("persistent-oversized", b"7")
        tiny = scalar | {"WAVE7_BYTES": "1"}
        self.persistent_check("oversized-first", oversized, b"29", False, extra=tiny)
        self.persistent_check("oversized-repeat", oversized, b"29", False, extra=tiny)
        assert not list((oversized / "persistent").glob("memo-*.entry"))
        self.persistent_uncertain_publication()

    def persistent_uncertain_publication(self):
        case = self.directory("persistent-uncertain-publication", b"7")
        for label in ("publish", "warm"):
            marker = self.output / f"persistent-uncertain-{label}.marker"
            extra = {"WAVE7_KEY": "number"} | self.fault_env(
                marker, "directory-sync-error", "@directory")
            self.run("persistent-uncertain-" + label, case, mode="persistent", extra=extra, success=False)
            assert marker.exists(), "directory sync failure must actually execute"
            assert len(list((case / "persistent").glob("memo-*.entry"))) == 1
        self.persistent_check("persistent-uncertain-recovery", case, b"29", True,
                              extra={"WAVE7_KEY": "number"})

    def durable(self):
        oracle = self.directory("uninterrupted-oracle")
        self.durable_check("uninterrupted-forced-empty-store", oracle, 6, 0)
        self.durable_check("uninterrupted-warm", oracle, 0, 6)
        empty = self.directory("empty-pipeline", b"")
        self.durable_check("empty-pipeline-cold", empty, 1, 0)
        self.durable_check("empty-pipeline-warm", empty, 0, 1)
        phases = [("write-before", "chunk-0.entry", 1), ("write-after", "chunk-0.entry", 1),
                  ("rename-before", "chunk-0.entry", 1), ("rename-after", "chunk-0.entry", 1),
                  ("rename-before", "run.json", 2), ("rename-after", "run.json", 2),
                  ("rename-before", "final.csv", 1), ("rename-after", "final.csv", 1),
                  ("directory-sync-before", "run.json", 2), ("directory-sync-after", "run.json", 2),
                  ("directory-sync-before", "final.csv", 1), ("directory-sync-after", "final.csv", 1)]
        for operation, target, occurrence in phases:
            self.crash(operation + "-" + target.replace(".", "-"), operation, target, occurrence)
        for operation, target in [("write-error", "chunk-0.entry"), ("file-sync-error", "chunk-0.entry"),
                                  ("rename-error", "chunk-0.entry"), ("directory-sync-error", "final.csv")]:
            name = operation + "-failure"
            case = self.directory(name)
            marker = self.output / (name + ".marker")
            self.run(name, case, extra=self.fault_env(marker, operation, target), success=False)
            assert marker.exists()
            prefix = committed(case / "durable")
            if target == "final.csv":
                assert (case / "durable/final.csv").read_bytes() == csv_oracle(INPUT)[0]
            self.durable_check(name + "-recovery", case, 6 - prefix, prefix)
        self.published_journal_uncertain()
        self.recovery_adversaries()

    def published_journal_uncertain(self):
        case = self.directory("published-journal-uncertain")
        marker = self.output / "published-journal-uncertain.marker"
        self.run("published-journal-uncertain", case,
                 extra=self.fault_env(marker, "directory-sync-error", "run.json", 8), success=False)
        assert marker.exists() and committed(case / "durable") == 6
        journal = case / "durable/run.json"
        assert decode_record(journal.read_bytes())[2] == "published"
        assert (case / "durable/final.csv").read_bytes() == csv_oracle(INPUT)[0]
        before = {path.name: digest(path.read_bytes()) for path in (case / "durable").iterdir() if path.is_file()}
        marker = self.output / "published-journal-repeat-sync.marker"
        self.run("published-journal-repeat-sync", case,
                 extra=self.fault_env(marker, "directory-sync-error", "@directory"), success=False)
        assert marker.exists(), "published warm recovery must synchronize before success"
        assert before == {path.name: digest(path.read_bytes()) for path in (case / "durable").iterdir() if path.is_file()}
        self.durable_check("published-journal-sync-recovery", case, 0, 6)

    def smoke(self):
        scalar = {"WAVE7_KEY": "number"}
        case = self.directory("smoke-persistent", b"7")
        self.persistent_check("smoke-persistent-cold", case, b"29", False, extra=scalar)
        self.persistent_check("smoke-persistent-warm", case, b"29", True, extra=scalar)
        self.persistent_check("smoke-persistent-force", case, b"29", False,
                              extra=scalar | {"WAVE7_ENTRIES": "0"})
        artifacts = list((case / "persistent").glob("memo-*.entry"))
        assert len(artifacts) == 1
        artifacts[0].write_bytes(b"truncated")
        self.persistent_check("smoke-persistent-corrupt-miss", case, b"29", False, extra=scalar)
        self.persistent_check("smoke-persistent-repaired", case, b"29", True, extra=scalar)
        case = self.directory("smoke-durable")
        self.durable_check("smoke-durable-cold", case, 6, 0)
        self.durable_check("smoke-durable-warm", case, 0, 6)
        self.crash("smoke-after-committed-prefix", "rename-after", "run.json", 2)
        (case / "input.csv").write_bytes(INPUT.replace(b"1,10\n", b"1,11\n", 1))
        self.run("smoke-input-incompatible", case, success=False)
        (case / "input.csv").write_bytes(INPUT)
        self.durable_check("smoke-input-revert", case, 0, 6)

    def recovery_adversaries(self):
        case = self.directory("competing-recovery")
        process, extra = self.stopped("competing", case, "rename-after", "run.json", 2)
        try:
            assert committed(case / "durable") == 1
            before = {path.name: digest(path.read_bytes()) for path in (case / "durable").iterdir() if path.is_file()}
            self.run("competing-denied", case, success=False)
            after = {path.name: digest(path.read_bytes()) for path in (case / "durable").iterdir() if path.is_file()}
            assert before == after
            os.killpg(process.pid, signal.SIGCONT)
            stdout, stderr = process.communicate(timeout=30)
            result = subprocess.CompletedProcess([str(self.baseline)], process.returncode, stdout, stderr)
            report = self.result("competing-winner", case, self.baseline, result, "durable", extra)
            assert process.returncode == 0 and report["ok"]
            self.durable_check("competing-after-release", case, 0, 6)
        finally:
            self.stop(process)
            self.active.discard(process)
        for action in ("journal-corrupt", "journal-truncate", "artifact-corrupt", "artifact-missing", "coherent-index"):
            case = self.directory(action)
            self.durable_check(action + "-prime", case, 6, 0)
            target = case / "durable" / ("run.json" if action.startswith("journal") else "chunk-0.entry")
            if action.endswith("missing"):
                target.unlink()
            elif action == "coherent-index":
                fields = decode_record(target.read_bytes())
                fields[2] = "1"
                replacement = encode_record(fields)
                target.write_bytes(replacement)
                journal = case / "durable/run.json"
                fields = decode_record(journal.read_bytes())
                fields[4] = digest(replacement)
                journal.write_bytes(encode_record(fields))
            else:
                raw = target.read_bytes()
                target.write_bytes(raw[:len(raw) // 2] if action.endswith("truncate") else raw[:-1] + bytes([raw[-1] ^ 1]))
            snapshot = {path.name: digest(path.read_bytes()) for path in (case / "durable").iterdir() if path.is_file()}
            self.run(action + "-fail-closed", case, success=False)
            assert snapshot == {path.name: digest(path.read_bytes()) for path in (case / "durable").iterdir() if path.is_file()}
        case = self.directory("orphan-gc")
        self.durable_check("orphan-prime", case, 6, 0)
        store = case / "durable"
        (store / "chunk-99.entry").write_bytes(b"orphan")
        (store / ".myl-durable-orphan").write_bytes(b"partial")
        keep = {path.name: digest(path.read_bytes()) for path in store.iterdir()
                if path.name in {"run.json", "final.csv"} or path.name in {f"chunk-{i}.entry" for i in range(6)}}
        self.durable_check("orphan-cleaned", case, 0, 6)
        assert not (store / "chunk-99.entry").exists() and not (store / ".myl-durable-orphan").exists()
        assert all(digest((store / name).read_bytes()) == value for name, value in keep.items())
        case = self.directory("changed-input")
        self.durable_check("durable-input-prime", case, 6, 0)
        path = case / "input.csv"
        stamp = path.stat()
        path.write_bytes(INPUT.replace(b"1,10\n", b"1,11\n", 1))
        os.utime(path, ns=(stamp.st_atime_ns, stamp.st_mtime_ns))
        self.run("durable-input-incompatible", case, success=False)
        path.write_bytes(INPUT)
        self.durable_check("durable-input-revert", case, 0, 6)
        snapshot = {item.name: digest(item.read_bytes()) for item in (case / "durable").iterdir() if item.is_file()}
        path.unlink()
        self.run("durable-input-deleted", case, success=False)
        assert snapshot == {item.name: digest(item.read_bytes()) for item in (case / "durable").iterdir() if item.is_file()}
        path.write_bytes(INPUT)
        self.durable_check("durable-input-deletion-revert", case, 0, 6)
        self.captured_input_mutation()
        for name, multiplier, total_multiplier in (("shared-helper", 5, 1), ("schema", 3, 1), ("pipeline-body", 3, 2)):
            binary = self.variant(name)
            case = self.directory("durable-" + name)
            self.durable_check(name + "-journal-prime", case, 6, 0)
            self.run(name + "-journal-incompatible", case, binary, success=False)
            self.durable_check(name + "-journal-revert", case, 0, 6)
            fresh = self.directory("durable-" + name + "-forced")
            self.durable_check(name + "-fresh-oracle", fresh, 6, 0, binary, multiplier, total_multiplier)
        case = self.directory("durable-unrelated-private")
        original = self.durable_check("unrelated-private-prime", case, 6, 0)
        unchanged = self.durable_check("unrelated-private-edit", case, 0, 6, self.variant("private-helper"))
        assert unchanged["function_digest"] == original["function_digest"]
        self.durable_check("unrelated-private-revert", case, 0, 6)
        case = self.directory("durable-callback")
        self.durable_check("durable-callback-prime", case, 6, 0)
        alternate = {"WAVE7_ALTERNATE": "1"}
        self.run("durable-callback-incompatible", case, extra=alternate, success=False)
        self.durable_check("durable-callback-revert", case, 0, 6)
        fresh = self.directory("durable-callback-forced")
        changed = self.durable_check("durable-callback-fresh", fresh, 6, 0, extra=alternate)
        self.durable_check("durable-callback-warm", fresh, 0, 6, extra=alternate)
        assert changed["function_digest"] != original["function_digest"]

    def captured_input_mutation(self):
        case = self.directory("captured-input-mutation")
        process, extra = self.stopped("captured-input", case, "rename-after", "run.json", 2)
        try:
            assert committed(case / "durable") == 1
            path = case / "input.csv"
            stamp = path.stat()
            path.write_bytes(INPUT.replace(b"1,10\n", b"1,11\n", 1))
            os.utime(path, ns=(stamp.st_atime_ns, stamp.st_mtime_ns))
            os.killpg(process.pid, signal.SIGCONT)
            stdout, stderr = process.communicate(timeout=30)
            result = subprocess.CompletedProcess([str(self.baseline)], process.returncode, stdout, stderr)
            report = self.result("captured-input-original-completes", case, self.baseline, result, "durable", extra)
            assert process.returncode == 0 and report["ok"] and (report["fresh"], report["reused"]) == (6, 0)
            expected, state = csv_oracle(INPUT)
            assert (case / "durable/final.csv").read_bytes() == expected
            assert bytes.fromhex(report["state_hex"]) == state and report["output_digest"] == digest(expected)
            self.run("captured-input-next-run-incompatible", case, success=False)
            path.write_bytes(INPUT)
            self.durable_check("captured-input-revert", case, 0, 6)
        finally:
            self.stop(process)
            self.active.discard(process)

    def save(self, success, error=None):
        for process in list(self.active):
            self.stop(process)
        self.active.clear()
        self.source.write_text(self.original)
        summary = {"schema": "application-durability-qualification-v1", "complete": success,
                   "error": error, "scope": "native correctness and process-crash recovery; no timing/power-loss claim",
                   "compiler_sha256": file_digest(self.compiler), "zig_sha256": file_digest(self.zig),
                   "fixture_sha256": digest(self.original.encode()), "shim_source_sha256": digest(SHIM.read_bytes()),
                   "builds": self.builds, "calls": self.calls, "crash_cases": self.cases}
        (self.output / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler", type=Path, required=True)
    parser.add_argument("--zig", type=Path, default=os.environ.get("MYLANG_ZIG", os.environ.get("ZIG", shutil.which("zig"))))
    parser.add_argument("--output", type=Path)
    parser.add_argument("--smoke", action="store_true", help="bounded permanent gate matrix")
    parser.add_argument("--kind", choices=("all", "persistent", "durable"), default="all")
    args = parser.parse_args()
    if args.zig is None:
        parser.error("pass --zig or set MYLANG_ZIG to the pinned toolchain")
    automatic = args.output is None
    temporary = None
    if automatic:
        temporary = Path(tempfile.mkdtemp(prefix="application-cache-", dir=os.environ.get("TMPDIR")))
        args.output = temporary / "evidence"
    def interrupted(number, _frame):
        raise KeyboardInterrupt(f"received signal {number}")
    for number in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
        signal.signal(number, interrupted)
    harness = Harness(args.compiler, args.zig, args.output)
    try:
        if args.smoke:
            harness.smoke()
        elif args.kind in ("all", "persistent"):
            harness.persistent()
        if not args.smoke and args.kind in ("all", "durable"):
            harness.durable()
    except BaseException as error:
        harness.save(False, repr(error))
        raise
    harness.save(True)
    print(json.dumps({"complete": True, "calls": len(harness.calls), "crashes": len(harness.cases)}))
    if automatic:
        shutil.rmtree(temporary)


if __name__ == "__main__":
    main()
