#!/usr/bin/env python3
"""Verify archived word-overwrite observations without rerunning benchmarks."""
import gzip
import hashlib
import json
from pathlib import Path
import statistics
import sys

ROOT = Path(__file__).resolve().parent


def content(name):
    return gzip.decompress((ROOT / (name + ".gz")).read_bytes())


def data(name):
    return json.loads(content(name))


def digest(bits):
    return hashlib.sha256(bits).hexdigest()


def balanced(counts):
    assert counts["runtime"] == "rc-v3-counting"
    assert not counts["saturated"]
    assert counts["heap_allocate"] == counts["retire"]
    assert counts["hold_acquire"] == counts["hold_release"]
    assert counts["owner_acquire"] + counts["heap_allocate"] == counts["owner_release"]


def instructions(row):
    lines = [line.split(",") for line in row["perf"].splitlines()]
    active = [fields for fields in lines if len(fields) > 4 and fields[0].isdigit()]
    active = [fields for fields in active if "instructions" in fields[2]]
    assert len(active) == 1, row
    assert float(active[0][4]) == 100.0
    assert int(active[0][0]) == row["instructions"]
    assert row["status"] == 0


def trace(row):
    return "\n".join(line for line in row["stderr"].splitlines()
                     if not line.startswith("MYLANG_RC_COUNTS "))


def main():
    index = json.loads((ROOT / "files.json").read_text())
    for name, expected in index.items():
        bits = content(name)
        assert len(bits) == expected["bytes"]
        assert digest(bits) == expected["sha256"], name
    identity = json.loads((ROOT / "identity.json").read_text())
    assert identity["base"] == "88f4e47728b1ad33058e847009cbaa2be91fd45f"
    expected_output = content("workload/dict_count.expected").decode()
    expected_counts = None
    observed = 0
    for variant in ("find", "repeat"):
        receipt = data(variant + "-measurements.json")
        compiler = next(row for row in identity["compilers"] if row["side"] == variant)
        assert receipt["compiler"]["sha256"] == compiler["sha256"]
        assert receipt["source"]["sha256"] == digest(content("workload/dict_count.my"))
        assert len(receipt["runs"]) == 22
        for build in receipt["builds"]:
            assert build["status"] == 0
            assert build["manifest"]["backend"] == build["backend"]
            if build["backend"] == "llvm":
                assert build["manifest"]["optimization"] == "3"
                assert build["manifest"]["lto"] and not build["manifest"]["thin_lto"]
        for row in receipt["runs"]:
            assert row["stdout"] == expected_output and row["status"] == 0
            if row.get("stats"):
                balanced(row["counts"])
                expected_counts = expected_counts or row["counts"]
                assert row["counts"] == expected_counts
                continue
            instructions(row)
            observed += 1
            binary = next(item for item in identity["binaries"]
                          if item["side"] == row["side"] and item["backend"] == row["backend"])
            assert row["binary_sha256"] == binary["sha256"]
        for backend in ("qbe", "llvm"):
            for side in ("gc", "before", variant):
                values = [row["instructions"] for row in receipt["runs"]
                          if row["side"] == side and row["backend"] == backend and not row.get("stats")]
                assert len(values) == 3
                assert statistics.median(values) == receipt["medians"][side + "-" + backend]
    assert observed == 36
    assert expected_counts["heap_allocate"] == 2029
    assert expected_counts["owner_acquire"] == expected_counts["hold_acquire"] == 2001
    assert expected_counts["unique_check"] == 1001 and expected_counts["clone_shell"] == 0
    mixed = data("mixed.json")
    assert len(mixed["runs"]) == 18
    assert mixed["source_sha256"] == digest(content("mixed.my"))
    for row in mixed["runs"]:
        instructions(row)
        assert row["stdout"] == mixed["runs"][0]["stdout"]
    for backend in ("qbe", "llvm"):
        for side in ("before", "find", "repeat"):
            values = [row["instructions"] for row in mixed["runs"]
                      if row["side"] == side and row["backend"] == backend]
            assert len(values) == 3
            assert statistics.median(values) == mixed["medians"][side + "-" + backend]
        assert mixed["medians"]["repeat-" + backend] > mixed["medians"]["before-" + backend]
        assert mixed["medians"]["repeat-" + backend] > mixed["medians"]["find-" + backend]
    guests = data("guests.json")["runs"]
    assert len(guests) == 8
    assert all(row["status"] == 0 and json.loads(row["stdout"])["failed"] == 0 for row in guests)
    assert sum(json.loads(row["stdout"])["passed"] for row in guests) == 64
    controls = data("controls.json")["runs"]
    assert len(controls) == 28
    for row in controls:
        balanced(row["counts"])
        if row["side"] != "before":
            continue
        other = next(candidate for candidate in controls if candidate["side"] == "after"
                     and all(candidate[key] == row[key] for key in ("backend", "case", "budget", "options")))
        assert (row["status"], row["stdout"], trace(row)) == (other["status"], other["stdout"], trace(other))
        assert row["counts"] == other["counts"]
    reentrant = data("reentrant.json")["runs"]
    assert len(reentrant) == 4
    for row in reentrant:
        assert row["status"] == 0 and row["stdout"] == "status=0 phase=2 observed=1 bad=0 result=10\n"
        balanced(row["counts"])
    assert b"native RC collections: 47 passed" in content("logs/native-final.log")
    assert b"native RC collections: 47 passed" in content("logs/native-before.log")
    assert b"word_phase==2 && word_source==99" in content("logs/native-no-queue.log")
    assert b"88 check(s) passed" in content("logs/guardian-final.log")
    assert content("source/native_dictionary.c") == content("native_dictionary-find.c")
    assert b"myl_rc_descriptor_repeat" not in content("source/native_dictionary.c")
    qbe = next(item for item in identity["guest_objects"] if item["backend"] == "qbe")
    assert qbe["before"]["sha256"] == qbe["after"]["sha256"]
    if "--live" in sys.argv[1:]:
        for item in identity["compilers"] + identity["binaries"]:
            assert digest(Path(item["path"]).read_bytes()) == item["sha256"], item["path"]
    print("verified: 54 instruction observations, eight counted runs, 64 assertions, 28 paired controls, four finalizer entries")


if __name__ == "__main__":
    main()
