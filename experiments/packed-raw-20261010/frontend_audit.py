#!/usr/bin/env python3
"""Reproduce frontend work attribution from the uncompressed paired benchmark."""
import argparse
import gzip
import hashlib
import json
from pathlib import Path
import re

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
DEFAULT_INPUT = HERE / "paired-raw.json.gz"
PHASES = ("entry_edit", "helper_edit", "three_file_edit")
EXPECTED_CHECKED = {12: (651, 649, 653), 32: (1731, 1729, 1733)}
EXPECTED_SYNTAX_TOTAL = {12: 723, 32: 1923}


def miss_names(source):
    declaration = re.search(r"pub const MissReason = enum \{(.*?)\n\};", source, re.S)
    assert declaration, "MissReason schema missing"
    names = re.findall(r"^\s*([a-z_]+),\s*$", declaration.group(1), re.M)
    assert len(names) == 16, names
    return names


def named_counts(values, names):
    assert len(values) == len(names)
    return dict(zip(names, values))


def audit(input_path):
    input_bytes = input_path.read_bytes()
    data = json.loads(gzip.decompress(input_bytes))
    schema_path = REPO / "src" / "semantic_cache.zig"
    schema_bytes = schema_path.read_bytes()
    names = miss_names(schema_bytes.decode())
    result = {
        "input": str(input_path.relative_to(REPO)) if input_path.is_relative_to(REPO) else str(input_path),
        "input_sha256": hashlib.sha256(input_bytes).hexdigest(),
        "miss_schema": {"source": "src/semantic_cache.zig:MissReason", "source_sha256": hashlib.sha256(schema_bytes).hexdigest(), "names": names},
        "sources": {
            "fresh_check_count": "src/sema.zig:reuseBody/checkInstance",
            "ordinary_retention_guards": "src/semantic_cache.zig:buildFreshEntry",
            "source_read_hash_header_lex": "src/project.zig:add/header",
            "declaration_rebuild": "src/interfaces.zig:buildWithCacheTimed",
            "mandatory_global_validation": "src/sema.zig:effects.check/domain_codecs.check/warning derivation",
        },
        "interpretation": {
            "units": "Checked counts are function bodies/instances, not source files or native objects.",
            "specializations": "not_ordinary denotes an ordinary-store lookup outside ordinary instances; reuseBody then tries specialization replay. Checked counts are incremented only when both reuse paths fail.",
            "retention": "Retention misses describe refusal to save ordinary bodies after checking. They are not extra fresh checks and must not be added to lookup misses. generic_specialization retention counts ordinary callers referencing concrete specializations, not specialized bodies.",
            "guarded_repeat": "Helper-edit excess 648/1728 is repeat checking associated with cache limitations. Guards are currently necessary for correctness; this is potential avoidable work after safe replay, not a proven removable minimum.",
            "minimum": "Deliberately edited body counts are 1/1/3, and exactly 1/1/3 are lowered and compiled into native objects. These observations do not prove the minimal semantic checking set: dependency propagation, diagnostics, effects, identity validation and global passes must remain sound.",
            "per_file": "The report does not attribute freshly checked bodies to individual source paths; the number of distinct files containing them is unknown.",
            "remaining_scan": "All reachable modules are read, hashed and header-lexed; cached syntax is replayed and all declaration/interface tables rebuilt. Global effect/origin and validation passes still run, using summary facts where available. This is overhead/validation, not native compilation.",
            "compression": "This audit reads candidate work counters. In paired-raw.json.gz the candidate uses uncompressed packs; wall-time comparisons are summarized separately.",
        },
        "sizes": {},
    }
    for copies, expected in EXPECTED_CHECKED.items():
        size = data["sizes"][str(copies)]
        output = {"project_modules": size["project_modules"], "physical_lines": size["physical_lines"], "reachability": size["reachability"], "syntax_units": EXPECTED_SYNTAX_TOTAL[copies], "phases": {}}
        for phase, expected_checked in zip(PHASES, expected):
            rows = [r for r in data["records"] if r["variant"] == "candidate" and r["copies"] == copies and r["phase"] == phase]
            assert len(rows) == data["repeats"] == 3
            edits = 3 if phase == "three_file_edit" else 1
            samples = []
            for row in rows:
                stages = row["cache"]["stages"]
                front = stages["frontend"]
                assert front["checked"] == expected_checked
                assert front["syntax_misses"] == edits
                assert front["syntax_hits"] + edits == EXPECTED_SYNTAX_TOTAL[copies]
                assert stages["lowering"]["lowered"] == row["cache"]["compiled"] == edits
                misses = stages["frontend_misses"]
                lookup = named_counts(misses["lookup"], names)
                retention = named_counts(misses["retention"], names)
                assert sum(lookup.values()) == front["checked"], "For these samples, lookup misses exactly match fresh-body counts"
                assert lookup["context_changed"] == 0
                samples.append({"sample": row["sample"], "frontend": front, "lookup": lookup, "retention": retention, "relocation_failure_kinds": misses["relocation"], "native_objects_compiled": row["cache"]["compiled"], "bodies_lowered": stages["lowering"]["lowered"]})
            output["phases"][phase] = {"deliberately_edited_bodies": edits, "checked": expected_checked, "checked_beyond_deliberate_edits": expected_checked - edits, "fresh_syntax_units": edits, "syntax_replays": EXPECTED_SYNTAX_TOTAL[copies] - edits, "samples": samples}
        helper = output["phases"]["helper_edit"]
        retain = helper["samples"][0]["retention"]
        ordinary_unretained = sum(retain.values())
        assert ordinary_unretained == 35 * copies
        assert retain["ambiguous_record"] == 24 * copies
        assert retain["generic_specialization"] == 8 * copies
        assert retain["interned_record"] == 3 * copies
        assert helper["checked"] == 19 * copies + ordinary_unretained + 1
        for row in helper["samples"]:
            assert row["lookup"]["not_ordinary"] == 19 * copies
            assert row["retention"] == retain
            assert row["lookup"]["relocation_failed"] == 0
            assert row["lookup"]["no_entry"] + row["lookup"]["region_length_changed"] == ordinary_unretained + 1
        output["helper_decomposition"] = {
            "deliberately_changed_helper": 1,
            "nonordinary_instance_lookups_ending_in_fresh_checks": 19 * copies,
            "ordinary_bodies_unretained_ambiguous_record": 24 * copies,
            "ordinary_bodies_unretained_specialization_dependencies": 8 * copies,
            "ordinary_bodies_unretained_interned_records": 3 * copies,
            "repeat_checks_beyond_changed_helper": 54 * copies,
            "total_checked": helper["checked"],
            "dependency_digest_changed_lookup_misses": 0,
            "attribution_limit": "Decomposition is aggregate arithmetic matching stable retention totals; report lacks per-body identity joins and specialization miss detail. Zero context_changed lookups does not mean all semantic dependencies/global validation can be skipped.",
        }
        result["sizes"][str(copies)] = output
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, default=DEFAULT_INPUT)
    parser.add_argument("--output", type=Path, default=HERE / "frontend-audit.json")
    args = parser.parse_args()
    args.output.write_text(json.dumps(audit(args.input.resolve()), indent=2) + "\n")
    print(args.output)


if __name__ == "__main__":
    main()
