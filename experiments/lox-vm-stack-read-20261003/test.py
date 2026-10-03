#!/usr/bin/env python3
"""Fresh accounted public qualification; these are correctness tests, not perf."""
from pathlib import Path
import hashlib, json, os, re, subprocess

lane = Path(__file__).resolve().parents[2]
work = lane / '.tmp-lox-vm-stack-read-20261003'
source = work/'equal-qualified'
compiler = Path('/home/epentland/ai/canopy/mylang-worktrees/codex-lox-parity-lowering-20261003/.tmp-lox-lowering/cfg-fix-release/bin/mylang')
sha = lambda p: hashlib.sha256(Path(p).read_bytes()).hexdigest()
sources = lambda: {str(f.relative_to(source)): sha(f) for f in sorted(source.rglob('*')) if f.is_file()}
env = dict(os.environ, TMPDIR=str(work/'tmp'))
receipt = {'compiler': str(compiler), 'compiler_sha256': sha(compiler), 'qbe_sha256': sha(compiler.with_name('qbe')),
           'source': str(source), 'source_sha256': sources(), 'runs': [], 'verified_after': False}
assert receipt['compiler_sha256'] == 'd14a704083bcc5f5174932a751f7d9dda73100dbd62403626b42b52436cad040'
dest = work/'public-qualification.json'
assert not dest.exists()
for backend in ('llvm', 'qbe'):
    for runtime in ('rc', 'gc-stress'):
        key = 'public-'+backend+'-'+runtime
        argv = [str(lane/'scripts/build-slot.sh'), 'build', str(compiler), 'test', str(source), '--jobs', '2', '--max-steps', '1000000000', '--timeout-ms', '120000', '--cache-dir', str(work/('cache-'+key))]
        argv += ['--release'] if backend == 'llvm' else ['--mode', 'ReleaseFast']
        argv += ['--rc-runtime'] if runtime == 'rc' else ['--gc-stress']
        log = work/(key+'.log')
        print('Testing', key, flush=True)
        with log.open('xb') as out:
            run = subprocess.run(argv, cwd=lane, env=env, stdout=out, stderr=subprocess.STDOUT, timeout=900)
        row = {'argv': argv, 'cwd': str(lane), 'environment': {'TMPDIR': env['TMPDIR']}, 'status': run.returncode, 'log': str(log), 'log_sha256': sha(log), 'summaries': re.findall(r'^\d+ passed.*$', log.read_text(), re.M)}
        receipt['runs'].append(row)
        dest.write_text(json.dumps(receipt, indent=2)+'\n')
        assert run.returncode == 0, log
assert sources() == receipt['source_sha256']
assert sha(compiler) == receipt['compiler_sha256'] and sha(compiler.with_name('qbe')) == receipt['qbe_sha256']
receipt['verified_after'] = True
dest.write_text(json.dumps(receipt, indent=2)+'\n')
