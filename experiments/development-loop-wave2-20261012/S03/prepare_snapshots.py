#!/usr/bin/env python3
"""Create private immutable recipe-replay inputs from authenticated Git objects."""
import hashlib
import io
import json
from pathlib import Path
import re
import subprocess
import tarfile

ROOT = Path(__file__).resolve().parents[3]
OUT = Path(__file__).resolve().parent
SCRATCH = ROOT / '.tmp/s03-paired'
SOURCES = {'C0': 'fbfcaa7a923186a8e773c3760f81c10aa345a432', 'B0': 'c1857310e0bf623545380c8de24515f1b9970021'}
SCRATCH.mkdir(parents=True, exist_ok=True)
guardian = ROOT.parent / 'guardian-zig'
assert guardian.is_dir()
link = SCRATCH / 'guardian-zig'
if not link.exists():
    link.symlink_to(guardian, target_is_directory=True)
record = {'schema': 's03-paired-source-preparation-v1', 'sources': {}, 'replay_recipe_sha256': hashlib.sha256((OUT / 'replay_build.zig').read_bytes()).hexdigest()}
for label, revision in SOURCES.items():
    destination = SCRATCH / label
    assert not destination.exists(), destination
    harness = subprocess.check_output(['git', 'show', revision + ':test/golden_parity.zig'], cwd=ROOT).decode()
    fixtures = re.findall(r'\.name = "[^"]+", \.relative_path = "([^"]+)"', harness)
    paths = ['src', 'docs', 'build_identity.zig', 'test/golden_parity.zig', 'tests/goldens', *fixtures]
    archive = subprocess.check_output(['git', 'archive', revision, '--', *paths], cwd=ROOT)
    destination.mkdir()
    with tarfile.open(fileobj=io.BytesIO(archive)) as contents:
        contents.extractall(destination, filter='data')
    (destination / 'build.zig').write_bytes((OUT / 'replay_build.zig').read_bytes())
    (destination / 'build.zig.zon').write_text('.{ .name = .mylang, .version = "0.1.0", .fingerprint = 0xe12764e71b51fef7, .dependencies = .{ .guardian = .{ .path = "../guardian-zig" } }, .paths = .{""} }\n')
    files = [{'path': str(path.relative_to(destination)), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest(), 'bytes': path.stat().st_size} for path in sorted(destination.rglob('*')) if path.is_file()]
    record['sources'][label] = {'revision': revision, 'snapshot': str(destination), 'archive_sha256': hashlib.sha256(archive).hexdigest(), 'files': files}
(OUT / 'source-preparation.json').write_text(json.dumps(record, indent=2) + '\n')
print(json.dumps({k: {'revision': v['revision'], 'files': len(v['files'])} for k, v in record['sources'].items()}))
