#!/usr/bin/env python3
"""Recheck and preserve fresh public-test receipts; never executes guests."""
import gzip,hashlib,json,shutil
from pathlib import Path

OWN = Path(__file__).resolve().parents[2]
WORK = OWN/'.tmp-lox-ast-selected-public-20261003'
OUT = Path(__file__).resolve().parent
sha = lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
receipt = json.loads((WORK/'qualification.json').read_text())
assert receipt['verified_after'] and receipt['fresh_public_passes'] == 336
before,after = receipt['before'],receipt['after']
assert before['source37'] == after['source37'] and len(after['source37']) == 37
assert before['baseline37'] == after['baseline37'] and len(after['baseline37']) == 37
assert before['artifacts_sha256'] == after['artifacts_sha256']
for path,h in after['artifacts_sha256'].items():assert sha(path) == h,path
assert len(receipt['runs']) == 4 and len(before['public_names']) == 84
for row in receipt['runs']:
    assert row['status'] == 0 and row['fresh_cache']
    assert row['counts'] == {'passed':84,'failed':0,'skipped':0,'cached':0,'executed':84,'dropped':0,'unloaded':0,'programs':10}
    assert '--cases' not in row['argv']
    assert sha(row['stdout']) == row['stdout_sha256'] and sha(row['stderr']) == row['stderr_sha256']
    report = json.loads(Path(row['stdout']).read_text())
    assert sorted(x['name'] for x in report['tests']) == before['public_names']
    assert all(x['status'] == 'passed' and x['actual'] is True and x['provider'] == '' for x in report['tests'])
    assert row['native_test_artifacts_sha256']
    for path,h in row['native_test_artifacts_sha256'].items():assert sha(path) == h,path
raw = ['qualification.json']+[Path(row['stdout']).name for row in receipt['runs']]
archives = {}
for name in raw:
    data = (WORK/name).read_bytes()
    output = OUT/(name+'.gz')
    output.write_bytes(gzip.compress(data,mtime=0))
    assert gzip.decompress(output.read_bytes()) == data
    archives[name] = {'raw_sha256':sha(WORK/name),'gzip_sha256':sha(output),'raw_bytes':len(data),'gzip_bytes':output.stat().st_size}
for name in ['run.log']+[Path(row['stderr']).name for row in receipt['runs']]:shutil.copyfile(WORK/name,OUT/name)
summary = {'scope':receipt['scope'],'source37':after['source37'],'baseline37':after['baseline37'],
           'fresh_selected_d14_ast84_public_passes':336,'public_names':before['public_names'],
           'all_sources_native_artifacts_tools_unchanged':True,'verified_after':True,
           'compiler_sha256':'d14a704083bcc5f5174932a751f7d9dda73100dbd62403626b42b52436cad040',
           'qbe_sha256':'99ad919d70ad582dee6202b045bd53e1ab18fec356de98849610f49983756d63',
           'provider_scope':receipt['provider_scope'],'runs':[{k:row[k] for k in ['key','argv','cwd','environment','status','counts','provider_identity','fresh_cache']}|{'native_test_artifacts':len(row['native_test_artifacts_sha256'])} for row in receipt['runs']],
           'started_utc':before['started_utc'],'finished_utc':receipt['finished_utc'],'runner_affinity':before['affinity'],'full_receipts':archives,
           'native_scope':'Existing selected d14 AST native ELF identities frozen for continuity; native 1168+96 and 8 refusal probes were not repeated.',
           'performance':'No timings, counters or performance selection in this qualification.'}
(OUT/'qualification.json').write_text(json.dumps(summary,indent=2)+'\n')
print('Rechecked 336 fresh selected-d14 AST public passes and all frozen identities; full JSON reports preserved.')
