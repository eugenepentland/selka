#!/usr/bin/env python3
"""Isolated managed body workflow measurements, after installed correctness gates."""
import argparse
import json
from pathlib import Path
import os
import resource
import tempfile
import time
import run_body_check_qualification as D
from measure_frontend_adoption import execute, distribution


MAIN=b'import helper\n\nfunc main() -> int:\n    mut text = helper.text()\n    mut raw = helper.raw()\n    return len(text) + len(raw)\n'
HELPER='public func text() -> str:\n    return "é😀ab"\n\npublic func raw() -> bytes:\n    return b"xyz"\n'.encode()


def edited(original,index):
    return original.replace(b'b"xyz"',b'b"xyz'+b'!'*index+b'"')


def package_inventory(directory, baseline):
    return D.packages(directory, body_schema=1 if baseline else 2)


def cache_summary(stderr):
    report=json.loads(stderr)
    D.F.require(report.get('version')=='cache-report-v1','missing measured cache report')
    fields=('units','reused','compiled','verified','processes')
    D.F.require(all(type(report.get(key)) is int and report[key]>=0 for key in fields),'invalid cache work counters')
    return {'program':report['program'],**{key:report[key] for key in fields}}


def sample(command, env, work, expected, stdout=None):
    start=time.perf_counter_ns()
    result=execute(command,env,work,timeout=600)
    elapsed=time.perf_counter_ns()-start
    D.F.require(result[0]==expected and (stdout is None or result[1]==stdout), f'measured managed body workflow failed: {result!r}')
    return elapsed,result


def main():
    ap=argparse.ArgumentParser()
    for name in ('compiler','builder','component-dir','zig','output'):ap.add_argument('--'+name,type=Path,required=True)
    ap.add_argument('--source-root',type=Path,default=D.ROOT)
    ap.add_argument('--label',required=True)
    ap.add_argument('--baseline',action='store_true',help='frozen prior scalar body host: reference only, seven package schema 1 profile')
    ap.add_argument('--isolated',action='store_true')
    ap.add_argument('--prewarm-only',action='store_true',help='untimed native reference builds for every original/edit workload')
    ap.add_argument('--iterations',type=int,default=20)
    ap.add_argument('--edit-iterations',type=int,default=5)
    args=ap.parse_args()
    D.F.require(args.isolated and args.iterations>=5 and args.edit_iterations>=1,'requires isolated nonempty measurement')
    for name in ('compiler','builder','component_dir','zig','source_root'):setattr(args,name,getattr(args,name).resolve())
    manifests=package_inventory(args.component_dir,args.baseline)
    provision=execute([args.builder,'--root',args.source_root,'--zig',args.zig,'--seed-only'],D.coordinator_environment(),args.source_root,timeout=600)
    lines=provision[1].decode().strip().splitlines()
    D.F.require(provision[0]==0 and len(lines)==1 and Path(lines[0]).is_file(),'missing verified seed receipt')
    seed_sha256=D.F.digest(Path(lines[0]))
    host=D.F.digest(args.compiler)
    rows=[]
    with tempfile.TemporaryDirectory(prefix='body-check-measurement-') as temporary:
        work=Path(temporary);source=work/'source';source.mkdir();empty=work/'empty';empty.mkdir()
        (source/'main.my').write_bytes(MAIN)
        (source/'helper.my').write_bytes(HELPER)
        main=source/'main.my';helper=source/'helper.my';original=helper.read_bytes()
        native_env=D.environment('reference',args.component_dir,empty);native_env['MYL_CORE_LEAKCHECK']='0'
        prewarm=[]
        for index in range(args.edit_iterations+1):
            helper.write_bytes(edited(original,index))
            command=[args.compiler,'build',main,'--project','-o',work/'prewarm-program','--cache-dir',work/('prewarm-'+str(index)),f'--zig={args.zig}','--report']
            result=execute(command,native_env,work,timeout=600)
            D.F.require(result[0]==0 and execute([work/'prewarm-program'],native_env,work)==(7+index,b'',b''),'native prewarm behavior differs')
            prewarm.append(cache_summary(result[2]))
        helper.write_bytes(original)
        for mode in ([] if args.prewarm_only else (['reference'] if args.baseline else ['reference','component'])):
            helper.write_bytes(original)
            env=D.environment(mode,args.component_dir,empty);env['MYL_CORE_LEAKCHECK']='0'
            cache=work/f'cache-{mode}'
            command=[args.compiler,'build',main,'--project','-o',work/'program','--cache-dir',cache,f'--zig={args.zig}','--report']
            initial,prime=sample(command,env,work,0,b'')
            D.F.require(execute([work/'program'],env,work)==(7,b'',b''),'fresh program behavior differs')
            rows.append({'mode':mode,'phase':'fresh-application-cache','cache_evidence':prime[2].decode(),'cache_samples':[cache_summary(prime[2])],**distribution([initial])})
            warm=[];warm_reports=[]
            for _ in range(args.iterations):
                elapsed,result=sample(command,env,work,0,b'');warm.append(elapsed);warm_reports.append(cache_summary(result[2]))
                D.F.require(execute([work/'program'],env,work)==(7,b'',b''),'warm program behavior differs')
            rows.append({'mode':mode,'phase':'warm','cache_evidence':result[2].decode(),'cache_samples':warm_reports,**distribution(warm)})
            edits=[];edit_reports=[]
            for index in range(args.edit_iterations):
                value=8+index;helper.write_bytes(edited(original,index+1))
                elapsed,result=sample(command,env,work,0,b'');edits.append(elapsed);edit_reports.append(cache_summary(result[2]))
                D.F.require(execute([work/'program'],env,work)==(value,b'',b''),'edited program behavior differs')
            rows.append({'mode':mode,'phase':'edit','cache_evidence':result[2].decode(),'cache_samples':edit_reports,**distribution(edits)})
            helper.write_bytes(original)
            checking=[args.compiler,'check-project',main]
            _,prime=sample(checking,env,work,0)
            samples=[]
            for _ in range(args.iterations):
                elapsed,result=sample(checking,env,work,0,prime[1]);D.F.require(result==prime,'body check outcome differs');samples.append(elapsed)
            rows.append({'mode':mode,'phase':'check-project','stdout_sha256':D.F.hashlib.sha256(prime[1]).hexdigest(),**distribution(samples)})
    D.F.require(D.F.digest(args.compiler)==host,'measurement changed host')
    D.F.require(package_inventory(args.component_dir,args.baseline)==manifests,'measurement changed packages')
    evidence={'label':args.label,'measurement_script_sha256':D.F.digest(Path(__file__)),
              'qualification_script_sha256':D.F.digest(Path(D.__file__)),
              'source_root':str(args.source_root),'iterations':args.iterations,'edit_iterations':args.edit_iterations,'baseline_reference_only':args.baseline,'prewarm_only':args.prewarm_only,'native_prewarm_cache_samples':prewarm,'host_sha256':host,'packages':manifests,'verified_seed_sha256':seed_sha256,
              'fixed_modes':{'lexer':'reference','parser':'reference','test-index':'reference','cache-plan':'reference','declaration':'reference','type-interface':'reference'},
              'fact_leak_checks':'disabled for timings, qualified independently',
              'native_cache_scope':'private application caches; every original/edit native workload prewarmed untimed for both hosts before matched runs; shared native units/runtime/toolchain warm, receipts identify reuse',
              'rows':rows,'affinity':sorted(os.sched_getaffinity(0)),
              'children_peak_rss_kib':resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss,
              'rss_scope':'cumulative child high-water across complete run, not per exchange'}
    args.output.parent.mkdir(parents=True,exist_ok=True);args.output.write_text(json.dumps(evidence,indent=2)+'\n')
    print(json.dumps({'measurement':str(args.output),'host_sha256':host,'rows':len(rows)}))

if __name__=='__main__':main()
