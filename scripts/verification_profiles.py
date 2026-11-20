#!/usr/bin/env python3
"""Coverage-preserving profiles for the existing verification coordinator.

`proofs` selects what `complete` selects and certifies the same coverage; after the gate passes the coordinator also runs
the `ownership-proof` driver with the Lean checker's size cap lifted (`verify_cache.run_proof_profile`), so a request keyed
and cached exactly as `complete` is, with one extra step the complete profile leaves out.

The caller validates the exported inventory and resolves receipts using its live
dependency model. This module ranks that work; it cannot authorize evidence.
"""
import math
import hashlib
import verification_code_identity as code_identity
import re
import sys

VERSION = "verification-profile-v3"
QUALIFICATION_GROUPS = frozenset(("juice", "juice-runtime"))
PREPARATION_GROUPS = frozenset(("input-discovery", "environment-discovery", "component-preparation"))
PROFILES = ("quick", "complete", "proofs", "long-qualification")
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
                or row.get("state") not in ("reused", "execute", "fresh", "executed", "skipped", "prepared", "owed")
                or type(row.get("action_key")) is not str or _KEY.fullmatch(row["action_key"]) is None):
            raise ValueError("invalid profile action decision")
        if row["state"] == "prepared" and row["id"] not in PREPARATION_GROUPS:
            raise ValueError("unknown preparation authority")
        if row["state"] == "owed" and row["id"] not in QUALIFICATION_GROUPS:
            raise ValueError("unknown qualification obligation")
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
    pending = [name for name in ids if decisions[name]["state"] not in ("reused", "prepared")
               and name not in QUALIFICATION_GROUPS]
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
            "qualification_owed": [name for name in ids if name in QUALIFICATION_GROUPS],
            "prepared": [name for name in ids if decisions[name]["state"] == "prepared"],
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
            or set(selected) - set(ids) or any(decisions[name]["state"] in ("reused", "prepared", "owed") for name in selected)):
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
    prepared = [name for name in ids if decisions[name]["state"] == "prepared" and inputs_stable
                and decisions[name].get("success") is not False]
    migrated = [name for name in ids if name in QUALIFICATION_GROUPS]
    outstanding = [name for name in ids if name not in reused and name not in executed
                   and name not in prepared and name not in migrated]
    # A build without `-Dproofs=true` turns the four Lean proof actions into steps that print "skipped" and exit 0 (GH-D10): such
    # a run proved nothing about them, so it never completes the gate, whatever its status says. A plan that does not say fails closed.
    proofs_enabled = plan.get("configuration", {}).get("proofs") is True
    gate_complete = (not outstanding and status == 0 and inputs_stable and proofs_enabled
                     and not plan.get("configuration", {}).get("filtered", False))
    qualification_outstanding = ([name for name in required if name not in qualified]
                                or (["qualification-inventory-unavailable"] if not required else [])) if profile == "long-qualification" else migrated
    complete = gate_complete and profile != "quick"
    qualified_complete = complete and not qualification_outstanding
    verification_complete = complete and profile != "long-qualification"
    return {"version": VERSION, "profile": profile,
            "status": "failed" if status != 0 or not inputs_stable else "complete" if qualified_complete or verification_complete else "partial",
            "heuristic": profile == "quick", "complete_verification": complete,
            "complete_qualification": qualified_complete and profile == "long-qualification",
            "required": ids, "complete_required": [name for name in ids if name not in migrated],
            "prepared": prepared, "qualification_owed": qualification_outstanding, "outstanding": outstanding,
            "qualification_outstanding": qualification_outstanding,
            "filtered_inventory": plan.get("configuration", {}).get("filtered", False),
            "proofs_enabled": proofs_enabled,
            "counts": {"required": len(ids), "reused": len(reused), "executed": len(executed),
                       "outstanding": len(outstanding), "prepared": len(prepared), "qualification_owed": len(qualification_outstanding)},
            "inputs_stable": inputs_stable}


_LOADED_CODE_OBJECT = sys._getframe().f_code
LOADED_CODE_SHA256 = code_identity.loaded_code_sha256(_LOADED_CODE_OBJECT)
