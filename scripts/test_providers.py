"""Deterministic source-provider replacement in isolated guest test snapshots."""
import hashlib
from pathlib import Path

import navigate
from worker_snapshot import sources_snapshot


def snapshot(entry, inventory, replacements, directory):
    """Replace named dependency modules; never alter the application's test entry."""
    if not isinstance(replacements, dict) or not replacements:
        raise ValueError('providers must map dependency .my paths to source strings')
    if entry.name in replacements or any(name not in inventory for name in replacements):
        raise ValueError('providers must replace existing dependencies, never the test entry')
    if any(not isinstance(value, str) for value in replacements.values()):
        raise ValueError('provider replacements must be source strings')
    captured = {}
    for name, expected in inventory.items():
        data = navigate.bounded_read(entry.parent / name, 16 * 1024 * 1024)
        if hashlib.sha256(data).hexdigest() != expected:
            raise ValueError('source changed while capturing test providers')
        captured[name] = replacements[name].encode() if name in replacements else data
    captured, identity = sources_snapshot(captured, entry.name, 16 * 1024 * 1024)
    for name, data in captured.items():
        target = Path(directory) / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
    return Path(directory) / entry.name, identity
