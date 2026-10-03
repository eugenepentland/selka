#!/usr/bin/env python3
"""Compile frozen byte-guard IL variants to standalone objects; never run guests."""
from pathlib import Path
import argparse,hashlib,json,os,re,subprocess
lane=Path(__file__).resolve().parents[2]
parser=argparse.ArgumentParser()
parser.add_argument('--work',type=Path,default=lane/'.tmp-lox-byte-positive-20261003/refusal-diag')
work=parser.parse_args().work.resolve()
qbe=lane/'.tmp-lox-byte-positive-20261003/release/bin/qbe'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
inputs=json.loads((work/'inputs.json').read_text());assert sha(qbe)==inputs['qbe_sha256']=='99ad919d70ad582dee6202b045bd53e1ab18fec356de98849610f49983756d63'
output=work/'compiled.json';assert not output.exists()
env=dict(os.environ,TMPDIR=str(work.parent/'tmp'))
Path(env['TMPDIR']).mkdir(parents=True,exist_ok=True)
receipt={'inputs_sha256':sha(work/'inputs.json'),'qbe_sha256':sha(qbe),'runs':[],'verified_after':False}
for label,v in inputs['variants'].items():
    source=work/(label+'.ssa');assembly=work/(label+'.s');obj=work/(label+'.o')
    assert sha(source)==v['source_sha256']
    for cmd in [[str(qbe),'-o',str(assembly),str(source)],['cc','-c',str(assembly),'-o',str(obj)]]:
        argv=[str(lane/'scripts/build-slot.sh'),'build']+cmd
        result=subprocess.run(argv,cwd=lane,env=env,capture_output=True,timeout=120)
        receipt['runs'].append({'argv':argv,'status':result.returncode,'stdout':result.stdout.decode(),'stderr':result.stderr.decode()})
        output.write_text(json.dumps(receipt,indent=2)+'\n');assert result.returncode==0,result.stderr
    argv=['objdump','-d','--no-show-raw-insn',str(obj)];text=subprocess.check_output(argv,text=True);(work/(label+'.asm')).write_text(text)
    print(label,len(re.findall(r'^\s*[0-9a-f]+:\s+',text,re.M)),flush=True)
assert all(sha(work/(label+'.ssa'))==v['source_sha256'] for label,v in inputs['variants'].items())
assert sha(qbe)==receipt['qbe_sha256'];receipt['verified_after']=True;output.write_text(json.dumps(receipt,indent=2)+'\n')
