#!/usr/bin/env python3
"""Qualify one immutable P4 snapshot under normal shared admission."""
from pathlib import Path
import os,subprocess,json,hashlib,shutil
ROOT=Path(__file__).resolve().parents[3]
HERE=Path(__file__).resolve().parent
WORK=ROOT/'.tmp/lox-eda-improvements/P4/qualification'
SOURCE=ROOT/'experiments/lox-eda-improvements-20261012/source/eda'
COMPILER=Path('/home/epentland/ai/canopy/mylang-text-gaps-main-20261012/.tmp/text-gaps/coordinator/common-002/install/bin/mylang')
WORK.mkdir(parents=True,exist_ok=True)
snapshot=WORK/'source'
if not snapshot.exists():
    shutil.copytree(SOURCE,snapshot)
hashes={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(snapshot.glob('*.my'))}
for p in snapshot.glob('*.my'):p.chmod(0o444)
(WORK/'tmp').mkdir(exist_ok=True)
env=dict(os.environ,MYL_CORE_LEAKCHECK='1',TMPDIR=str(WORK/'tmp'))
receipt={'compiler':str(COMPILER),'compiler_sha256':hashlib.sha256(COMPILER.read_bytes()).hexdigest(),'source':str(snapshot),'source_hashes':hashes,'MYL_CORE_LEAKCHECK':'1','commands':[]}
base=[str(COMPILER),'test','--experimental-zero-rc','--max-steps','1000000000','--max-frames','40000','--max-memory','2G','--timeout-ms','120000','--json']
checks=[('focused-verified-release',snapshot/'sexpr_borrowed_test.my',['--release','--verify-facts'],1)]
for name,source,flags,jobs in checks:
    command=[*base,str(source),*flags,'--jobs',str(jobs),'--cache-dir',str(WORK/name)]
    with (HERE/(name+'.json')).open('w') as out,(HERE/(name+'.stderr')).open('w') as err:
        result=subprocess.run([str(ROOT/'scripts/build-slot.sh'),'build',*command],cwd=ROOT,env=env,stdout=out,stderr=err)
    entry={'name':name,'command':command,'returncode':result.returncode}
    if result.returncode==0:
        data=json.loads((HERE/(name+'.json')).read_text());entry['counts']={k:data[k] for k in ('passed','failed','skipped','unsupported','cached')}
        assert data['passed']==4 and all(data[k]==0 for k in ('failed','skipped','unsupported'))
    receipt['commands'].append(entry);(HERE/'qualification.json').write_text(json.dumps(receipt,indent=2)+'\n')
    print(name,result.returncode,entry.get('counts'),flush=True)
    assert result.returncode==0,name
for name,want in hashes.items():assert hashlib.sha256((snapshot/name).read_bytes()).hexdigest()==want
assert {p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in SOURCE.glob('*.my')}==hashes
