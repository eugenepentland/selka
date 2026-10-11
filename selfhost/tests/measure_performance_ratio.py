#!/usr/bin/env python3
"""Strict per-workflow performance accounting; selected components remain intermediate."""
import argparse
import json
import os
import math
import resource
from pathlib import Path
import tempfile
import time
import run_frontend_qualification as F
from measure_frontend_adoption import execute, distribution

FIXTURES=Path(__file__).with_name('fixtures')/'performance_ratio'
MODES=('LEXER','PARSER','DECLARATION','TYPE_INTERFACE','BODY_CHECK','TEST_INDEX','CACHE_PLAN')


def summarize(samples):
    F.require(bool(samples) and all(type(value) is int and value>0 for value in samples),'invalid timing samples')
    result=distribution(samples)
    result['p95_ns']=sorted(samples)[math.ceil(len(samples)*.95)-1]
    return result


def verdict(baseline,candidate,budget=1.5):
    F.require(set(baseline)==set(candidate) and bool(baseline),'missing or extra performance rows')
    rows=[]
    for key in baseline:
        a,b=baseline[key],candidate[key]
        F.require(a['samples_ns'] and b['samples_ns'],'empty performance sample')
        ratios={name:b[name]/a[name] for name in ('median_ns','p95_ns')}
        rows.append({'workflow':key,'ratios':ratios,'passed':all(value<=budget for value in ratios.values())})
    return {'budget':budget,'rows':rows,'passed':all(row['passed'] for row in rows)}


def environment(prefix,modes,empty):
    env={k:v for k,v in os.environ.items() if not k.startswith(('MYLANG_','MYL_CORE_','PILOT_','BODY_'))}
    env.update(PATH=str(empty),MYLANG_COMPONENT_DIR=str(prefix/'libexec/mylang/components'),MYL_CORE_LEAKCHECK='0')
    for name in MODES:env['MYLANG_'+name+'_MODE']=modes.get(name,'reference')
    return env


def inventory(prefix,body_schema):
    result={}
    directory=prefix/'libexec/mylang/components'
    for path in sorted(directory.glob('*.json')):
        value=json.loads(path.read_text());artifact=directory/value['artifact']
        F.require(path.stem==value.get('component') and all(type(value.get(k)) is int for k in ('protocol','schema')),'malformed package identity')
        F.require(Path(value['artifact']).name==value['artifact'] and F.digest(artifact)==value['sha256'],'unauthenticated package')
        result[value['component']]=value
    versions={'test-index':(1,1),'cache-plan':(2,2),'lexer-pilot':(1,2),'parser-pilot':(1,2),'declaration-index':(1,1),'type-interface':(1,1),'body-check':(1,body_schema)}
    F.require(set(result)==set(versions),'changed intermediate package inventory')
    for name,(protocol,schema) in versions.items():
        F.require(result[name].get('protocol')==protocol and result[name].get('schema')==schema,'wrong package wire version')
    return result


def tests(result,cached):
    F.test_counts(result,expected=2,allow_cached=cached)
    report=json.loads(result[1]);F.require(report.get('cached')==(2 if cached else 0),'wrong cold/warm test receipt state')
    return report


def warm_build(stderr):
    report=json.loads(stderr)
    F.require(report.get('version')=='cache-report-v1' and report.get('program')=='replayed','warm program receipt was not replayed')
    for key in ('units','reused','compiled','verified','processes'):
        F.require(type(report.get(key)) is int and report[key]>=0,'invalid warm work counter')
    F.require(report['compiled']==0 and report['processes']==0,'warm build performed fresh compiler work')
    return report


def measured(command,env,work,expected,validator=None):
    start=time.perf_counter_ns();result=execute(command,env,work,timeout=600);elapsed=time.perf_counter_ns()-start
    F.require(result[0]==expected,'measured command failed: '+repr(result))
    if validator:validator(result)
    return elapsed,result


def main():
    ap=argparse.ArgumentParser()
    for key in ('baseline-prefix','candidate-prefix','zig','output'):ap.add_argument('--'+key,type=Path,required=True)
    ap.add_argument('--candidate-mode',action='append',default=[],help='NAME=reference|component; unspecified boundaries remain reference')
    ap.add_argument('--baseline-host-sha256',default='3c9f1f1c1806eadd21c0281b4cf216d74e2a4854415a4176e2010416b99c3496')
    ap.add_argument('--source-root',type=Path,default=Path(__file__).resolve().parents[2])
    ap.add_argument('--baseline-body-schema',type=int,default=2)
    ap.add_argument('--candidate-body-schema',type=int,default=6)
    ap.add_argument('--iterations',type=int,default=20);ap.add_argument('--isolated',action='store_true')
    args=ap.parse_args();F.require(args.isolated and args.iterations>=5,'isolated nonempty samples required')
    F.require(sorted(os.sched_getaffinity(0))==[2,3,10,11] and '/gate' in os.readlink('/proc/self/fd/30'),'timing reservation/affinity absent')
    F.require(F.digest(args.baseline_prefix/'bin/mylang')==args.baseline_host_sha256,'frozen baseline host changed')
    modes={}
    for item in args.candidate_mode:
        name,value=item.split('=',1);F.require(name in MODES and name not in modes and value in ('reference','component'),'invalid explicit mode');modes[name]=value
    F.require(bool(modes),'candidate mode selection must be explicit')
    evidence={'tool_sha256':F.digest(Path(__file__)),'affinity':sorted(os.sched_getaffinity(0)),'facts_leaks':'qualified before timings; disabled consistently during timings','scope':'intermediate seven-package scalar/managed/list/record/variant/failure subset, not full language selfhosting','iterations':args.iterations,'modes':modes,'hosts':{},'rows':{},'behavior_checks':[]}
    with tempfile.TemporaryDirectory(prefix='performance-ratio-') as temporary:
        work=Path(temporary);empty=work/'empty';empty.mkdir()
        # Match native-unit warmth before either host contributes timing samples.
        evidence['native_prewarm']=[]
        for label,prefix in [('baseline',args.baseline_prefix),('candidate',args.candidate_prefix)]:
            prefix=prefix.resolve();env=environment(prefix,{},empty)
            for fixture in sorted(FIXTURES.iterdir()):
                source=work/('prewarm-'+label+'-'+fixture.name);source.mkdir()
                for path in fixture.glob('*.input'):(source/path.with_suffix('.my').name).write_bytes(path.read_bytes())
                result=execute([prefix/'bin/mylang','build',source/'main.my','--project','--release','-o',source/'program','--cache-dir',source/'cache',f'--zig={args.zig}','--report'],env,source,timeout=600)
                F.require(result[0]==0 and execute([source/'program'],env,source)==(7,b'',b''),'native prewarm failed')
                evidence['native_prewarm'].append({'host':label,'fixture':fixture.name,'cache_receipt':result[2].decode()})
        evidence['cache_scope']='fresh private application caches; native units prewarmed for both hosts before timing'
        for label,prefix,selected in [('baseline',args.baseline_prefix,{}),('candidate',args.candidate_prefix,modes)]:
            prefix=prefix.resolve();compiler=prefix/'bin/mylang';body_schema=args.baseline_body_schema if label=='baseline' else args.candidate_body_schema
            seed_env=environment(prefix,{},empty)
            seed=execute([prefix/'tools/selka-components','--root',args.source_root,'--zig',args.zig,'--seed-only'],seed_env,work,timeout=600)
            seed_lines=seed[1].decode().strip().splitlines();F.require(seed[0]==0 and len(seed_lines)==1 and Path(seed_lines[0]).is_file(),'qualified seed receipt failed')
            identity={'host_sha256':F.digest(compiler),'packages':inventory(prefix,body_schema),'verified_seed_sha256':F.digest(Path(seed_lines[0]))};evidence['hosts'][label]=identity
            env=environment(prefix,selected,empty);rows={};evidence['rows'][label]=rows
            for fixture in sorted(FIXTURES.iterdir()):
                source=work/(label+'-'+fixture.name);source.mkdir()
                for path in fixture.glob('*.input'):(source/path.with_suffix('.my').name).write_bytes(path.read_bytes())
                main=source/'main.my';program=source/'program';cache=source/'cache'
                build=[compiler,'build',main,'--project','--release','-o',program,'--cache-dir',cache,f'--zig={args.zig}','--report']
                check=[compiler,'check-project',main]
                test=[compiler,'test',main,'--json','--release','--cache-dir',cache,f'--zig={args.zig}']
                # Behavior/facts/leaks gate precedes every measured subset; unsupported forms fail.
                correctness=dict(env,MYL_CORE_LEAKCHECK='1')
                result=execute([*test,'--force','--no-cache','--verify-facts'],correctness,source,timeout=600);tests(result,False)
                evidence['behavior_checks'].append({'host':label,'fixture':fixture.name,'tests':2,'facts_leaks':True})
                F.require(execute(build,env,source,timeout=600)[0]==0,'prime build failed');F.require(execute([program],env,source)==(7,b'',b''),'generated behavior differs')
                cold=[];cold_receipts=[]
                for index in range(args.iterations):
                    command=list(build);command[command.index('--cache-dir')+1]=source/('fresh-cache-'+str(index))
                    elapsed,result=measured(command,env,source,0)
                    F.require(execute([program],env,source)==(7,b'',b''),'fresh generated behavior differs')
                    cold.append(elapsed);cold_receipts.append(result[2].decode())
                rows[fixture.name+'/compile-fresh-application-cache']={**summarize(cold),'cache_receipts':cold_receipts}
                commands={'check':(check,0,None),'compile-warm':(build,0,None),'test-cold':([*test,'--force','--no-cache'],0,lambda r:tests(r,False)),'test-warm':(test,0,lambda r:tests(r,True)),'runtime':([program],7,lambda r:F.require(r==(7,b'',b''),'runtime output differs'))}
                tests(execute(test,env,source,timeout=600),False)
                for phase,(command,status,validator) in commands.items():
                    samples=[];receipts=[]
                    for _ in range(args.iterations):
                        elapsed,result=measured(command,env,source,status,validator)
                        if phase=='compile-warm':
                            warm_build(result[2])
                        samples.append(elapsed);receipts.append({'stdout':result[1].decode(),'stderr':result[2].decode()})
                    rows[fixture.name+'/'+phase]={**summarize(samples),'receipts':receipts,'command':[str(x) for x in command]}
                F.require(F.digest(compiler)==identity['host_sha256'] and inventory(prefix,body_schema)==identity['packages'],'measured deployment changed')
    evidence['children_peak_rss_kib']=resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss
    evidence['rss_scope']='complete matched run cumulative child high-water, not per workflow'
    evidence['verdict']=verdict(evidence['rows']['baseline'],evidence['rows']['candidate'])
    args.output.parent.mkdir(parents=True,exist_ok=True);args.output.write_text(json.dumps(evidence,indent=2)+'\n')
    print(json.dumps(evidence['verdict']));raise SystemExit(0 if evidence['verdict']['passed'] else 1)

if __name__=='__main__':main()
