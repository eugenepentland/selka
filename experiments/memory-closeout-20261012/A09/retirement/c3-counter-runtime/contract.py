"""Strict C3 consumer contract; historical C0 counter parsing is unchanged.

The caller selects this adapter only for the retired checked-owned ABI. Its
zero compatibility fields are not instrumented observations of RC operations.
"""
import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[5]
ABI = "mylang-checked-owned-v1"
LEGACY_KINDS = ("retain", "release", "unique_test")
LEGACY_SLOTS = ("runtime_retains", "runtime_releases", "shared_retains",
                "shared_releases", "share_marks", "share_bytes")


def historical_audit(path):
    source = ROOT / "experiments/zero-rc-20261011/audit.py"
    spec = importlib.util.spec_from_file_location("historical_counter_audit", source)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.audit(path)


def zero(value):
    if type(value) is not int or value != 0:
        raise ValueError("retired RC telemetry must be an explicit integer zero")


def audit(path, *, guest_abi):
    if guest_abi != ABI:
        raise ValueError("C3 counter adapter requires the checked-owned ABI")
    try:
        result = historical_audit(path)
        raw = json.loads(Path(path).read_text())
        for record in (raw["totals"], *raw["functions"]):
            for field in LEGACY_SLOTS:
                zero(record[field])
        for kind in LEGACY_KINDS:
            for field in ("count", "bytes", "extra"):
                zero(raw["kinds"][kind][field])
        if any(site["kind"] in LEGACY_KINDS for site in raw["sites"]):
            raise ValueError("C3 must not emit historical RC counter sites")
    except (KeyError, TypeError) as error:
        raise ValueError("missing or incompatible required counter field") from error
    result.pop("observed_rc_free")
    result["legacy_rc_fields"] = {"runtime": result.pop("runtime_rc"),
                                  "emitted": result.pop("emitted_rc")}
    result.update(guest_abi=guest_abi, rc_compatibility_fields_zero=True,
                  rc_evidence="Historical fields are explicit zeros; no RC event instrumentation remains. Structural retirement proof is required.")
    return result


def qualified(counter, structural):
    """A zero compatibility report alone can never qualify guest RC retirement."""
    return (counter.get("guest_abi") == ABI and counter.get("managed_leak_free") is True
            and counter.get("rc_compatibility_fields_zero") is True
            and structural.get("guest_abi") == ABI and structural.get("passed") is True)
