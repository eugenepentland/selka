#!/usr/bin/env python3
"""Build one private source variant with the immutable fixed compiler; no timings."""
from pathlib import Path
import argparse, hashlib, json, os, subprocess
from datetime import datetime, timezone

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('label')
a = p.parse_args()
lane = Path(__file__).resolve().parents[2]
work = lane / '.tmp-lox-vm-bytecode-20261003'
source = work / a.label
compiler = Path('/home/epentland/ai/canopy/mylang-worktrees/codex-lox-parity-lowering-20261003/.tmp-lox-lowering/cfg-fix-release/bin/mylang')
sha = lambda path: hashlib.sha256(Path(path).read_bytes()).hexdigest()
env = dict(os.environ, TMPDIR=str(work / 'tmp'))
receipt = {'compiler': str(compiler), 'compiler_sha256': sha(compiler),
           'qbe_sha256': sha(compiler.with_name('qbe')), 'source': str(source),
           'source_sha256': {str(f.relative_to(source)): sha(f) for f in source.rglob('*') if f.is_file()},
           'runs': [], 'verified_after': False}
output = work / (a.label + '-build.json')
assert not output.exists()
for backend in ['llvm', 'qbe', 'emission']:
    argv = [str(lane/'scripts/build-slot.sh'), 'build', str(compiler)]
    cache = work / ('cache-' + a.label + '-' + backend)
    binary = work / (a.label + '-' + backend)
    if backend == 'emission':
        argv += ['emit-project-qbe', str(source/'main.my'), '--rc-runtime',
                 '--drop-step-checks', '--drop-frame-checks', '--cache-dir=' + str(cache)]
    else:
        argv += ['build', str(source/'main.my'), '--project', '--backend', backend]
        if backend == 'llvm': argv += ['--llvm-opt', '3', '--lto']
        argv += ['--rc-runtime', '--keep-symbols', '--cache-dir', str(cache), '-o', str(binary)]
    stdout = work / (a.label+'-'+backend+('.json' if backend == 'emission' else '.stdout'))
    stderr = work / (a.label+'-'+backend+'.stderr')
    print('Building', a.label, backend, flush=True)
    start = datetime.now(timezone.utc).isoformat()
    with stdout.open('wb') as out, stderr.open('wb') as err:
        run = subprocess.run(argv, cwd=lane, env=env, stdout=out, stderr=err, timeout=900)
    row = {'argv': argv, 'cwd': str(lane), 'TMPDIR': env['TMPDIR'], 'started': start,
           'status': run.returncode, 'stdout': str(stdout), 'stdout_sha256': sha(stdout),
           'stderr': str(stderr), 'stderr_sha256': sha(stderr)}
    if backend != 'emission' and run.returncode == 0:
        row.update(binary=str(binary), binary_sha256=sha(binary))
    receipt['runs'].append(row)
    output.write_text(json.dumps(receipt, indent=2)+'\n')
    assert run.returncode == 0, stderr.read_text()
assert receipt['source_sha256'] == {str(f.relative_to(source)): sha(f) for f in source.rglob('*') if f.is_file()}
assert sha(compiler) == receipt['compiler_sha256']
assert sha(compiler.with_name('qbe')) == receipt['qbe_sha256']
receipt['verified_after'] = True
output.write_text(json.dumps(receipt, indent=2)+'\n')
function = next(f for f in json.loads((work/(a.label+'-emission.json')).read_text())['functions'] if f['name'] == 'vm::run')
(work/(a.label+'-vm-run.ssa')).write_text(function['il'])
(work/(a.label+'-run-symbol')).write_text(function['symbol']+'\n')
print('Verified', a.label, function['symbol'], flush=True)
