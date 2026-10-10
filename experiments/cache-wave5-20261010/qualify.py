#!/usr/bin/env python3
"""Qualify native Juice workload reuse with static syscall-only assembly fixtures.

This driver invokes no build tools itself. juice_cache.py owns admission and
native Juice builds/captures. Retained experiment output excludes executables.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
SHARED = ".macro step\n    add $1, %eax\n.endm\n"
BUILD = """#!/bin/sh
set -eu
compiler=$1
linker=$2
project=$3
binary=$4
provider=$5
"$compiler" --64 -I "$provider" "$project/work.S" -o "$project/work.o"
"$linker" -m elf_x86_64 -nostdlib --no-dynamic-linker --build-id=none -o "$binary" "$project/work.o"
"""
ASSEMBLY = """.include "step.inc"
.global _start
.section .text
_start:
    mov $65569, %ecx
    xor %eax, %eax
.Lwork:
    step
    dec %ecx
    jnz .Lwork
    mov %al, result(%rip)
    mov $1, %eax
    mov $1, %edi
    lea result(%rip), %rsi
    mov $2, %edx
    syscall
    mov $60, %eax
    xor %edi, %edi
    syscall
.section .data
result:
    .byte 0, 10
.section .note.GNU-stack,"",@progbits
"""
UNTRACKED = ("LD_PRELOAD", "LD_LIBRARY_PATH", "LD_AUDIT", "PYTHONPATH", "PYTHONHOME",
             "ZIG_LIB_DIR", "CC", "CXX", "CPATH", "C_INCLUDE_PATH",
             "CPLUS_INCLUDE_PATH", "LIBRARY_PATH")
SELKA = """func main(args: str[], out: Stream) -> int:
    mut total = 0
    for i in range(len(args) + 65568):
        total += 1
    out.print(total)
    return 0
"""


def save(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def sha(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        while data := stream.read(1 << 20):
            digest.update(data)
    return digest.hexdigest()


def fixture(work):
    """Create separate ELF closures; only alpha and beta consume the shared macro."""
    fixtures = work / "fixtures"
    shared = fixtures / "shared"
    shared.mkdir(parents=True)
    (shared / "step.inc").write_text(SHARED)
    rows = []
    for name in ("alpha", "beta", "gamma"):
        project = fixtures / name
        project.mkdir()
        (project / "build.sh").write_text(BUILD)
        (project / "work.S").write_text(ASSEMBLY)
        local = name == "gamma"
        if local:
            (project / "step.inc").write_text(SHARED)
        manifest = {
            "version": 1, "name": "wave5-" + name, "adapter": "native",
            "sources": ["build.sh", "work.S"] + (["step.inc"] if local else []),
            "build": {
                "compiler": "/usr/bin/as",
                "command": ["/bin/sh", "{root}/build.sh", "{compiler}", "/usr/bin/ld",
                            "{root}", "{binary}", "{root}" if local else str(shared)],
                "tools": ["/bin/sh", "/usr/bin/ld", "size", "nm", "objdump", "ldd"],
                "dependencies": [] if local else [str(shared)],
            },
            "workloads": [{"name": name, "family": "synthetic-static-counting",
                           "unit": "completed scenario", "units": 1,
                           "expected_stdout": "!\n", "timeout_seconds": 10}],
        }
        save(project / "juice.json", manifest)
        rows.append({"id": name, "manifest": str(project / "juice.json"), "workload": name,
                     "complete": True, "reuse": "historical", "dependencies": []})
    suite = work / "suite.json"
    save(suite, {"version": "juice-suite-v1", "workloads": rows})
    return suite


def selka_fixture(work):
    """An ordinary dynamically linked Selka guest with an isolated config."""
    project = work / "fixtures/selka"
    project.mkdir()
    (project / "main.my").write_text(SELKA)
    save(project / "mylang.json", {"version": 2})
    manifest = {"version": 1, "name": "wave5-selka", "adapter": "mylang",
                "sources": ["main.my", "mylang.json"],
                "build": {"entry": "main.my", "compiler": "mylang",
                          "tools": ["size", "nm", "objdump", "ldd"],
                          "counter_semantics": "Selka Core runtime counters; plain perf capture"},
                "workloads": [{"name": "selka", "family": "selka-dynamic-counting",
                               "unit": "completed scenario", "units": 1,
                               "args": ["nonce"], "expected_stdout": "65569\n",
                               "timeout_seconds": 10}]}
    save(project / "juice.json", manifest)
    providers = ["/usr/lib/x86_64-linux-gnu/libc.so.6",
                 "/usr/lib/x86_64-linux-gnu/libm.so.6",
                 "/usr/lib/x86_64-linux-gnu/libpthread.so.0", "/lib64/ld-linux-x86-64.so.2"]
    suite = work / "selka-suite.json"
    save(suite, {"version": "juice-suite-v1", "workloads": [
        {"id": "selka", "manifest": str(project / "juice.json"), "workload": "selka",
         "complete": True, "reuse": "historical", "dependencies": providers}]})
    return suite


class Qualification:
    def __init__(self, args):
        self.args = args
        self.output = args.output.absolute()
        self.work = args.work.absolute()
        self.output.mkdir(parents=True, exist_ok=False)
        self.work.mkdir(parents=True, exist_ok=False)
        self.suite = fixture(self.work)
        self.selka_suite = selka_fixture(self.work) if args.selka else None
        self.env = dict(os.environ)
        removed = {name: self.env.pop(name) for name in UNTRACKED if name in self.env}
        self.env.update(PYTHONNOUSERSITE="1", PYTHONDONTWRITEBYTECODE="1", PYTHONPYCACHEPREFIX="/dev/null")
        self.records = {}
        self.state = {"version": "juice-wave5-native-qualification-v1", "success": False,
                      "scope": "real native perf counting, workload reuse and invalidation; no elapsed-time claim",
                      "checks": {}, "commands": [], "reports": {},
                      "compiler": {"path": str(args.compiler.resolve()), "sha256": sha(args.compiler)},
                      "removed_environment_variables": sorted(removed),
                      "work_directory": str(self.work), "output_directory": str(self.output)}

    def invoke(self, label, arguments, expected=0):
        argv = [sys.executable, "-B", str(ROOT / "scripts/juice_cache.py"), *map(str, arguments),
                "--compiler", str(self.args.compiler.absolute())]
        log = self.output / (label + ".log")
        with log.open("wb") as stream:
            result = subprocess.run(argv, cwd=ROOT, env=self.env, stdout=stream,
                                    stderr=subprocess.STDOUT, timeout=self.args.timeout)
        self.state["commands"].append({"label": label, "argv": argv, "status": result.returncode,
                                       "expected_status": expected, "log": log.name})
        if result.returncode != expected:
            raise RuntimeError(label + " returned " + str(result.returncode) + "; see " + str(log))

    def capture(self, label, executed, reused, *extra, suite=None):
        report = self.work / (label + ".json")
        try:
            self.invoke(label, ["capture", suite or self.suite, "--cache-dir", self.work / "cache",
                                "--report", report, "--repeats", "3", *extra])
        finally:
            if report.is_file():
                self.records[label] = report
                self.state["reports"][label] = json.loads(report.read_text())
        value = self.state["reports"][label]
        counts = value["counts"]
        expected = {"executed": executed, "reused": reused, "admissions": executed}
        passed = value["complete"] is True and value["success"] is True and counts == expected
        self.state["checks"][label] = {"passed": passed, "expected_counts": expected, "counts": counts}
        if not passed:
            raise RuntimeError(label + " did not match qualified execution/reuse counts")
        return value

    def compare(self, label, threshold, expected):
        destination = self.work / label
        retained = self.records["context-warm"]
        self.invoke(label, ["compare", retained, retained, "--output", destination,
                            "--fail-above", threshold, "--max-spread", "0.1", "--min-change", "0"], expected)
        value = json.loads((destination / "decisions.json").read_text())
        passed = value["complete"] is True and value["measurements_executed"] == 0 and value["admissions"] == 0
        self.state["checks"][label] = {"passed": passed, "expected_status": expected, "decisions": value}
        if not passed:
            raise RuntimeError(label + " unexpectedly measured or requested admission")

    def run(self):
        if self.args.selka_only:
            self.run_selka()
            self.state["success"] = True
            return
        self.capture("cold", 3, 0)
        self.capture("warm", 0, 3)
        alpha = self.work / "fixtures/alpha/work.S"
        alpha.write_text(ASSEMBLY.replace("    step\n", "    step\n    nop\n"))
        self.capture("private-edit", 1, 2)
        alpha.write_text(ASSEMBLY)
        self.capture("private-revert", 0, 3)
        helper = self.work / "fixtures/shared/step.inc"
        helper.write_text(SHARED.replace(".endm", "    nop\n.endm"))
        self.capture("shared-edit", 2, 1)
        helper.write_text(SHARED)
        self.capture("shared-revert", 0, 3)
        self.capture("context-repeats", 3, 0, "--repeats", "2")
        self.capture("context-warm", 0, 3, "--repeats", "2")
        self.compare("threshold-pass", "101", 0)
        self.compare("threshold-fail", "99", 1)
        latest = self.capture("forced-fresh", 3, 0, "--repeats", "2", "--fresh")
        digest = latest["actions"][0]["record_sha256"]
        corrupted = self.work / "cache/evidence/blobs" / digest
        if not corrupted.is_file():
            raise RuntimeError("expected retained record blob does not exist")
        corrupted.write_bytes(b"intentional qualification corruption\n")
        self.capture("corrupt-record", 1, 2, "--repeats", "2")
        if self.selka_suite:
            self.run_selka()
        self.state["success"] = True

    def run_selka(self):
        cold = self.capture("selka-cold", 1, 0, suite=self.selka_suite)
        warm = self.capture("selka-warm", 0, 1, suite=self.selka_suite)
        path = Path(cold["actions"][0]["record"])
        libraries = json.loads(path.read_text())["context"]["libraries"]
        passed = bool(libraries) and warm["actions"][0]["qualified"] is True
        self.state["checks"]["selka-dynamic-providers"] = {"passed": passed, "libraries": libraries}
        if not passed:
            raise RuntimeError("Selka dynamic provider evidence was not qualified and reused")

    def retain(self):
        """Copy only text/JSON/raw collector evidence; never copy ELF artifacts."""
        shutil.copytree(self.work / "fixtures", self.output / "fixtures")
        shutil.copyfile(self.suite, self.output / "suite.json")
        if self.selka_suite:
            shutil.copyfile(self.selka_suite, self.output / "selka-suite.json")
        for label, report in self.records.items():
            shutil.copyfile(report, self.output / (label + ".json"))
            for row in self.state["reports"][label]["actions"]:
                path = Path(row.get("record", ""))
                if not path.is_file():
                    continue
                directory = self.output / "raw" / label / row["id"]
                directory.mkdir(parents=True, exist_ok=True)
                document = json.loads(path.read_text())
                shutil.copyfile(path, directory / "record.json")
                for name in document.get("evidence", {}):
                    source = path.parent / name
                    if source.is_file():
                        shutil.copyfile(source, directory / name)
        for label in ("threshold-pass", "threshold-fail"):
            directory = self.work / label
            if directory.is_dir():
                target = self.output / label
                target.mkdir()
                for path in directory.iterdir():
                    if path.is_file() and path.suffix in (".json", ".md"):
                        shutil.copyfile(path, target / path.name)
        save(self.output / "results.json", self.state)
        files = {str(path.relative_to(self.output)): sha(path) for path in sorted(self.output.rglob("*"))
                 if path.is_file() and path.name != "evidence-sha256.json"}
        save(self.output / "evidence-sha256.json", files)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler", type=Path, default=ROOT / "zig-out/bin/mylang")
    parser.add_argument("--work", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--timeout", type=float, default=1800)
    parser.add_argument("--selka", action="store_true", help="also qualify an ordinary dynamic Selka workload")
    parser.add_argument("--selka-only", action="store_true", help="qualify only the ordinary dynamic Selka workload")
    args = parser.parse_args()
    args.selka = args.selka or args.selka_only
    qualification = Qualification(args)
    try:
        qualification.run()
    except BaseException as error:
        qualification.state["error"] = str(error) or type(error).__name__
        raise
    finally:
        qualification.retain()


if __name__ == "__main__":
    main()
