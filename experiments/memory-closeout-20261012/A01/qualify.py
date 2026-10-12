#!/usr/bin/env python3
"""A01 map correctness/allocation matrix; no historical report writes or timings."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
_spec=importlib.util.spec_from_file_location('zero_rc_audit',ROOT/'experiments/zero-rc-20261011/audit.py')
_audit=importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_audit)
MODES = {'release': ['--release'], 'debug': ['--unoptimized'], 'verify': ['--release', '--verify-facts'],
         'optimized_debug': [], 'no_facts': ['--release', '--no-facts'],
         'tsan': ['--release']}
EXPECTED = {'wide': '2145\n', 'managed': '2016 item-0! 16\n', 'outcome': '416\n',
            'ranges': str(sum(sum(i*i for i in range(n)) for n in [0,1,2,7,8,9,31,32,33,65,257,1025]))+'\n',
            'result': str(sum(len(('bad-' if i%3==0 else 'good-')+str(i)) for i in range(257)))+'\n'}

def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def run(argv, env):
    result = subprocess.run(list(map(str, argv)), cwd=ROOT, env=env, capture_output=True, text=True, timeout=600)
    return {'argv': list(map(str, argv)), 'status': result.returncode, 'stdout': result.stdout, 'stderr': result.stderr}

def main():
    p=argparse.ArgumentParser(description=__doc__)
    for key in ('compiler','zig','output'): p.add_argument('--'+key, type=Path, required=True)
    p.add_argument('--modes', nargs='+', choices=list(MODES), default=list(MODES))
    p.add_argument('--cases', nargs='+', default=list(EXPECTED)+['trap'])
    p.add_argument('--repeat', type=int, default=1)
    p.add_argument('--source-revision', required=True)
    a=p.parse_args()
    for key in ('compiler','zig','output'): setattr(a,key,getattr(a,key).resolve())
    a.output.mkdir(parents=True,exist_ok=True)
    env=dict(os.environ, ZIG=str(a.zig), MYLANG_ZIG=str(a.zig), MYL_CORE_LEAKCHECK='1')
    for key in ('MYLANG_CORE_SANITIZE','MYLANG_COUNTERS','MYLANG_OPTIONS'): env.pop(key,None)
    results={'source_revision':a.source_revision,'compiler_sha256':digest(a.compiler),'harness_sha256':digest(__file__),'cases':{},'failures':[]}
    def save(): (a.output/'results.json').write_text(json.dumps(results,indent=2)+'\n')
    for case in a.cases:
        source=HERE/'samples'/(case+'.my')
        for mode in a.modes:
            d=a.output/case/mode; d.mkdir(parents=True,exist_ok=True)
            binary=d/'program'; llvm=d/'program.ll'
            local=dict(env, **({'MYLANG_CORE_SANITIZE':'thread'} if mode=='tsan' else {}))
            build=run([ROOT/'scripts/build-slot.sh','build',a.compiler,'build',source,'--zig',a.zig,'--cache-dir',a.output/'cache','--experimental-zero-rc',*MODES[mode],*(['--counters'] if mode!='tsan' else []),'-o',binary,'--emit-llvm',llvm],local)
            item={'source_sha256':digest(source),'build':build,'runs':[]}
            results['cases'][case+'/'+mode]=item
            if build['status']:
                results['failures'].append(case+'/'+mode+'/build'); save(); continue
            item['binary_sha256']=digest(binary); item['llvm_sha256']=digest(llvm)
            symbols=run(['nm',binary],local)['stdout']
            item['structural_rc_free']=not any(x in symbols or x in llvm.read_text() for x in ['myl_core_retain','myl_core_release','myl_core_share'])
            if not item['structural_rc_free']: results['failures'].append(case+'/'+mode+'/structural')
            for threads in ('1','2','8'):
                for repetition in range(a.repeat):
                    counts=d/('counts-'+threads+'-'+str(repetition)+'.json')
                    record=run([binary],dict(local,MYLANG_THREADS=threads,MYLANG_COUNTERS=str(counts)))
                    record.update(threads=int(threads),repetition=repetition)
                    if case=='trap':
                        record['passed']=record['status']!=0 and 'parallel.map item 17' in record['stderr']
                    else:
                        record['passed']=record['status']==0 and record['stdout']==EXPECTED[case] and record['stderr']==''
                    if counts.exists():
                        record['counts_path']=str(counts.relative_to(a.output))
                        record['audit']=_audit.audit(counts)
                        if case!='trap': record['passed'] &= record['audit']['managed_leak_free'] and record['audit']['observed_rc_free']
                    if not record['passed']: results['failures'].append(case+'/'+mode+'/'+threads+'/'+str(repetition))
                    item['runs'].append(record)
            print(case,mode,'pass' if all(x['passed'] for x in item['runs']) else 'FAIL',flush=True); save()
    save()
    raise SystemExit(bool(results['failures']))

if __name__=='__main__': main()
