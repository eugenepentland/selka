#!/usr/bin/env python3
"""Freeze a fresh replay checkout; refuse to replace historical evidence."""
from pathlib import Path
import hashlib, json, shutil, subprocess

lane = Path(__file__).resolve().parents[2]
work = lane / '.tmp-lox-native-policy-20261003'
root = Path('/home/epentland/ai/canopy/mylang-worktrees/codex-lox-parity-20261003')
source = root / '.tmp-lox-round3/ast'
sha = lambda p: hashlib.sha256(Path(p).read_bytes()).hexdigest()
work.mkdir(exist_ok=True)
destination = work / 'frozen-source-v2.json'
assert not destination.exists(), 'Use a fresh isolated checkout/output directory'
paths = [p for p in (lane / 'src').rglob('*') if p.is_file()]
paths += [lane / p for p in ['build.zig', 'build.zig.zon', 'build_qbe_assets.zig',
    'build_test_inputs.zig', 'SPEC.md', 'test/integration.zig',
    'test/native_variant_policy.zig', 'test/fixtures/native-rc/variant-native.c']]
core = {str(p.relative_to(lane)): sha(p) for p in sorted(paths)}
assert len(core) == 878
sources = {str(p.relative_to(source)): sha(p) for p in sorted(source.rglob('*')) if p.is_file()}
assert len(sources) == 37
assert sources == json.loads((root / 'experiments/lox-ast-constant-20261003/sources.json').read_text())['ast']
copy = work / 'frozen-core-v2'
for name in core:
    target = copy / name
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(lane / name, target)
base = '3b33df52044a10cb84b908f8b1641af439e8c729'
changed = []
for name, digest in core.items():
    old = subprocess.run(['git', 'show', base + ':' + name], cwd=lane, capture_output=True)
    if old.returncode or hashlib.sha256(old.stdout).hexdigest() != digest:
        changed.append(name)
descriptor = dict(base=base, core=core, source=str(source), source37=sources,
                  core_copy=str(copy), proof_source=str(copy), changed_from_base=changed,
                  status='Fresh replay corrected V2 complete878; qualification prospective')
destination.write_text(json.dumps(descriptor, indent=2) + '\n')
for name in ['tmp', 'global-cache']:
    (work / name).mkdir(exist_ok=True)
print('Fresh complete878/source37 replay source frozen', sha(destination))
