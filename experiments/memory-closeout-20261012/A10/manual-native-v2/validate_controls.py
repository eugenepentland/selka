#!/usr/bin/env python3
"""Compare normal and manual candidate counted release binaries on JSON/tasks."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import manual_native_v2 as native


def main():
    p=argparse.ArgumentParser(description=__doc__)
    for name in ('compiler','zig','runtime','manifest','output','audit'):
        p.add_argument('--'+name,type=lambda value:Path(value).resolve(),required=True)
    args=p.parse_args()
    if os.environ.get('MYLANG_ADMISSION_KIND')!='build':p.error('requires existing shared build admission')
    args.output.mkdir(parents=True,exist_ok=False)
    spec=importlib.util.spec_from_file_location('counter_audit',args.audit);audit=importlib.util.module_from_spec(spec);spec.loader.exec_module(audit)
    manifests=json.loads(args.manifest.read_text())
    picked=[next(row for row in manifests['cases'] if row['id']==name) for name in ('array','parallel_cheap_1')]
    env=native.environment(args.output)
    env['MYL_CORE_LEAKCHECK']='1'
    results=[]
    for case in picked:
        name=case['id'];directory=args.output/name;directory.mkdir()
        source=Path(case['source']);assert native.digest(source)==case['source_sha256']
        llvm=directory/'program.ll';normal=directory/'normal';manual=directory/'manual'
        command=[args.compiler,'build',source,'--experimental-zero-rc','--release','--counters','--zig',args.zig,'--cache-dir',directory/'cache','-o',normal,'--emit-llvm',llvm]
        native.run(command,directory,env,'normal-build')
        artifact=native.link(args.runtime,llvm,manual,directory/'native')
        if name=='array':run_args=[]; expected=case['expected']
        else:run_args=['513','32','cheap'];expected=str(32*sum(v*3+1 for v in range(513)))+'\n'
        outcomes=[]
        for label,binary in [('normal',normal),('manual',manual)]:
            counters=directory/(label+'-counts.json')
            run_env=dict(env,MYLANG_COUNTERS=str(counters),MYLANG_THREADS='1')
            stdout=native.run([binary,*run_args],directory,run_env,label+'-run').decode()
            result=audit.audit(counters)
            assert stdout==expected and result['observed_rc_free'] and result['managed_leak_free'],(name,label,stdout,result)
            outcomes.append(dict(label=label,binary_sha256=native.digest(binary),output=stdout,counts=json.loads(counters.read_text()),audit=result))
        equal=outcomes[0]['counts']==outcomes[1]['counts']
        row=dict(id=name,source=str(source),source_sha256=native.digest(source),args=run_args,threads=1,
                 exact_counter_documents_equal=equal,normal=outcomes[0],manual=outcomes[1],manual_artifact=artifact)
        results.append(row)
        native.save(args.output/'results.json',dict(method=native.METHOD,scope='intermediate candidate equivalence controls; not final C1 or timing evidence',compiler=str(args.compiler),compiler_sha256=native.digest(args.compiler),adapter_sha256=native.digest(native.__file__),rows=results,passed=all(r['exact_counter_documents_equal'] for r in results)))
        assert equal,f'{name}: counter documents differ; inspect preserved reports'
        print(name,'normal/manual output and exact counters match',flush=True)


if __name__=='__main__':main()
