"""Coordinator-only equivalent repair mutations; source baselines remain untouched."""
from pathlib import Path
from .storage import digest, inventory, snapshot, source_files, verify_snapshot


RECIPES = {
    ('planner-input-boundary', 'python'): ('planner.py', 'if len(payload) > MAX_INPUT_BYTES:', 'if len(payload) >= MAX_INPUT_BYTES:'),
    ('planner-input-boundary', 'zig'): ('src/main.zig', 'input.len > max_input)', 'input.len >= max_input)'),
    ('planner-input-boundary', 'my'): ('main.my', 'std_text::read(heap, 1048576)', 'std_text::read(heap, 1048575)'),
    ('eda-clearance-boundary', 'python'): ('inspector.py', 'gap_x * gap_x + gap_y * gap_y < clearance * clearance:', 'gap_x * gap_x + gap_y * gap_y <= clearance * clearance:'),
    ('eda-clearance-boundary', 'zig'): ('src/main.zig', 'gx * gx + gy * gy < @as(i128, clearance) * clearance)', 'gx * gx + gy * gy <= @as(i128, clearance) * clearance)'),
    ('eda-clearance-boundary', 'my'): ('main.my', 'gx * gx + gy * gy < clearance * clearance ||', 'gx * gx + gy * gy <= clearance * clearance ||'),
}


def create(source, destination, receipt, *, task, language):
    """Require a reviewed source identity and one exact mutation site, fail closed.

Returned mutation details belong in private cohort records, never candidate files.
This records construction only; executable equivalence checks are separate.
"""
    if (task, language) not in RECIPES:
        raise ValueError('unknown seeded regression')
    verify_snapshot(source, receipt)
    path, before, after = RECIPES[task, language]
    original = snapshot(source, destination)
    if original != receipt:
        raise ValueError('baseline changed during mutation capture')
    target = Path(destination) / path
    data = target.read_bytes()
    if data.count(before.encode()) != 1:
        raise ValueError('seed requires exactly one matching source site')
    target.write_bytes(data.replace(before.encode(), after.encode()))
    files = inventory(source_files(destination))
    seeded = {'files': files, 'sha256': digest(files)}
    return {'version': 'seeded-regression-v1', 'task': task, 'language': language,
            'original': original, 'seeded': seeded,
            'mutation': {'path': path, 'before': before, 'after': after},
            'comparative_claim': False}
