#!/usr/bin/env python3
"""Read-only verification of the frozen discovery correction handoff."""
import hashlib
import json
from pathlib import Path


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    package = Path("experiments/new-core-s4-project-tests-20261006")
    handoff = package / "tool-discovery-correction-01"
    manifest = json.loads((handoff / "manifest.json").read_text())
    total = 0
    for row in manifest["files"]:
        path = handoff / row["path"]
        assert path.is_file() and not path.is_symlink(), row["path"]
        data = path.read_bytes()
        assert not data.startswith(b"\x7fELF"), row["path"]
        assert len(data) == row["bytes"] and sha(path) == row["sha256"], row["path"]
        total += len(data)
    assert manifest["count"] == len(manifest["files"]) == 126
    assert total == manifest["bytes"] == 1195387
    source = json.loads((handoff / "source-notdir-23.json").read_text())
    assert source == json.loads((handoff / "source-final-29.json").read_text())
    assert all(sha(Path(path)) == digest for path, digest in source.items())
    artifacts = json.loads((handoff / "artifacts-26.json").read_text())
    assert artifacts["source_unchanged"] is True
    for artifact in (artifacts["core"], artifacts["probe"]):
        assert sha(Path(artifact["path"])) == artifact["sha256"]
    commands = json.loads((handoff / "commands-24-26.json").read_text())
    assert len(commands) == 3 and all(c["exit_code"] == 0 for c in commands)
    assert "All 27 tests passed." in (handoff / "focus-24.log").read_text()
    assert "88 check(s) passed" in (handoff / "guardian-29.log").read_text()
    native = json.loads((handoff / "native-replay-28-summary.json").read_text())
    assert native["classification"] == "GREEN" and len(native["cases"]) == 3
    expected_object = "d8dd5741be1e8c641748d89dec8810ff602a9203e1b8afeaf4006e4cfe7a0b37"
    for index, case in enumerate(native["cases"]):
        assert case["status"] == 0
        assert case["values"]["cacheable_after"] == "false"
        for phase in ("native_before", "native_after"):
            receipt = case[phase]
            assert receipt["status"] == 0 and receipt["timeout"] is False
            assert receipt["object_sha256"] == expected_object
            argv = receipt["command"]
            assert sha(Path(argv[argv.index("-o", argv.index("cc")) + 1])) == expected_object
        if index:
            assert case["values"]["cacheable_before"] == "false"
            assert case["core_fallback"]["status"] == 0
            assert case["core_fallback"]["timeout"] is False
            assert case["native_guest"]["status"] == 7
            assert case["native_guest"]["timeout"] is False
            assert case["owned_private_cache_leftovers"] == []
            assert sha(Path(case["native_guest"]["command"][0])) == case["guest_sha256"]
        if index != 1:
            assert case["values"]["unchanged"] == "false"
            assert case["values"]["before_digest"] != case["values"]["after_digest"]
            assert case["values"]["before_generation"] != case["values"]["after_generation"]
    result = {
        "classification": "GREEN",
        "scope": "read-only source, handoff, artifact and native receipt verification",
        "manifest_sha256": sha(handoff / "manifest.json"),
        "handoff_files": manifest["count"],
        "handoff_bytes": total,
        "source_sha256": source,
        "native_receipt_sha256": sha(handoff / "native-replay-28-summary.json"),
        "actual_native_objects": 6,
        "unknown_layout_fallback_builds": 2,
        "focused_tests": 27,
        "guardian_checks": 88,
        "full_package_qualification": False,
    }
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
