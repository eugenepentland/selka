#!/usr/bin/env python3
"""Fresh native qualification on both backends, RC and GC stress; no benchmarks."""
from pathlib import Path
import argparse, hashlib, json, os, re, subprocess

lane = Path(__file__).resolve().parents[2]
work = lane / '.tmp-lox-ast-bytecode-20261003'
source = work/'candidate'
compiler = Path('/home/epentland/ai/canopy/mylang-worktrees/codex-lox-parity-lowering-20261003/.tmp-lox-lowering/cfg-fix-release/bin/mylang')
sha = lambda path: hashlib.sha256(Path(path).read_bytes()).hexdigest()
env = {k:v for k,v in os.environ.items() if not k.startswith('MYLANG_') and k != 'LD_PRELOAD'}
env['TMPDIR'] = str(work/'tmp')
assert not set(os.sched_getaffinity(0)) & {2,3,10,11}
receipt = {'compiler': str(compiler), 'compiler_sha256': sha(compiler),
           'qbe_sha256': sha(compiler.with_name('qbe')), 'source': str(source),
           'source_sha256': {str(f.relative_to(source)): sha(f) for f in source.rglob('*') if f.is_file()},
           'runs': [], 'verified_after': False}
output = work / 'public-qualification.json'
assert not output.exists()
for backend in ['llvm', 'qbe']:
    for runtime in ['rc', 'gc-stress']:
        key = 'public-' + backend + '-' + runtime
        cache = work / ('cache-' + key)
        argv = [str(lane/'scripts/build-slot.sh'), 'build', str(compiler), 'test', str(source),
                '--json', '--jobs', '2', '--max-steps', '1000000000', '--timeout-ms', '120000',
                '--cache-dir', str(cache)]
        argv += ['--release'] if backend == 'llvm' else ['--mode', 'ReleaseFast']
        argv += ['--rc-runtime'] if runtime == 'rc' else ['--gc-stress']
        log = work / (key + '.json')
        stderr = work/(key+'.stderr')
        print('Testing', key, flush=True)
        with log.open('wb') as out, stderr.open('wb') as err:
            run = subprocess.run(argv, cwd=lane, env=env, stdout=out, stderr=err, timeout=900)
        row = {'argv': argv, 'cwd': str(lane), 'TMPDIR': env['TMPDIR'], 'status': run.returncode,
               'log': str(log), 'log_sha256': sha(log), 'stderr':str(stderr), 'stderr_sha256':sha(stderr)}
        receipt['runs'].append(row)
        output.write_text(json.dumps(receipt, indent=2)+'\n')
        assert run.returncode == 0, log
        report=json.loads(log.read_text())
        counts={k:report[k] for k in ['passed','failed','skipped','cached','executed','dropped','unloaded','programs']}
        assert counts=={'passed':88,'failed':0,'skipped':0,'cached':0,'executed':88,'dropped':0,'unloaded':0,'programs':10}
        names=json.loads((lane/'experiments/lox-ast-bytecode-20261003/source.json').read_text())['public_names']
        assert sorted(x['name'] for x in report['tests'])==names
        assert all(x['status']=='passed' and x['actual'] is True and x['provider']=='' for x in report['tests'])
        row.update(counts=counts,provider_identity='')
assert receipt['source_sha256'] == {str(f.relative_to(source)): sha(f) for f in source.rglob('*') if f.is_file()}
assert sha(compiler) == receipt['compiler_sha256']
assert sha(compiler.with_name('qbe')) == receipt['qbe_sha256']
receipt['verified_after'] = True
receipt['fresh_public_passes']=352
receipt['provider_scope']='No --cases; all provider identities empty; fixture preservation structural.'
output.write_text(json.dumps(receipt, indent=2)+'\n')
print('Verified all four fresh qualification arms', flush=True)
