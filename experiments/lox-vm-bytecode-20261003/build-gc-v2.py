#!/usr/bin/env python3
"""Build fresh unaccounted native-GC guests without changing prior prototypes."""
from pathlib import Path
import hashlib, json, os, subprocess

lane = Path(__file__).resolve().parents[2]
work = lane / '.tmp-lox-vm-bytecode-20261003/v2-gc'
source = lane / '.tmp-lox-vm-bytecode-20261003/octets-v2'
compiler = Path('/home/epentland/ai/canopy/mylang-worktrees/codex-lox-parity-lowering-20261003/.tmp-lox-lowering/cfg-fix-release/bin/mylang')
sha = lambda p: hashlib.sha256(Path(p).read_bytes()).hexdigest()
files = lambda root: {str(f.relative_to(root)): sha(f) for f in sorted(root.rglob('*')) if f.is_file()}
env = {k: v for k, v in os.environ.items() if not k.startswith('MYLANG_') and k != 'LD_PRELOAD'}
env['TMPDIR'] = str(work/'tmp')
receipt = {'source': str(source), 'source37': files(source), 'compiler': str(compiler),
           'compiler_sha256': sha(compiler), 'qbe_sha256': sha(compiler.with_name('qbe')),
           'runs': [], 'verified_after': False}
assert len(receipt['source37']) == 37
assert receipt['compiler_sha256'] == 'd14a704083bcc5f5174932a751f7d9dda73100dbd62403626b42b52436cad040'
output = work/'gc-builds.json'
assert not output.exists()
for backend in ['llvm', 'qbe']:
    binary = work/('octets-gc-'+backend)
    argv = [str(lane/'scripts/build-slot.sh'), 'build', str(compiler), 'build', str(source/'main.my'),
            '--project', '--backend', backend]
    if backend == 'llvm': argv += ['--llvm-opt', '3', '--lto']
    argv += ['--gc-runtime', '--keep-symbols', '--cache-dir', str(work/('cache-gc-'+backend)), '-o', str(binary)]
    log = work/('build-gc-'+backend+'.log')
    print('Building actual unaccounted GC guest', backend, flush=True)
    with log.open('wb') as out:
        run = subprocess.run(argv, cwd=lane, env=env, stdout=out, stderr=subprocess.STDOUT, timeout=900)
    row = {'argv': argv, 'cwd': str(lane), 'TMPDIR': env['TMPDIR'], 'status': run.returncode,
           'log': str(log), 'log_sha256': sha(log)}
    assert run.returncode == 0, log
    manifest = Path(str(binary)+'.qbe-manifest.json')
    runtime = Path(json.loads(manifest.read_text())['runtime_object'])
    row.update(binary=str(binary), binary_sha256=sha(binary), manifest=str(manifest), manifest_sha256=sha(manifest),
               receipt_sha256=sha(str(binary)+'.qbe-receipt'), runtime_object=str(runtime), runtime_object_sha256=sha(runtime))
    receipt['runs'].append(row)
    output.write_text(json.dumps(receipt, indent=2)+'\n')
assert receipt['source37'] == files(source)
assert receipt['compiler_sha256'] == sha(compiler)
assert receipt['qbe_sha256'] == sha(compiler.with_name('qbe'))
receipt['verified_after'] = True
output.write_text(json.dumps(receipt, indent=2)+'\n')
print('Verified exact GC source/compiler/ELF/runtime identities', flush=True)
