#!/usr/bin/env python3
"""Strict six-corpus S4 acceptance sweep, with pinned external port sources."""
import argparse
import glob
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[3]
DEFAULT_LOX = Path("/home/epentland/ai/canopy/mylang-worktrees/codex-s4-lox-value-semantics")
DEFAULT_EDA = Path("/home/epentland/ai/canopy/eda-bench-wt/codex-s4-eda-stage1")


def git(root, *args):
    return subprocess.check_output(["git", "-C", str(root), *args], text=True).strip()


def port_entry(source, destination):
    """Check every module, including test-only modules, in its original topology."""
    shutil.copytree(source, destination, ignore=shutil.ignore_patterns(".mylang-cache", ".zig-cache", "zig-out", ".git"))
    files, synthetic = [], set()
    for path in sorted(destination.rglob("*.my")):
        text = path.read_text()
        found = re.search(r"^module\s+([A-Za-z_][A-Za-z_0-9.]*)", text, re.MULTILINE)
        if found is None:
            raise RuntimeError(f"port module lacks a header: {path}")
        module = found.group(1)
        if not re.search(r"^(?:public\s+)?def\s+main\s*\(", text, re.MULTILINE):
            path.write_text(text.rstrip("\n") + "\n\ndef main() -> int:\n    return 0\n")
            synthetic.add(f"{module}::main")
        # The base Session derives its loader root from dirname(path). A dotted
        # alias keeps nested entries rooted at the project while the provider
        # still reads their actual nested paths. All aliases live in scratch.
        alias = destination / f"{module}.my"
        if alias != path:
            alias.symlink_to(path.relative_to(destination))
        files.append(str(alias))
    return files, synthetic


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--evidence", type=Path, required=True)
    parser.add_argument("--core", type=Path, default=ROOT / "zig-out/bin/mylang-core")
    parser.add_argument("--lox", type=Path, default=DEFAULT_LOX)
    parser.add_argument("--eda", type=Path, default=DEFAULT_EDA)
    args = parser.parse_args()
    area = args.evidence.resolve()
    if area.exists() or not area.is_relative_to(ROOT / "experiments"):
        parser.error("choose a fresh evidence directory under experiments")
    area.mkdir(parents=True)
    scratch = area / "scratch"
    scratch.mkdir()
    spec = importlib.util.spec_from_file_location("s0_coverage", ROOT / "experiments/new-core-s0-20261005/coverage.py")
    inherited = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(inherited)
    entries = scratch / "coverage-entries"
    shutil.copytree(ROOT / "tests/lang", entries, ignore=shutil.ignore_patterns(".mylang-cache", ".zig-cache", "zig-out"))
    lox_files, lox_synthetic = port_entry(args.lox / "benchmarks/lox/ports/mylang", scratch / "lox")
    eda_files, eda_synthetic = port_entry(args.eda / "mylang/src", scratch / "eda")
    corpora = {
        "examples": inherited.with_entry(sorted(glob.glob(str(ROOT / "examples/**/*.my"), recursive=True)), str(scratch / "coverage-examples")),
        "bench/parity": sorted(glob.glob(str(ROOT / "bench/parity/**/*.my"), recursive=True)),
        "tests/lang": inherited.with_entry(sorted(glob.glob(str(ROOT / "tests/lang/*.my"))), str(entries)),
        "benchmarks/runtime": sorted(glob.glob(str(ROOT / "benchmarks/runtime/expanded/*/main.my"))),
        "lox port": lox_files,
        "EDA Stage 1": eda_files,
    }
    report = {"qualified": False, "source_commit": git(ROOT, "rev-parse", "HEAD"),
              "core_sha256": hashlib.sha256(args.core.read_bytes()).hexdigest(),
              "ports": {"lox": git(args.lox, "rev-parse", "HEAD"), "eda": git(args.eda, "rev-parse", "HEAD")},
              "corpora": {}, "error": None}
    try:
        if report["ports"]["lox"] != "f44302d877dfc8a01b64673e70c44b9e0c49f063" or report["ports"]["eda"] != "510c2e229f8389e5cd9d82db690abc0084397b1c":
            raise RuntimeError("port source differs from the S4 plan pin")
        for index, (name, files) in enumerate(corpora.items(), 1):
            command = [str(args.core.resolve()), "coverage", *files]
            result = subprocess.run(command, text=True, capture_output=True, timeout=300,
                                    env={**os.environ, "TMPDIR": str(scratch)})
            (area / f"corpus-{index}.txt").write_text(result.stdout)
            (area / f"corpus-{index}.err").write_text(result.stderr)
            outcomes, frontend = {}, []
            for line in result.stdout.splitlines():
                kind, _, rest = line.partition(" ")
                if kind == "frontend":
                    frontend.append(rest)
                elif kind == "ok":
                    function = rest.partition("\t")[0]
                    synthetic = lox_synthetic if name == "lox port" else eda_synthetic if name == "EDA Stage 1" else set()
                    if function not in synthetic:
                        outcomes[function] = None
                elif kind == "refused":
                    reason, _, function = rest.partition("\t")
                    outcomes.setdefault(function, reason)
                else:
                    raise RuntimeError(f"unknown coverage output: {line}")
            report["corpora"][name] = {"command": command, "status": result.returncode, "files": len(files),
                                      "functions": len(outcomes), "accepted": sum(reason is None for reason in outcomes.values()),
                                      "frontend": frontend, "refused": {key: value for key, value in outcomes.items() if value is not None}}
            if result.returncode:
                raise RuntimeError(f"{name}: compiler exited {result.returncode}")
            if name in ("lox port", "EDA Stage 1") and (frontend or not outcomes):
                raise RuntimeError(f"{name}: project entry coverage failed")
            print(f"{name}: {report['corpora'][name]['accepted']}/{len(outcomes)} accepted", flush=True)
        report["qualified"] = True
    except Exception as error:
        report["error"] = f"{type(error).__name__}: {error}"
        print(report["error"], flush=True)
    finally:
        (area / "summary.json").write_text(json.dumps(report, indent=2) + "\n")
        shutil.rmtree(scratch)
    return int(not report["qualified"])


if __name__ == "__main__":
    raise SystemExit(main())
