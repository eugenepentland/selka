#!/usr/bin/env python3
"""Build frozen inlined readonly-equality source with selected d14; no timing."""
from pathlib import Path
import hashlib, json, os, subprocess
from datetime import datetime, timezone

lane = Path(__file__).resolve().parents[2]
work = lane / '.tmp-lox-vm-stack-read-v2-20261003'
source = work / 'inline-qualified'
compiler = Path('/home/epentland/ai/canopy/mylang-worktrees/codex-lox-parity-lowering-20261003/.tmp-lox-lowering/cfg-fix-release/bin/mylang')
sha = lambda p: hashlib.sha256(Path(p).read_bytes()).hexdigest()
sources = lambda: {str(f.relative_to(source)): sha(f) for f in sorted(source.rglob('*')) if f.is_file()}
assert sha(compiler) == 'd14a704083bcc5f5174932a751f7d9dda73100dbd62403626b42b52436cad040'
assert sha(compiler.with_name('qbe')) == '99ad919d70ad582dee6202b045bd53e1ab18fec356de98849610f49983756d63'
env = dict(os.environ, TMPDIR=str(work/'tmp'))
receipt = {'compiler': str(compiler), 'compiler_sha256': sha(compiler), 'qbe': str(compiler.with_name('qbe')),
           'qbe_sha256': sha(compiler.with_name('qbe')), 'source': str(source), 'source_sha256': sources(),
           'runs': [], 'verified_after': False, 'scope': 'Distinct V2 four-flavor builds; explicit RC/GC runtime flags; no performance runs.'}
dest = work/'builds.json'
assert not dest.exists()
for backend in ('llvm', 'qbe'):
    for runtime in ('rc', 'gc'):
        key = 'qualified-inline-'+backend+'-'+runtime
        binary = work/key
        argv = [str(lane/'scripts/build-slot.sh'), 'build', str(compiler), 'build', str(source/'main.my'), '--project', '--backend', backend]
        if backend == 'llvm': argv += ['--llvm-opt', '3', '--lto']
        argv += ['--rc-runtime'] if runtime == 'rc' else ['--gc-runtime']
        argv += ['--keep-symbols', '--cache-dir', str(work/('cache-'+key)), '-o', str(binary)]
        stdout, stderr = work/(key+'.stdout'), work/(key+'.stderr')
        print('Building', key, flush=True)
        row = {'argv': argv, 'runtime': runtime, 'cwd': str(lane), 'environment': {'TMPDIR': env['TMPDIR']}, 'started': datetime.now(timezone.utc).isoformat()}
        with stdout.open('xb') as out, stderr.open('xb') as err:
            run = subprocess.run(argv, cwd=lane, env=env, stdout=out, stderr=err, timeout=900)
        row.update(status=run.returncode, stdout=str(stdout), stdout_sha256=sha(stdout), stderr=str(stderr), stderr_sha256=sha(stderr), finished=datetime.now(timezone.utc).isoformat())
        if run.returncode == 0:
            manifest = binary.with_name(binary.name+'.qbe-manifest.json')
            sidecar = binary.with_name(binary.name+'.qbe-receipt')
            m = json.loads(manifest.read_text())
            row.update(binary=str(binary), binary_sha256=sha(binary), manifest=str(manifest), manifest_sha256=sha(manifest), receipt=str(sidecar), receipt_sha256=sha(sidecar),
                       codegen={k: m[k] for k in ('abi', 'backend', 'optimization', 'lto', 'thin_lto')}, runtime_object=m['runtime_object'], runtime_object_sha256=sha(m['runtime_object']))
        receipt['runs'].append(row)
        dest.write_text(json.dumps(receipt, indent=2)+'\n')
        assert run.returncode == 0, stderr.read_text()
assert sources() == receipt['source_sha256'] and len(receipt['source_sha256']) == 37
assert sha(compiler) == receipt['compiler_sha256'] and sha(compiler.with_name('qbe')) == receipt['qbe_sha256']
receipt['verified_after'] = True
dest.write_text(json.dumps(receipt, indent=2)+'\n')
