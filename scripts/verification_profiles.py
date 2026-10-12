#!/usr/bin/env python3
"""Coverage-preserving profiles for the existing verification coordinator.

The caller validates the exported inventory and resolves receipts using its live
dependency model. This module ranks that work; it cannot authorize evidence.
"""
import math
import hashlib
import marshal
import re
import sys

VERSION = "verification-profile-v2"
PROFILES = ("quick", "complete", "long-qualification")
MAX_ACTIONS = 1024
_KEY = re.compile(r"[0-9a-f]{64}")


def validate_request(profile, quick_actions):
    """Reject unsupported profile controls before preparation or invalidation."""
    if profile not in PROFILES or type(quick_actions) is not int or not 1 <= quick_actions <= MAX_ACTIONS:
        raise ValueError("invalid verification profile or quick action bound")


def _actions(plan, rows):
    groups = plan.get("groups")
    if type(groups) is not list or not 1 <= len(groups) <= MAX_ACTIONS:
        raise ValueError("profile requires a bounded current action inventory")
    ids = [group.get("id") for group in groups if type(group) is dict]
    if len(ids) != len(groups) or any(type(name) is not str or not name for name in ids) or len(set(ids)) != len(ids):
        raise ValueError("invalid profile inventory identities")
    if type(rows) is not list or len(rows) != len(ids):
        raise ValueError("profile requires every current action decision")
    decisions = {}
    for row in rows:
        if (type(row) is not dict or row.get("id") not in ids or row["id"] in decisions
                or row.get("state") not in ("reused", "execute", "fresh", "executed", "skipped")
                or type(row.get("action_key")) is not str or _KEY.fullmatch(row["action_key"]) is None):
            raise ValueError("invalid profile action decision")
        decisions[row["id"]] = row
    return ids, decisions


def schedule(plan, rows, profile="complete", *, quick_actions=3, costs=None):
    """Select existing pending actions; heuristic ranking never removes obligations."""
    validate_request(profile, quick_actions)
    ids, decisions = _actions(plan, rows)
    costs = {} if costs is None else costs
    if (type(costs) is not dict or set(costs) - set(ids)
            or any(type(value) not in (int, float) or not math.isfinite(value) or value < 0 for value in costs.values())):
        raise ValueError("invalid report-only profile costs")
    pending = [name for name in ids if decisions[name]["state"] != "reused"]
    changed = [name for name in pending if decisions[name].get("invalidation", {}).get("changes")]
    members = {item["id"]: len(item["steps"]) for item in plan.get("action_metadata", [])}
    if profile == "quick":
        # Miss explanations and observed costs are prioritization hints only.
        # Member count is a visibly heuristic work proxy when costs are unknown.
        pending.sort(key=lambda name: (name not in changed, name not in costs,
                                       costs.get(name, members.get(name, math.inf)), ids.index(name)))
        selected = pending[:quick_actions]
    else:
        selected = pending
    return {"version": VERSION, "profile": profile, "required": ids,
            "selected": selected, "pending": pending,
            "deferred": [name for name in pending if name not in selected],
            "affected_actions": changed, "heuristic": profile == "quick",
            "cost_scope": "report-only action cost; unknown costs use heuristic member count then inventory order"}


def coverage(plan, rows, selected, profile="complete", *, status, inputs_stable,
             qualification_required=(), qualification_results=(), qualification_run=None, qualification_context=None):
    """Account for exact gate coverage; a shared failing gate certifies no selected action.

Reuse rows are already qualified by the caller. Selected work is covered only
after the admitted command and publication guards succeed. Long qualification
uses separately qualified results; timing telemetry is never such a result.
"""
    if profile not in PROFILES or type(status) is not int or type(inputs_stable) is not bool:
        raise ValueError("invalid profile outcome")
    ids, decisions = _actions(plan, rows)
    if (type(selected) is not list or len(selected) != len(set(selected))
            or set(selected) - set(ids) or any(decisions[name]["state"] == "reused" for name in selected)):
        raise ValueError("invalid profile execution coverage")
    required = list(qualification_required)
    if (len(required) > MAX_ACTIONS or any(type(name) is not str or not name for name in required)
            or len(set(required)) != len(required)):
        raise ValueError("invalid qualification inventory")
    if qualification_results:
        raise ValueError("serialized qualification success booleans cannot authorize completion")
    qualified = set()
    if qualification_run is not None:
        from verification_qualification import qualified_names
        qualified = qualified_names(qualification_run, qualification_context, required)
    reused = [name for name in ids if decisions[name]["state"] == "reused" and inputs_stable
              and decisions[name].get("success") is not False]
    executed = [name for name in selected if decisions[name]["state"] != "skipped"
                and decisions[name].get("success") is not False] if status == 0 and inputs_stable else []
    outstanding = [name for name in ids if name not in reused and name not in executed]
    gate_complete = not outstanding and status == 0 and inputs_stable and not plan.get("configuration", {}).get("filtered", False)
    qualification_outstanding = ([name for name in required if name not in qualified]
                                or (["qualification-inventory-unavailable"] if not required else [])) if profile == "long-qualification" else []
    complete = gate_complete and profile != "quick"
    qualified_complete = complete and not qualification_outstanding
    return {"version": VERSION, "profile": profile,
            "status": "failed" if status != 0 or not inputs_stable else "complete" if qualified_complete else "partial",
            "heuristic": profile == "quick", "complete_verification": complete,
            "complete_qualification": qualified_complete and profile == "long-qualification",
            "required": ids, "outstanding": outstanding,
            "qualification_outstanding": qualification_outstanding,
            "filtered_inventory": plan.get("configuration", {}).get("filtered", False),
            "counts": {"required": len(ids), "reused": len(reused), "executed": len(executed),
                       "outstanding": len(outstanding)},
            "inputs_stable": inputs_stable}


LOADED_CODE_SHA256 = hashlib.sha256(marshal.dumps(sys._getframe().f_code)).hexdigest()
