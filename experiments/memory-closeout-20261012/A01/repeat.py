#!/usr/bin/env python3
"""Repeat qualified A01 binaries at eight workers without rebuilding them."""
import argparse
import importlib.util
import json
import os
from pathlib import Path

HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('a01_qualify',HERE/'qualify.py')
q=importlib.util.module_from_spec(spec)
spec.loader.exec_module(q)

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--input',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True)
    p.add_argument('--repeat',type=int,default=100)
    p.add_argument('--modes',nargs='+',default=['release','tsan'])
    p.add_argument('--admitted',action='store_true',help=argparse.SUPPRESS)
    a=p.parse_args()
    q.admit(a.admitted)
    a.input=a.input.resolve();a.output=a.output.resolve()
    a.output.mkdir(parents=True,exist_ok=True)
    raw=(a.input/'results.json').read_bytes()
    (a.output/'qualification-input.json').write_bytes(raw)
    qualified=json.loads(raw)
    result={'qualification_sha256':q.digest(a.output/'qualification-input.json'),'compiler_sha256':qualified['compiler_sha256'],'ownership_selection':qualified.get('ownership_selection','unrecorded'),'runs':[]}
    for key,item in qualified['cases'].items():
        case,mode=key.split('/')
        if mode not in a.modes or case=='trap' or item['build']['status']: continue
        binary=a.input/case/mode/'program'
        assert q.digest(binary)==item['binary_sha256']
        for i in range(a.repeat):
            counts=a.output/('counts-'+case+'-'+mode+'-'+str(i)+'.json')
            env=dict(os.environ,MYLANG_THREADS='8',MYLANG_COUNTERS=str(counts),MYL_CORE_LEAKCHECK='1')
            ran=q.run([binary],env)
            ran.update(case=case,mode=mode,repetition=i,binary_sha256=q.digest(binary))
            ran['passed']=ran['status']==0 and ran['stdout']==q.EXPECTED[case] and ran['stderr']==''
            if counts.exists():
                ran['audit']=q._audit.audit(counts)
                ran['passed'] &= ran['audit']['observed_rc_free'] and ran['audit']['managed_leak_free']
            result['runs'].append(ran)
            (a.output/'results.json').write_text(json.dumps(result,indent=2)+'\n')
            if not ran['passed']: raise SystemExit(1)
        print(case,mode,a.repeat,'passed',flush=True)
    assert result['runs'], 'No matching binaries'

if __name__=='__main__':main()
