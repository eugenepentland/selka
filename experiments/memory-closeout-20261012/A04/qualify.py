#!/usr/bin/env python3
"""Qualify every A04 export without writing historical reports.

Owns shared build admission per lane. Compile durations are operational observations,
not controlled performance measurements. Scratch binaries remain outside evidence.
"""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
from build_admission import admission
MODULES = ("json", "strings", "path", "base64", "hex", "byte_builder")
FIXTURES = ("strings", "path", "codecs", "byte_builder", "json")
SUPPLEMENT = ROOT / "tests/lang/a04_memory_library_contracts.my"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def save(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2) + "\n")


def inventory():
    sources = [ROOT / f"src/stdlib/fixtures/{name}.my" for name in FIXTURES] + [SUPPLEMENT]
    declarations = []
    for module in MODULES:
        source = ROOT / f"src/stdlib/{module}.my"
        for lineno, line in enumerate(source.read_text().splitlines(), 1):
            match = re.match(r"public (func|record|enum) (\w+)", line)
            if not match:
                continue
            kind, name = match.groups()
            coverage = [str(path.relative_to(ROOT)) for path in sources if f"{module}.{name}(" in path.read_text()]
            if kind != "func":
                contract = "Owned aggregate; managed children move into constructors; borrowing field access does not transfer ownership."
            elif "mut " in line:
                contract = "Exclusive mutable builder writeback; ordinary data/text arguments borrowed for the call; scalar success or Unit returned."
            elif name in ("digits", "letters", "whitespace", "standard_alphabet", "urlsafe_alphabet", "separator", "type_name"):
                contract = "Ordinary input borrowed when present; immutable literal result may use immortal storage."
            elif any(f"-> {scalar}" in line for scalar in ("int", "bool", "float")):
                contract = "Ordinary managed inputs borrowed; scalar or optional-scalar result owns no input storage."
            else:
                contract = "Ordinary managed inputs borrowed; managed return independently owned (explicit deep copy, construction or owned temporary transfer)."
            if module == "byte_builder" and name == "finish":
                contract = "Builder borrowed; immutable bytes snapshot owns a fresh copy and survives builder mutation/destruction."
            declarations.append({"module": module, "name": name, "kind": kind, "line": lineno,
                                 "source": str(source.relative_to(ROOT)), "source_sha256": digest(source),
                                 "signature": line, "contract": contract, "coverage_sources": coverage,
                                 "scope": "supported public contract", "qualification": "see phase results; inventory alone is not a pass"})
    uncovered = [f"{row['module']}.{row['name']}" for row in declarations if row["kind"] == "func" and not row["coverage_sources"]]
    return {"schema": "memory-closeout-a04-inventory-v1", "declarations": declarations,
            "public_functions": sum(row["kind"] == "func" for row in declarations),
            "public_types": sum(row["kind"] != "func" for row in declarations), "uncovered_functions": uncovered,
            "boundaries": ["Ordinary source parameters borrow; returning that borrowed storage requires explicit .copy().",
                           "Borrowed text/byte views may not escape their owner, be stored in aggregates, or survive owner mutation/replacement.",
                           "Text classification/case conversion in strings is ASCII as documented; ord/chr and UTF-8 operations cover Unicode scalars.",
                           "Malformed input is an API Result/Option error, not an unsupported ownership shape."]}


def capture(args):
    spec = importlib.util.spec_from_file_location("historical_qualify", ROOT / "experiments/zero-rc-closeout-20261011/qualify.py")
    q = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(q)
    # Import helper functions only. Historical main writes into its old evidence
    # directory and must never be called by this adapter.
    for name in ("compiler", "zig", "output", "evidence"):
        setattr(args, name, getattr(args, name).resolve())
    result_path = args.evidence / "results.json"
    if result_path.exists() and not args.resume:
        raise SystemExit(f"Refusing to overwrite {result_path}; choose a new phase directory")
    env = dict(os.environ, ZIG=str(args.zig), MYLANG_ZIG=str(args.zig), MYL_CORE_LEAKCHECK="1")
    for name in ("MYLANG_COUNTERS", "MYLANG_OPTIONS", "MYLANG_CORE_SANITIZE"):
        env.pop(name, None)
    result = {"schema": "memory-closeout-a04-results-v1", "compiler": {"path": str(args.compiler), "sha256": digest(args.compiler), "source_commit": args.source_commit},
              "harness_sha256": digest(Path(__file__)), "inventory": inventory(), "cases": {},
              "limitations": ["Managed counters omit native metadata/provider buffers/allocator overhead; no RSS or timing claims.",
                              "Count-free LLVM and symbol checks supplement execution counters; package bootstrap is owned by A10."]}
    if args.resume and result_path.exists():
        previous = json.loads(result_path.read_text())
        assert "summary" not in previous, "completed evidence is immutable; choose a new phase"
        assert previous["compiler"] == result["compiler"], "compiler identity changed"
        assert previous["inventory"] == result["inventory"], "export inventory changed"
        result = previous
        result.setdefault("resume_harness_sha256", []).append(digest(Path(__file__)))
    result["selection"] = {"baseline": args.baseline, "only": args.only, "modes": args.modes,
                           "note": "baseline runs every case in release plus the new public ownership supplement in all requested modes; final qualification uses all modes"}
    cases = [(name, ROOT / f"src/stdlib/fixtures/{name}.my", 42) for name in FIXTURES]
    cases.extend([("ownership_contracts", SUPPLEMENT, 0), ("json_lookup", ROOT / "test/core/zero_rc_json_lookup.my", 0),
                  ("view_contracts", HERE / "samples/view_contracts.my", 0)])
    modes = {name: flags for name, flags in q.common.MODES.items() if not args.modes or name in args.modes}
    failures = len(result["inventory"]["uncovered_functions"]) + sum(row["status"] != "passed" for modes in result["cases"].values() for row in modes.values())
    for name, source, expected in cases:
        if args.only and name not in args.only:
            continue
        lanes = result["cases"].setdefault(name, {})
        for mode, flags in modes.items():
            if args.baseline and name != "ownership_contracts" and mode != "release":
                continue
            if mode in lanes:
                assert lanes[mode]["source_sha256"] == digest(source), "completed source changed"
                print(name, mode, "preserved", lanes[mode]["status"], flush=True)
                continue
            try:
                with admission("build"):
                    lanes[mode] = dict(q.lane(args, env, name, source, ["--experimental-zero-rc", *flags], mode, expected), status="passed")
            except (AssertionError, subprocess.SubprocessError, OSError) as error:
                failures += 1
                lanes[mode] = {"status": "failed", "error": str(error), "source_sha256": digest(source)}
            raw = args.output / name / mode
            destination = args.evidence / "raw" / name / mode
            destination.mkdir(parents=True, exist_ok=True)
            for pattern in ("*.my", "*.json", "*.stdout", "*.stderr"):
                for artifact in raw.glob(pattern):
                    shutil.copyfile(artifact, destination / artifact.name)
            save(result_path, result)
            print(name, mode, lanes[mode]["status"], flush=True)
    result["negative_cases"] = {}
    for name, diagnostic in (("view_invalidated", "E_ZERO_RC_VIEW_INVALIDATED"), ("byte_view_invalidated", "E_ZERO_RC_VIEW_INVALIDATED"),
                             ("view_escape", "E_ZERO_RC_VIEW_SIGNATURE")):
        source = HERE / "samples" / (name + ".my")
        command = [str(args.compiler), "check", str(source), "--experimental-zero-rc"]
        with admission("build"):
            ran = subprocess.run(command, cwd=ROOT, env=env, capture_output=True, text=True, timeout=120)
        passed = ran.returncode == 1 and diagnostic in ran.stderr
        result["negative_cases"][name] = {"command": command, "status": "passed" if passed else "failed", "exit_code": ran.returncode,
                                          "stdout": ran.stdout, "stderr": ran.stderr, "source_sha256": digest(source), "expected_diagnostic": diagnostic}
        failures += not passed
    result["summary"] = {"lanes": sum(len(rows) for rows in result["cases"].values()), "failed": failures,
                         "uncovered_functions": result["inventory"]["uncovered_functions"]}
    assert result["compiler"]["sha256"] == digest(args.compiler), "compiler changed during qualification"
    save(result_path, result)
    return int(bool(failures))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--inventory", action="store_true")
    parser.add_argument("--resume", action="store_true", help="resume an interrupted phase only when compiler, exports and completed sources match")
    parser.add_argument("--baseline", action="store_true", help="all exports in release and new ownership supplement across five modes; final qualification remains the full matrix")
    for name in ("compiler", "zig", "output", "evidence"):
        parser.add_argument("--" + name, type=Path)
    parser.add_argument("--source-commit")
    parser.add_argument("--modes", nargs="+", choices=("release", "debug", "verify", "optimized_debug", "no_facts"))
    parser.add_argument("--only", nargs="+", choices=(*FIXTURES, "ownership_contracts", "json_lookup", "view_contracts"))
    args = parser.parse_args()
    if args.inventory:
        report = inventory()
        save(HERE / "inventory.json", report)
        return int(bool(report["uncovered_functions"]))
    if not all(getattr(args, name) for name in ("compiler", "zig", "output", "evidence", "source_commit")):
        parser.error("capture requires --compiler, --zig, --output, --evidence and --source-commit")
    return capture(args)


if __name__ == "__main__":
    sys.exit(main())
