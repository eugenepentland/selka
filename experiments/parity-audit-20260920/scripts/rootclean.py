#!/usr/bin/env python3
"""Regenerate one of this audit's arms with the parallel audit's private-root-record
store removal (experiments/llvm-parity-audit-20260920/build_root_probe.py::root_stores)
applied on top of the arm's own unchecked lowering.

usage: rootclean.py <build-dir> <arm>      e.g. build-ctl whole-o3 | build-pall compact-o3
Writes <build-dir>/maxperf/<arm>-rootclean/000.ll (+ runtime/ symlink) and
<build-dir>/maxperf/<arm>-rootclean.bin linked exactly as maxperf/build.py links it.
"""
import importlib.util, json, os, subprocess, sys
from pathlib import Path
REPO = Path('/home/epentland/ai/canopy/mylang')
BACKEND = REPO / 'experiments/llvm-backend'
sys.path[:0] = [str(BACKEND), str(BACKEND / 'maxperf'), str(REPO / 'experiments/llvm-parity-audit-20260920')]
import qbe_llvm, unchecked
spec = importlib.util.spec_from_file_location('maxperf_build', BACKEND / 'maxperf/build.py')
builder = importlib.util.module_from_spec(spec); spec.loader.exec_module(builder)
spec2 = importlib.util.spec_from_file_location('root_probe', REPO / 'experiments/llvm-parity-audit-20260920/build_root_probe.py')
root_probe = importlib.util.module_from_spec(spec2); spec2.loader.exec_module(root_probe)

S = Path('/tmp/claude-1000/-home-epentland-ai-canopy-mylang/6108061e-40b0-485a-852b-53c35cd1760e/scratchpad/probes')
build_dir, arm = S / sys.argv[1], sys.argv[2]
manifest = json.loads((build_dir / 'manifest.json').read_text())
builds = json.loads((build_dir / 'maxperf/builds.json').read_text())
frozen = build_dir / 'maxperf' / arm
out = build_dir / 'maxperf' / (arm + '-rootclean'); out.mkdir(exist_ok=True)
funcs = sorted(manifest['functions'], key=lambda f: f['symbol'])
signatures = {f['symbol']: qbe_llvm.signature_map(qbe_llvm.parse_unit(f['il'], f['name'])) for f in funcs}
# control: the arm's own lowering must reproduce the arm's IR before we change it
modules = [unchecked.translate_unit(f['il'], unchecked.Options(mode='unchecked', arena_proven=True), signatures, f['name']).ir for f in funcs]
assert builder.merge_modules(modules) == (frozen / '000.ll').read_text(), 'translator drift'
unchecked._strip_arena_roots = root_probe.root_stores
modules, removed = [], 0
for f in funcs:
    r = unchecked.translate_unit(f['il'], unchecked.Options(mode='unchecked', arena_proven=True), signatures, f['name'])
    modules.append(r.ir); removed += r.inventory.removed.get('private_root_record_store', 0)
ir = builder.merge_modules(modules)
(out / '000.ll').write_text(ir)
rt = out / 'runtime'
if not rt.exists(): rt.symlink_to(frozen / 'runtime')
for name in ('runtime.a', 'unchecked_runtime.o'):
    if not (out / name).exists(): (out / name).symlink_to(frozen / name)
obj = out / '000.o'
builder.run(['zig', 'cc', '-c', '-O3', '-fPIC', '-g0', out / '000.ll', '-o', obj])
binary = build_dir / 'maxperf' / (arm + '-rootclean.bin')
builder.run(['cc', '-O2', '-fPIC', '-no-pie', obj, frozen / 'unchecked_runtime.o', *builds['common'],
             frozen / 'runtime.a', *builds['arms'][arm]['wrappers'], '-lm', '-Wl,--gc-sections', '-o', binary])
print(f'{sys.argv[1]} {arm}: removed {removed} private root-record stores -> {binary}')
