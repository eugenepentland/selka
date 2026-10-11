#!/usr/bin/env python3
"""Isolated declaration workflow measurements, after installed correctness gates."""
import argparse
import json
from pathlib import Path
import os
import resource
import tempfile
import time
import run_declaration_qualification as D
from measure_frontend_adoption import execute, distribution


def sample(command, env, work, expected, stdout=None):
    start=time.perf_counter_ns()
    result=execute(command,env,work,timeout=600)
    elapsed=time.perf_counter_ns()-start
    D.F.require(result[0]==expected and (stdout is None or result[1]==stdout), f'measured declaration workflow failed: {result!r}')
    return elapsed,result


def main():
    ap=argparse.ArgumentParser()
    for name in ('compiler','builder','component-dir','zig','output'):ap.add_argument('--'+name,type=Path,required=True)
    ap.add_argument('--source-root',type=Path,default=D.ROOT)
    ap.add_argument('--label',required=True)
    ap.add_argument('--baseline',action='store_true',help='frozen prior host: reference mode only, no declaration package')
    ap.add_argument('--isolated',action='store_true')
    ap.add_argument('--iterations',type=int,default=20)
    ap.add_argument('--edit-iterations',type=int,default=5)
    args=ap.parse_args()
    D.F.require(args.isolated and args.iterations>=5 and args.edit_iterations>=1,'requires isolated nonempty measurement')
    for name in ('compiler','builder','component_dir','zig','source_root'):setattr(args,name,getattr(args,name).resolve())
    manifests=D.packages(args.component_dir,include_declaration=not args.baseline, include_type_interface=False, include_body=False)
    provision=execute([args.builder,'--root',args.source_root,'--zig',args.zig,'--seed-only'],D.coordinator_environment(),args.source_root,timeout=600)
    lines=provision[1].decode().strip().splitlines()
    D.F.require(provision[0]==0 and len(lines)==1 and Path(lines[0]).is_file(),'missing verified seed receipt')
    seed_sha256=D.F.digest(Path(lines[0]))
    host=D.F.digest(args.compiler)
    rows=[]
    with tempfile.TemporaryDirectory(prefix='declaration-measurement-') as temporary:
        work=Path(temporary);source=work/'source';D.F.copy_sources(source);empty=work/'empty';empty.mkdir()
        main=source/'main.my';helper=source/'helper.my';original=helper.read_bytes()
        for mode in (['reference'] if args.baseline else ['reference','component']):
            helper.write_bytes(original)
            env=D.environment(mode,args.component_dir,empty);env['MYL_CORE_LEAKCHECK']='0'
            cache=work/f'cache-{mode}'
            command=[args.compiler,'build',main,'--project','-o',work/'program','--cache-dir',cache,f'--zig={args.zig}','--report']
            initial,prime=sample(command,env,work,0,b'')
            rows.append({'mode':mode,'phase':'fresh-application-cache','cache_evidence':prime[2].decode(),**distribution([initial])})
            warm=[]
            for _ in range(args.iterations):
                elapsed,result=sample(command,env,work,0,b'');warm.append(elapsed)
                D.F.require(execute([work/'program'],env,work)==(7,b'',b''),'warm program behavior differs')
            rows.append({'mode':mode,'phase':'warm','cache_evidence':result[2].decode(),**distribution(warm)})
            edits=[]
            for index in range(args.edit_iterations):
                value=8+index;helper.write_bytes(original.replace(b'return 7',f'return {value}'.encode()))
                elapsed,result=sample(command,env,work,0,b'');edits.append(elapsed)
                D.F.require(execute([work/'program'],env,work)==(value,b'',b''),'edited program behavior differs')
            rows.append({'mode':mode,'phase':'edit','cache_evidence':result[2].decode(),**distribution(edits)})
            helper.write_bytes(original)
            interfaces=[args.compiler,'list-interfaces',main]
            _,prime=sample(interfaces,env,work,0)
            samples=[]
            for _ in range(args.iterations):
                elapsed,result=sample(interfaces,env,work,0,prime[1]);D.F.require(result==prime,'interface metadata differs');samples.append(elapsed)
            rows.append({'mode':mode,'phase':'interfaces','stdout_sha256':D.F.hashlib.sha256(prime[1]).hexdigest(),**distribution(samples)})
    D.F.require(D.F.digest(args.compiler)==host,'measurement changed host')
    D.F.require(D.packages(args.component_dir,include_declaration=not args.baseline, include_type_interface=False, include_body=False)==manifests,'measurement changed packages')
    evidence={'label':args.label,'baseline_reference_only':args.baseline,'host_sha256':host,'packages':manifests,'verified_seed_sha256':seed_sha256,
              'fixed_modes':{'lexer':'reference','parser':'reference','test-index':'reference','cache-plan':'reference'},
              'fact_leak_checks':'disabled for timings, qualified independently',
              'native_cache_scope':'private application cache, shared native units/runtime/toolchain may be warm; retained reports identify reuse',
              'rows':rows,'affinity':sorted(os.sched_getaffinity(0)),
              'children_peak_rss_kib':resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss,
              'rss_scope':'cumulative child high-water across complete run, not per exchange'}
    args.output.parent.mkdir(parents=True,exist_ok=True);args.output.write_text(json.dumps(evidence,indent=2)+'\n')
    print(json.dumps({'measurement':str(args.output),'host_sha256':host,'rows':len(rows)}))

if __name__=='__main__':main()
