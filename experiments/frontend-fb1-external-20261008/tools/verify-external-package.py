#!/usr/bin/env python3
"""Verify final saved gate receipts without executing any compiler or oracle."""
from pathlib import Path
import hashlib
import json

root = Path(__file__).resolve().parents[1]
summary = {}
compiler = Path("/home/epentland/ai/canopy/mylang-worktrees/codex-frontend-fb1/zig-out/bin/mylang")
identities = json.loads((root / "input-identities.json").read_text())
assert hashlib.sha256(compiler.read_bytes()).hexdigest() == identities["compiler"]["sha256"]
for corpus, area, commands, expected in (("lox", "lox-tests-fixed", 84, 65), ("eda", "eda-tests", 366, 310)):
    folder = root / area
    saved = json.loads((folder / "summary.json").read_text())
    assert not saved["mismatches"] and saved["commands"] == commands
    assert all(saved[key] for key in ("compiler_sources_unchanged", "compiler_unchanged",
        "source_manifest_unchanged", "reference_sources_unchanged", "reference_files_unchanged"))
    assert all(count == expected for count in saved["directory_counts"].values())
    assert all(saved["totals"]["current-" + mode]["tests"] == expected
        and saved["totals"]["current-" + mode]["failed"] == 0 for mode in ("debug", "release", "verify"))
    comparisons = json.loads((folder / "comparisons.json").read_text())
    assert all(not entry["problems"] and entry["complete_report_identical"]
        and entry["stdout_normalized_identical"] and entry["stderr_normalized_identical"]
        for entry in comparisons.values())
    summary[corpus] = {"summary": area + "/summary.json",
        "summary_sha256": hashlib.sha256((folder / "summary.json").read_bytes()).hexdigest(),
        "commands": commands, "tests_per_mode": expected, "directory_tests_per_mode": expected}
    if corpus == "lox":
        assert all(saved[key] for key in ("collector_unchanged", "settings_helper_unchanged",
            "settings_context_unchanged", "settings_witness_unchanged"))
        assert all(saved["totals"]["configured-" + mode]["tests"] == 13
            and saved["totals"]["configured-" + mode]["failed"] == 0 for mode in ("debug", "release", "verify"))
        proofs = list((folder / "settings").glob("*/configured/*.proof.json"))
        assert len(proofs) == 3 and all(json.loads(path.read_text())["all_other_inputs_byte_equal"] for path in proofs)
        configured = [entry for name, entry in comparisons.items() if "/configured/" in name]
        assert len(configured) == 3 and all(len(entry["normalizations"]["reference"])
            == len(entry["normalizations"]["candidate"]) == 13 for entry in configured)
        assert all(entry["stdout_identical"] and entry["stderr_identical"]
            for name, entry in comparisons.items() if "/configured/" not in name)
        summary[corpus].update(configured_cases_per_mode=13, settings_fields_proven=39)
    else:
        assert all(entry["stdout_identical"] and entry["stderr_identical"] for entry in comparisons.values())
for corpus, count in (("lox", 974), ("eda", 34)):
    answers = json.loads((root / f"native-{corpus}.answers.json").read_text())["summary"]
    assert answers["cases"] == count and not answers["failed"] and not answers["mismatches"] and answers["binary_unchanged"]
    manifest = json.loads((root / f"native-{corpus}.manifest.json").read_text())
    assert manifest["verified_lossless"]
    archive = root / f"native-{corpus}.tar.gz"
    assert hashlib.sha256(archive.read_bytes()).hexdigest() == manifest["archive_sha256"]
    summary[corpus]["native_cases"] = count
summary.update(compiler_sha256=identities["compiler"]["sha256"], frozen_answers_rerun=False, cpu10_performance_claim=False)
(root / "FINAL.json").write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")
print(json.dumps(summary, sort_keys=True))
