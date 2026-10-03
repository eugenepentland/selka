#!/usr/bin/env python3
"""Build frozen policy candidate guests with private caches and receipts."""
from pathlib import Path
import hashlib, json, os, subprocess

lane = Path(__file__).resolve().parents[2]
work = lane / '.tmp-lox-native-policy-20261003'
root = Path('/home/epentland/ai/canopy/mylang-worktrees/codex-lox-parity-20261003')
source = root / '.tmp-lox-round3/ast'
compiler = work / 'compiler-final-v2/bin/mylang'
qbe = Path('/home/epentland/ai/canopy/mylang-worktrees/codex-lox-parity-lowering-20261003/.tmp-lox-lowering/cfg-fix-release/bin/qbe')
sha = lambda p: hashlib.sha256(Path(p).read_bytes()).hexdigest()
files = lambda p: {str(f.relative_to(p)): sha(f) for f in sorted(p.rglob('*')) if f.is_file()}
frozen = json.loads((work / 'frozen-source-v2.json').read_text())
assert files(source) == frozen['source37']
assert all(sha(lane / p) == h for p, h in frozen['core'].items())
assert sha(qbe) == '99ad919d70ad582dee6202b045bd53e1ab18fec356de98849610f49983756d63'
from prefixes_v2 import snapshot
prefix_before = snapshot()
destination = work / 'builds-v2.json'
assert not destination.exists()
report = dict(source=str(source), source37=frozen['source37'], compiler=str(compiler),
              compiler_sha256=sha(compiler), qbe=str(qbe), qbe_sha256=sha(qbe), runs=[], verified_after=False)
environment = {k: v for k, v in os.environ.items() if not k.startswith('MYLANG_') and k != 'LD_PRELOAD'}
environment.update(TMPDIR=str(work / 'tmp'), ZIG_GLOBAL_CACHE_DIR=str(work / 'global-cache'))
for runtime in ['rc', 'gc']:
    for backend in ['qbe', 'llvm']:
        name = 'native-policy-v2-'  + runtime + '-' + backend
        binary, cache = work / name, work / ('cache-' + name)
        argv = [str(lane / 'scripts/build-slot.sh'), 'build', str(compiler), 'build', str(source / 'main.my'),
                '--project', '--backend', backend, '--' + runtime + '-runtime', '--keep-symbols',
                '--cache-dir', str(cache), '-o', str(binary)]
        if backend == 'llvm':
            argv += ['--llvm-opt', '3', '--lto']
        else:
            argv += ['--qbe', str(qbe)]
        print('Building', name, flush=True)
        with (work / (name + '.stdout')).open('xb') as out, (work / (name + '.stderr')).open('xb') as err:
            result = subprocess.run(argv, cwd=lane, env=environment, stdout=out, stderr=err)
        row = dict(argv=argv, cwd=str(lane), environment={k: environment[k] for k in ['TMPDIR', 'ZIG_GLOBAL_CACHE_DIR']},
                   runtime=runtime, backend=backend, status=result.returncode, cache=str(cache), binary=str(binary))
        if result.returncode == 0:
            manifest = Path(str(binary) + '.qbe-manifest.json')
            receipt = Path(str(binary) + '.qbe-receipt')
            runtime_object = Path(json.loads(manifest.read_text())['runtime_object'])
            row['artifacts_sha256'] = {str(p): sha(p) for p in [binary, manifest, receipt, runtime_object]}
        report['runs'].append(row)
        destination.write_text(json.dumps(report, indent=2) + '\n')
        assert result.returncode == 0, work / (name + '.stderr')
assert files(source) == frozen['source37'] and all(sha(lane / p) == h for p, h in frozen['core'].items())
assert sha(compiler) == report['compiler_sha256']
assert sha(qbe) == report['qbe_sha256']
report['immutable_prefixes_before'] = prefix_before
report['immutable_prefixes_after'] = snapshot()
assert prefix_before == report['immutable_prefixes_after']
report['verified_after'] = True
destination.write_text(json.dumps(report, indent=2) + '\n')
print('Frozen four RC/GC guests built; no performance measurements', flush=True)
