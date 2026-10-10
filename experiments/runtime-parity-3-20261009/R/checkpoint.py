#!/usr/bin/env python3
"""Build and measure named R checkpoint cells inside one admitted build slot."""
import argparse, importlib, json, os, pathlib, subprocess, sys
ROOT = pathlib.Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'experiments/runtime-parity-3-20261009/tools'))
import ce, pstat
p = argparse.ArgumentParser()
p.add_argument('--compiler', type=pathlib.Path, required=True)
p.add_argument('--tag', required=True)
p.add_argument('--programs', required=True)
p.add_argument('--rounds', type=int, default=3)
a = p.parse_args()
assert pathlib.Path(os.readlink('/proc/self/fd/9')).name.startswith('build')
cache = ROOT / '.mylang-cache/rp3/R' / a.tag
cache.mkdir(parents=True, exist_ok=True)
compiler = a.compiler.resolve()
outputs = []
arms = []
for name in a.programs.split(','):
    if name.startswith('row-'):
        source = ce.row_sources()[name.removeprefix('row-')]
        cell = ce.vp3_cells('rows')[name]
        args = [str(cell['size']), str(cell['iterations']), str(ce.row_registry().SEED)]
        links = ['--link', str(ROOT / 'benchmarks/runtime/ports/native_clock.c')]
    else:
        source = ROOT / ('bench/parity/' + ce.PARITY[name] + '.my')
        args, links = [], []
    label = name if name.startswith('row-') else 'parity-' + name
    for kind in ['plain', 'count']:
        binary = cache / (label + '-' + kind)
        command = [str(compiler), 'build', str(source), '-o', str(binary), '--cache-dir', str(cache / 'objects'), '--release', '--emit-llvm', str(cache / (label + '-' + kind + '.ll')), *links]
        if kind == 'count': command.append('--counters')
        env = dict(os.environ, MYLANG_CORE_RUNTIME_CACHE=str(cache / 'runtime'), MYLANG_COUNTERS=str(cache / (label + '-counts.json')))
        built = subprocess.run(command, cwd=ROOT, env=env, capture_output=True)
        if built.returncode: raise RuntimeError(built.stderr.decode())
        ran = subprocess.run([str(binary), *args], cwd=ROOT, env=env, capture_output=True)
        base = ce.CACHE / 'bin/base' / (label + '-plain')
        expected = subprocess.run([str(base), *args], cwd=ROOT, capture_output=True)
        matches = ran.stdout.split()[:1] == expected.stdout.split()[:1] if name.startswith('row-') else ran.stdout == expected.stdout
        assert ran.returncode == expected.returncode == 0 and matches, (label, ran.stdout, expected.stdout, ran.stderr)
        outputs.append({'name': label, 'kind': kind, 'binary_sha256': ce.digest(binary), 'stdout_sha256': ce.digest_bytes(ran.stdout), 'same_output': True})
    arms += [{'program': label, 'arm': arm, 'argv': [str(binary), *args]} for arm, binary in [('base', base), (a.tag, cache / (label + '-plain'))]]
    print('qualified', label, flush=True)
out = ROOT / 'experiments/runtime-parity-3-20261009/R'
(out / (a.tag + '-outputs.json')).write_text(json.dumps(outputs, indent=1))
(cache / 'arms.json').write_text(json.dumps(arms))
subprocess.run([sys.executable, str(ROOT / 'experiments/runtime-parity-3-20261009/tools/pstat.py'), str(cache / 'arms.json'), '--rounds', str(a.rounds), '--out', str(out / (a.tag + '-cpu8.json'))], check=True)
