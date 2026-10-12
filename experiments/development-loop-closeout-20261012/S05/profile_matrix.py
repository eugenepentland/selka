#!/usr/bin/env python3
"""Check profile accounting against an exported real action inventory.

This is deterministic adapter qualification, not execution evidence or latency.
S10 supplies the current candidate inventory after integrating build changes.
"""
import argparse
import copy
import hashlib
import json
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / "scripts"))
import verification_profiles as profiles
import verify_cache


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("inventory", type=Path)
    args = parser.parse_args()
    plan = verify_cache.inventory(args.inventory)
    reports = []
    for scenario in ("cold", "warm", "edit", "semantic-edit"):
        rows = [{"id": group["id"], "state": "reused" if scenario in ("warm", "edit") else "fresh",
                 "action_key": hashlib.sha256(group["id"].encode()).hexdigest(), "invalidation": {"changes": []}}
                for group in plan["groups"]]
        if scenario == "edit":
            rows[0].update(state="execute", invalidation={"changes": [{"kind": "file_content_changed", "name": "fixture"}]})
        if scenario == "semantic-edit":
            for row in rows:
                row["invalidation"]["changes"] = [{"kind": "file_content_changed", "name": "semantic producer"}]
        for profile in profiles.PROFILES:
            scheduled = profiles.schedule(plan, rows, profile)
            assert scheduled == profiles.schedule(copy.deepcopy(plan), copy.deepcopy(rows), profile)
            coverage = profiles.coverage(plan, rows, scheduled["selected"], profile, status=0, inputs_stable=True,
                                         qualification_required=["fuzz", "wall-clock-performance"])
            assert not coverage["complete_verification"] if profile == "quick" else coverage["complete_verification"]
            reports.append({"scenario": scenario, "schedule": scheduled, "coverage": coverage})
    print(json.dumps({"inventory_sha256": hashlib.sha256(args.inventory.read_bytes()).hexdigest(),
                      "scope": "profile adapter accounting; no actual test execution or timing", "reports": reports}, indent=2))


if __name__ == "__main__":
    main()
