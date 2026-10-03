#!/usr/bin/env python3
"""Fresh AST84 public tests on selected d14/99ad; separate from native probes."""
from datetime import datetime,timezone
import hashlib,json,os,re,subprocess
from pathlib import Path

OWN = Path(__file__).resolve().parents[2]
WORK = OWN/'.tmp-lox-ast-selected-public-20261003'
ROOT = Path('/home/epentland/ai/canopy/mylang-worktrees/codex-lox-parity-20261003')
ROUND = ROOT/'.tmp-lox-round3'
SOURCE = ROUND/'ast'
BASE = ROUND/'baseline'
COMPILER = Path('/home/epentland/ai/canopy/mylang-worktrees/codex-lox-parity-lowering-20261003/.tmp-lox-lowering/cfg-fix-release/bin/mylang')
NATIVE = Path('/home/epentland/ai/canopy/mylang-worktrees/codex-lox-parity-vm-20261003/.tmp-lox-ast-carrier-20261003/validation-selected-corrected/completed.json')
sha = lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
read = lambda p:json.loads(Path(p).read_text())
files = lambda p:{str(f.relative_to(p)):sha(f) for f in sorted(p.rglob('*')) if f.is_file()}
write = lambda n,v:(WORK/n).write_text(json.dumps(v,indent=2)+'\n')
assert WORK.is_dir() and not (WORK/'preflight.json').exists()
assert not set(os.sched_getaffinity(0)) & {2,3,10,11}
env = {k:v for k,v in os.environ.items() if not k.startswith('MYLANG_') and k != 'LD_PRELOAD'}
env['TMPDIR'] = str(WORK/'tmp')
assert Path(env['TMPDIR']).is_dir()

def snapshot():
    paths = {COMPILER,COMPILER.with_name('qbe'),Path(__file__).resolve(),OWN/'scripts/build-slot.sh',NATIVE,
             ROUND/'ast-build.json',ROUND/'combined.json',ROOT/'.tmp-lox-parity/inputs/pinned-SPEC.md'}
    # Freeze previously qualified native artifacts for identity continuity only.
    native = read(NATIVE)
    assert native['verified_after'] and native['before']['candidate37'] == native['after']['candidate37']
    assert native['before']['artifacts_sha256'] == native['after']['artifacts_sha256']
    paths.update(Path(p) for p in native['after']['artifacts_sha256'])
    for b in ['llvm','qbe']:
        binary = ROUND/('bin/ast-'+b)
        manifest = Path(str(binary)+'.qbe-manifest.json')
        paths.update([binary,manifest,Path(str(binary)+'.qbe-receipt'),Path(read(manifest)['runtime_object'])])
    return {'source37':files(SOURCE),'baseline37':files(BASE),'artifacts_sha256':{str(p):sha(p) for p in sorted(paths)}}

before = snapshot()
assert len(before['source37']) == len(before['baseline37']) == 37
assert sorted(k for k in before['source37'] if before['source37'][k] != before['baseline37'][k]) == ['interpreter.my']
assert before['source37'] == read(NATIVE)['before']['candidate37']
composition = read(ROUND/'combined.json')
assert before['source37'] == composition['input_hashes']['tree']
build = read(ROUND/'ast-build.json')
assert build['source_sha256'] == {k:v for k,v in before['source37'].items() if k.endswith('.my')}
assert sha(COMPILER) == build['compiler_sha256'] == 'd14a704083bcc5f5174932a751f7d9dda73100dbd62403626b42b52436cad040'
assert sha(COMPILER.with_name('qbe')) == '99ad919d70ad582dee6202b045bd53e1ab18fec356de98849610f49983756d63'
for b,h in [('llvm','180575c3fc2e46a16ed8dd290e289963a87603b5a7c0cf8bb0e03ba7cf794361'),('qbe','246f21781fd58c7141dbe0992101c842e62d732d9ce47e209d55821d02b11b25')]:
    assert sha(ROUND/('bin/ast-'+b)) == h
names = sorted(path.stem+'::'+m.group(1) for path in SOURCE.glob('*.my') for m in re.finditer(r'^public def (test_\w+)\(',path.read_text(),re.M))
assert len(names) == len(set(names)) == 84
before.update(started_utc=datetime.now(timezone.utc).isoformat(),affinity=sorted(os.sched_getaffinity(0)),public_names=names)
write('preflight.json',before)
receipt = {'scope':'Fresh accounted AST84 public tests on selected d14/99ad; no native probe repetition.',
           'before':before,'runs':[],'verified_after':False}
write('qualification.json',receipt)
for backend in ['llvm','qbe']:
    for runtime in ['rc','gc-stress']:
        key = backend+'-'+runtime
        cache = WORK/('cache-'+key)
        assert not cache.exists()
        argv = [str(OWN/'scripts/build-slot.sh'),'build',str(COMPILER),'test',str(SOURCE),'--json',
                '--jobs','2','--max-steps','1000000000','--timeout-ms','120000','--cache-dir',str(cache)]
        argv += ['--release'] if backend == 'llvm' else ['--mode','ReleaseFast']
        argv += ['--rc-runtime'] if runtime == 'rc' else ['--gc-stress']
        stdout,stderr = WORK/(key+'.json'),WORK/(key+'.stderr')
        print('Fresh selected AST84 public',key,flush=True)
        with stdout.open('wb') as out,stderr.open('wb') as err:
            result = subprocess.run(argv,cwd=OWN,env=env,stdout=out,stderr=err,timeout=900)
        row = {'key':key,'argv':argv,'cwd':str(OWN),'environment':{'TMPDIR':env['TMPDIR']},'status':result.returncode,
               'stdout':str(stdout),'stdout_sha256':sha(stdout),'stderr':str(stderr),'stderr_sha256':sha(stderr)}
        receipt['runs'].append(row)
        write('qualification.json',receipt)
        assert result.returncode == 0,(key,result.returncode)
        report = read(stdout)
        counts = {k:report[k] for k in ['passed','failed','skipped','cached','executed','dropped','unloaded','programs']}
        assert counts == {'passed':84,'failed':0,'skipped':0,'cached':0,'executed':84,'dropped':0,'unloaded':0,'programs':10}
        assert sorted(x['name'] for x in report['tests']) == names
        assert all(x['status'] == 'passed' and x['actual'] is True and x['provider'] == '' for x in report['tests'])
        row.update(counts=counts,provider_identity='',fresh_cache=True)
        row['native_test_artifacts_sha256'] = {str(p):sha(p) for p in sorted(cache.rglob('*')) if p.is_file() and (p.suffix in ['.a','.so','.o'] or p.name.endswith('.qbe-manifest.json') or p.name.endswith('.qbe-receipt'))}
        write('qualification.json',receipt)
after = snapshot()
assert after['source37'] == before['source37'] and after['baseline37'] == before['baseline37']
assert after['artifacts_sha256'] == before['artifacts_sha256']
for row in receipt['runs']:
    for p,h in row['native_test_artifacts_sha256'].items(): assert sha(p) == h
receipt.update(after=after,verified_after=True,finished_utc=datetime.now(timezone.utc).isoformat(),fresh_public_passes=336,
               provider_scope='All four directory arms omit --cases and every reported provider identity is empty; fixtures are preserved structurally.')
write('qualification.json',receipt)
print('336 fresh selected d14 AST84 public passes, source37/tool/native identities unchanged; provider-free directory execution.',flush=True)
