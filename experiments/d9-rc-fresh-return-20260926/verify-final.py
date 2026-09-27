"""The explicit large-result refusal leaves current admitted guest code identical."""
import hashlib, json, os, subprocess
from pathlib import Path
root = Path.cwd()
work = root / '.tmp-mut-argument/return-run'
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
compilers = {arm: root / f'.tmp-mut-argument/return-{arm}/bin/mylang' for arm in ('candidate', 'final')}
receipt = {'compilers': {arm: {'path': str(p), 'sha256': sha(p)} for arm, p in compilers.items()}, 'emissions': [], 'binaries': []}
def save():
    (work / 'final-identities.json').write_text(json.dumps(receipt, indent=2) + '\n')
for source in ('tests/lang/rc_fresh_constructors.my', 'tests/lang/rc_fresh_returns.my', 'experiments/d9-rc-fresh-constructor-20260926/trap.my', 'experiments/d9-rc-fresh-constructor-20260926/arithmetic-trap.my', 'experiments/d9-rc-fresh-return-20260926/stack-floor.my'):
    outputs = []
    for arm, compiler in compilers.items():
        command = [str(root / 'scripts/build-slot.sh'), 'build', str(compiler), 'emit-qbe', source, '--rc-runtime=stats']
        run = subprocess.run(command, text=True, capture_output=True)
        assert run.returncode == 0, run.stderr
        outputs.append(run.stdout)
    assert outputs[0] == outputs[1], source
    receipt['emissions'].append(dict(source=source, sha256=hashlib.sha256(outputs[0].encode()).hexdigest(), byte_identical=True))
    save()
for backend in ('qbe', 'llvm'):
    for mode in ('rc', 'stats'):
        old = work / f'trees-{backend}-after-{mode}'
        binary = work / f'trees-{backend}-final-{mode}'
        command = [str(root / 'scripts/build-slot.sh'), 'build', str(compilers['final']), 'build', str(work / 'binary_trees_n12.my'), '-o', str(binary), '--cache-dir', str(work / 'cache'), '--keep-symbols', '--rc-runtime=stats' if mode == 'stats' else '--rc-runtime']
        if backend == 'llvm':
            command += ['--backend=llvm', '--llvm-opt=3', '--lto']
        run = subprocess.run(command, text=True, capture_output=True, env=dict(os.environ, TMPDIR=str(work)))
        assert run.returncode == 0, run.stderr
        receipt['binaries'].append(dict(command=command, old=str(old), final=str(binary), old_sha256=sha(old), final_sha256=sha(binary)))
        save()
        assert sha(old) == sha(binary), receipt['binaries'][-1]
        print(backend, mode, 'byte-identical', flush=True)
