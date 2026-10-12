#!/usr/bin/env python3
"""Build immutable unchanged guests; qualify protocol/oracles, never timing."""
import hashlib, json, os, pathlib, subprocess
ROOT = pathlib.Path(__file__).resolve().parents[3]
HERE = pathlib.Path(__file__).resolve().parent
WORK = ROOT / '.tmp/text-gaps/json-serializer'
COMPILER = WORK / 'install/bin/mylang'
SOURCE = ROOT / 'experiments/micro-ownership-20261012/expanded/migrated/text.my'
BASE = '1994cb76e266080d971be6f41e98fba5707234dd'
BASELINE = '/home/epentland/ai/canopy/mylang-memory-20261012/.tmp/micro-gaps/coordinator/install'
def sha(path):
    return hashlib.sha256(pathlib.Path(path).read_bytes()).hexdigest()
def run(args, log, env):
    with log.open('w') as stream:
        subprocess.run(args, cwd=ROOT, env=env, stdout=stream, stderr=subprocess.STDOUT, check=True)
def main():
    assert sha(SOURCE) == '71f5e74e25f894e779c6248b9f52c144e9d53a8c482c0121e4249374dbe05754'
    env = dict(os.environ, MYLANG_COMPONENT_DIR=str(WORK / 'install/libexec/mylang/components'))
    compiler_hash = sha(COMPILER)
    entries = []
    for kind in ['runtime', 'counted']:
        binary = WORK / ('text-' + kind)
        assert not binary.exists()
        command = [str(COMPILER), 'build', str(SOURCE), '--release', '--experimental-zero-rc',
            '--cache-dir', str(WORK / ('cache-' + kind)), '-o', str(binary), '--link',
            str(ROOT / 'benchmarks/runtime/ports/native_clock.c'), '--emit-llvm', str(WORK / (kind + '.ll'))]
        if kind == 'counted': command.append('--counters')
        run([str(ROOT / 'scripts/build-slot.sh'), 'build', *command], HERE / (kind + '-build.log'), env)
        binary.chmod(0o555)
        run([str(ROOT / 'scripts/build-slot.sh'), 'build', 'python3', '-B',
            str(ROOT / 'experiments/text-gaps-20261012/split/qualify.py'), str(binary),
            str(HERE / (kind + '-qualification'))], HERE / (kind + '-qualification.log'), env)
        q = json.loads((HERE / (kind + '-qualification/qualification.json')).read_text())
        assert q['all_ok'] and len(q['results']) == 50
        if kind == 'counted': assert all(row['counters'] is not None for row in q['results'])
        entries.append(dict(kind=kind, binary=str(binary), sha256=sha(binary), source=str(SOURCE),
            source_sha256=sha(SOURCE), command=command, flags=command[3:], status='ok'))
    assert sha(COMPILER) == compiler_hash
    files = [dict(path=str(p.relative_to(WORK / 'install')), sha256=sha(p), bytes=p.stat().st_size)
        for p in sorted((WORK / 'install').rglob('*')) if p.is_file()]
    receipt = dict(base_commit=BASE, source_commit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),
        source_patch=subprocess.check_output(['git','diff','HEAD','--','src/stdlib/json.my'],cwd=ROOT,text=True),
        library_source=dict(path=str(ROOT / 'src/stdlib/json.my'),sha256=sha(ROOT / 'src/stdlib/json.my')),
        compiler=str(COMPILER), compiler_sha256=compiler_hash, baseline_installation=BASELINE,
        installation=str(WORK / 'install'), installation_files=files, entries=entries,
        qualification='176 native contracts in three RC/five checked modes; 100 independent oracle probes; no timing claim')
    (HERE / 'build-receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
if __name__ == '__main__': main()
