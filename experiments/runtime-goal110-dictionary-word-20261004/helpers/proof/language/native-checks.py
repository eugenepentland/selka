#!/usr/bin/env python3
"""Untimed ordinary/typed compiler differential with positive process oracles."""
import argparse, hashlib, importlib.util, json, os, shutil, subprocess
from datetime import datetime, timezone
from pathlib import Path
ROOT=Path.cwd().resolve()
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--before-receipt',type=Path,required=True)
parser.add_argument('--after-receipt',type=Path,required=True)
parser.add_argument('--output',type=Path,required=True)
args=parser.parse_args(); output=args.output.resolve(); output.mkdir(parents=True,exist_ok=False)
FIXTURE=Path(__file__).with_name('dictionary-word.my').resolve()
def artifact(path):
    path=Path(path).resolve(strict=True)
    return {'path':str(path),'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'bytes':path.stat().st_size}
def stamp(): return datetime.now(timezone.utc).isoformat()
def clean_environment(): return {k:v for k,v in os.environ.items() if not k.startswith('MYLANG_')}
spec=importlib.util.spec_from_file_location('build_compiler',ROOT/'benchmarks/runtime/build_compiler.py')
module=importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
hosts={};receipts={}
for label,path in [('before',args.before_receipt),('after',args.after_receipt)]:
    r=json.loads(path.read_text()); host=Path(r['compiler_path']).resolve(strict=True)
    module.validate_receipt(r,host,artifacts=True)
    receipts[label]={'artifact':artifact(path),'document':r};hosts[label]=host
assert receipts['before']['document']['source_revision']=='1a3980631e79bc65f048acd063d7250800f01901'
assert receipts['after']['document']['source_revision']=='a2dfdfa994e19ac3c80373a443913c7ecdef23d7'
qbe=ROOT/'zig-out/bin/qbe'; zig=Path(shutil.which('zig')).resolve(strict=True)
report={'schema':'mylang-dictionary-word-language-proof-v1','status':'in-progress','started_utc':stamp(),'timing':False,
        'receipts':receipts,'fixture':artifact(FIXTURE),'driver':artifact(__file__),'tools':{'zig':artifact(zig),'qbe':artifact(qbe)},
        'invocations':[],'emissions':[],'builds':[],'comparisons':[]}
def save(): (output/'report.json').write_text(json.dumps(report,indent=2)+'\n')
save();print(json.dumps({'hosts':{label:artifact(host) for label,host in hosts.items()},'source_revisions':{label:r['document']['source_revision'] for label,r in receipts.items()},'fixture':report['fixture']}),flush=True)
def execute(command,environment):
    exe=artifact(command[0]); started=stamp()
    done=subprocess.run(list(map(str,command)),cwd=ROOT,env=environment,capture_output=True,timeout=300)
    row={'command':list(map(str,command)),'executable':exe,'started_utc':started,'finished_utc':stamp(),
         'status':done.returncode,'stdout':done.stdout.decode(),'stderr':done.stderr.decode(),'executable_after':artifact(command[0])}
    assert row['executable']==row['executable_after'];report['invocations'].append(row);save();return row
old={-1:7,0:11,1:13};minimum=-(1<<63);maximum=(1<<63)-1
cases=[(0,k,0) for k in (-2,-1,0,1,2,minimum,maximum)]
cases += [(1,k,v) for k in (-1,0,9) for v in (-7,0,29)]
cases += [(2,k,v) for k in (-1,0,2) for v in (-11,0,maximum)]
cases += [(3,k,0) for k in (-2,0,2)] + [(4,k,0) for k in (-1,0,2)]
cases += [(5,0,0)] + [(6,k,v) for k in (0,9) for v in (33,maximum)]
cases += [(7,k,0) for k in (-1,0,2)]
cases += [(8,0,0),(9,0,37),(9,2,37),(10,0,0),(11,1,0),(11,2,0),(12,9,maximum)]
cases += [(13,k,0) for k in (-1,0,1,9)] + [(14,0,-7),(15,0,0)]
def expected(case):
    kind,key,delta=case;prefix='41\n'
    if kind==0:
        if key not in old:return {'failure':'R_MISSING_KEY','stdout':prefix}
        value=old[key]
    elif kind==1: value=old.get(key,delta);prefix+='43\n'
    elif kind==2:value=old.get(key,23)+delta
    elif kind==3:value=17
    elif kind==4:
        if key not in old:return {'failure':'R_MISSING_KEY','stdout':prefix}
        value=old[key]+23
    elif kind==5:value=143
    elif kind==6:
        if delta==maximum:return {'failure':'R_OVERFLOW','stdout':prefix}
        value=old.get(key,delta+1)
    elif kind==7:value=old.get(key,0)+1
    elif kind==8:value=71
    elif kind==9:value=29 if key==0 else delta
    elif kind==10:value=31
    elif kind==11:value=3 if key==1 else 5
    elif kind==12:value=delta
    elif kind==13:value=old.get(key,19)
    elif kind==14:value=delta+3
    else:value=73
    if not minimum<=value<=maximum:return {'failure':'R_OVERFLOW','stdout':prefix}
    return {'value':value,'status':value&255,'stdout':prefix+str(value)+'\n'}
configs=[('rc-v5',backend,accounted) for backend in ('qbe','llvm') for accounted in (False,True)]
configs += [(runtime,'llvm',False) for runtime in ('gc-v1','rc-v5-counting','rc-v5-sites')]
try:
    for runtime,backend,accounted in configs:
        label=f'{runtime}-{backend}-accounted{int(accounted)}'; binaries={};texts={}
        for arm,host in hosts.items():
            work=output/label/arm;work.mkdir(parents=True);(work/'tmp').mkdir()
            env={**clean_environment(),'MYLANG_RUNTIME':runtime,'TMPDIR':str(work/'tmp'),'ZIG_LOCAL_CACHE_DIR':str(work/'zig-local'),'ZIG_GLOBAL_CACHE_DIR':str(output/'zig-global')}
            env.pop('MYLANG_OPTIONS',None)
            emit=execute([host,'emit-qbe',FIXTURE],env);assert emit['status']==0,emit
            text=emit['stdout'];texts[arm]=text;path=work/'emission.json';path.write_text(text)
            count=text.count('call $myl_native_dictionary_read_word(')
            if runtime in ('rc-v5-counting','rc-v5-sites'):assert count==0,(label,arm,count)
            elif arm=='after':assert count>0,(label,arm,count)
            else:assert count==0,(label,arm,count)
            report['emissions'].append({'config':label,'arm':arm,'artifact':artifact(path),'word_read_calls':count})
            binary=work/'guest';command=[ROOT/'scripts/build-slot.sh','build',host,'build',FIXTURE,'-o',binary,'--cache-dir',work/'cache','--zig',zig,'--qbe',qbe,'--mode','ReleaseFast','--backend',backend,'--keep-symbols']
            if backend=='llvm':command+=['--llvm-opt','3','--lto']
            if accounted:command+=['--step-accounting','--max-frames=10000']
            done=execute(command,env);assert done['status']==0,done
            sidecar=Path(str(binary)+'.qbe-manifest.json');policy=json.loads(sidecar.read_text());assert policy['backend']==backend
            if backend=='llvm':assert policy['optimization']=='3' and policy['lto']
            report['builds'].append({'config':label,'arm':arm,'binary':artifact(binary),'sidecar':artifact(sidecar),'policy':policy});binaries[arm]=binary
        if runtime in ('rc-v5-counting','rc-v5-sites'):assert texts['before']==texts['after'],label
        for case in cases:
            env={**clean_environment(),'MYLANG_OPTIONS':'--print-result'+(' --gc-stress' if runtime=='gc-v1' else '')}
            results={arm:execute([binary,*map(str,case)],env) for arm,binary in binaries.items()}
            a,b=results['before'],results['after'];assert all(a[k]==b[k] for k in ('status','stdout','stderr')),(label,case,results)
            oracle=expected(case)
            if 'failure' in oracle:assert b['status']!=0 and b['stdout']==oracle['stdout'] and f"error[{oracle['failure']}]" in b['stderr'],(label,case,oracle,b)
            else:assert b['status']==oracle['status'] and b['stdout']==oracle['stdout'],(label,case,oracle,b)
            report['comparisons'].append({'config':label,'case':case,'oracle':oracle,'results':results});save()
        if accounted:
            for options,code in [('--print-result --max-steps=1','R_STEP_LIMIT'),('--print-result --max-frames=1','R_FRAME_LIMIT')]:
                results={arm:execute([binary,'0','0','0'],{**clean_environment(),'MYLANG_OPTIONS':options}) for arm,binary in binaries.items()}
                a,b=results['before'],results['after'];assert all(a[k]==b[k] for k in ('status','stdout','stderr')),(label,options,results)
                assert b['status']!=0 and code in b['stderr'],(label,options,b)
                report['comparisons'].append({'config':label,'options':options,'expected_failure':code,'results':results});save()
    for arm,r in receipts.items():module.validate_receipt(r['document'],hosts[arm],artifacts=True)
    assert artifact(FIXTURE)==report['fixture'] and artifact(__file__)==report['driver']
    for row in report['builds']:assert artifact(row['binary']['path'])==row['binary'] and artifact(row['sidecar']['path'])==row['sidecar']
    report.update(status='passed',finished_utc=stamp(),comparison_count=len(report['comparisons']),execution_count=2*len(report['comparisons']))
finally:save()
print(f"PASS {report['comparison_count']} exact native pairs / {report['execution_count']} executions",flush=True)
