#!/usr/bin/env python3
"""Fresh native qualification on both backends, RC and GC stress; no benchmarks."""
from pathlib import Path
import argparse, hashlib, json, os, re, subprocess

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('label')
a = p.parse_args()
lane = Path(__file__).resolve().parents[2]
work = lane / '.tmp-lox-vm-bytecode-20261003'
source = work / (a.label + '-qualified')
compiler = Path('/home/epentland/ai/canopy/mylang-worktrees/codex-lox-parity-lowering-20261003/.tmp-lox-lowering/cfg-fix-release/bin/mylang')
sha = lambda path: hashlib.sha256(Path(path).read_bytes()).hexdigest()
env = dict(os.environ, TMPDIR=str(work / 'tmp'))
receipt = {'compiler': str(compiler), 'compiler_sha256': sha(compiler),
           'qbe_sha256': sha(compiler.with_name('qbe')), 'source': str(source),
           'source_sha256': {str(f.relative_to(source)): sha(f) for f in source.rglob('*') if f.is_file()},
           'runs': [], 'verified_after': False}
output = work / (a.label + '-qualification.json')
assert not output.exists()
for backend in ['llvm', 'qbe']:
    for runtime in ['rc', 'gc-stress']:
        key = a.label + '-qualified-' + backend + '-' + runtime
        cache = work / ('cache-' + key)
        argv = [str(lane/'scripts/build-slot.sh'), 'build', str(compiler), 'test', str(source),
                '--jobs', '2', '--max-steps', '1000000000', '--timeout-ms', '120000',
                '--cache-dir', str(cache)]
        argv += ['--release'] if backend == 'llvm' else ['--mode', 'ReleaseFast']
        argv += ['--rc-runtime'] if runtime == 'rc' else ['--gc-stress']
        log = work / (key + '.log')
        print('Testing', key, flush=True)
        with log.open('wb') as out:
            run = subprocess.run(argv, cwd=lane, env=env, stdout=out, stderr=subprocess.STDOUT, timeout=900)
        row = {'argv': argv, 'cwd': str(lane), 'TMPDIR': env['TMPDIR'], 'status': run.returncode,
               'log': str(log), 'log_sha256': sha(log), 'summaries': re.findall(r'^\d+ passed.*$', log.read_text(), re.M)}
        receipt['runs'].append(row)
        output.write_text(json.dumps(receipt, indent=2)+'\n')
        assert run.returncode == 0, log
assert receipt['source_sha256'] == {str(f.relative_to(source)): sha(f) for f in source.rglob('*') if f.is_file()}
assert sha(compiler) == receipt['compiler_sha256']
assert sha(compiler.with_name('qbe')) == receipt['qbe_sha256']
receipt['verified_after'] = True
output.write_text(json.dumps(receipt, indent=2)+'\n')
print('Verified all four fresh qualification arms', flush=True)
