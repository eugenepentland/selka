#!/usr/bin/env python3
"""Application measurer adapted with a calibrated checked/Zig runtime deadline.
Original harness: ../lox-eda-zero-rc-20261012/bench/measure.py (kept unchanged).
Spec: {arms:{name:[argv...]}, oracle:name, files:[input paths], artifacts:[paths]}.
Invoke via scripts/build-slot.sh timing; do not nest admission.
"""
import argparse, datetime, hashlib, json, os, pathlib, shutil, signal, statistics, subprocess, tempfile, time

def digest(p):
    return hashlib.sha256(pathlib.Path(p).read_bytes()).hexdigest()

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('spec',type=pathlib.Path);p.add_argument('output',type=pathlib.Path)
    p.add_argument('--cpu',type=int,default=8);p.add_argument('--rounds',type=int,default=9)
    p.add_argument('--round-start',type=int,default=0);p.add_argument('--warmups',type=int,default=2)
    p.add_argument('--rss-rounds',type=int,default=3)
    p.add_argument('--guest-timeout',type=float,default=120)
    p.add_argument('--zig-factor',type=float,default=3)
    p.add_argument('--calibration-rounds',type=int,default=5)
    p.add_argument('--calibration-warmups',type=int,default=2)
    a=p.parse_args();assert not a.output.exists()
    assert a.zig_factor>0 and a.calibration_rounds>0 and a.calibration_warmups>=0
    journal=a.output.with_suffix(a.output.suffix+'.progress.jsonl')
    assert not journal.exists()
    def checkpoint(kind,record):
        with journal.open('a') as stream:
            stream.write(json.dumps({'kind':kind,**record})+'\n')
            stream.flush()
    assert a.cpu in os.sched_getaffinity(0)
    os.sched_setaffinity(0,{a.cpu})
    spec=json.loads(a.spec.read_text());arms=spec['arms'];names=list(arms)
    paths=set(spec.get('files',[]))|{v[0] for v in arms.values()}
    def identities_now():
        result={f:digest(f) for f in sorted(paths)}
        for dirname in spec.get('identity_dirs',[]):
            result.update({str(f):digest(f) for f in sorted(pathlib.Path(dirname).rglob('*')) if f.is_file()})
        return result
    identities=identities_now()
    arm_status={name:{'status':'ok'} for name in names}
    prior_identity=None
    relative_policy=None
    if spec.get('prior_receipt'):
        prior_path=pathlib.Path(spec['prior_receipt']);prior=json.loads(prior_path.read_text())
        assert prior['spec']['cell']==spec['cell'] and prior['spec']['arms']==arms
        assert prior['identities']==identities, 'inputs changed between chunks'
        prior_identity={'path':str(prior_path),'sha256':digest(prior_path)}
        for name,status in prior.get('arm_status',{}).items():
            if status['status']!='ok':arm_status[name]={**status,'inherited_from_prior_chunk':True}
        relative_policy=prior['relative_timeout_policy']
        assert relative_policy['factor']==a.zig_factor
    doc={'started_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
         'measurement_harness_sha256':digest(__file__),'prior_receipt':prior_identity,
         'host':os.uname()._asdict() if hasattr(os.uname(),'_asdict') else list(os.uname()),
         'loadavg_start':os.getloadavg(),'spec':spec,'spec_sha256':digest(a.spec),'cpu':a.cpu,'identities':identities,
         'guest_timeout_seconds':a.guest_timeout,'warmups':a.warmups,'round_start':a.round_start,'rounds':a.rounds,'wall_samples':[],'rss_samples':[],
         'arm_status':arm_status}
    checkpoint('header',{k:v for k,v in doc.items() if k not in ['wall_samples','rss_samples']})
    oracle=None
    def execute(argv,name,rss=False):
        relative=name=='mylang-zero-rc' and not rss and relative_policy is not None and relative_policy.get('budget_seconds') is not None
        deadline=relative_policy['budget_seconds'] if relative else a.guest_timeout
        started=time.perf_counter()
        child=subprocess.Popen(argv,stdout=subprocess.PIPE,stderr=subprocess.PIPE,cwd=spec.get('cwd'),start_new_session=True,env={**os.environ,**spec.get('env_by_arm',{}).get(name,{})})
        try:
            stdout,stderr=child.communicate(timeout=max(0,deadline-(time.perf_counter()-started)))
        except subprocess.TimeoutExpired:
            elapsed=time.perf_counter()-started
            try:os.killpg(child.pid,signal.SIGKILL)
            except ProcessLookupError:pass
            stdout,stderr=child.communicate()
            return {'status':'relative_timeout' if relative else 'timeout','arm':name,'argv':argv,'timeout_seconds':deadline,
                    'observed_wall_before_kill_seconds':elapsed,'relative_timeout_policy':relative_policy if relative else None,
                    'censored':True,'stdout_sha256':hashlib.sha256(stdout).hexdigest(),'stderr':stderr.decode(errors='replace')}
        return subprocess.CompletedProcess(argv,child.returncode,stdout,stderr)
    def run(name,rss=False):
        nonlocal oracle
        argv=arms[name];measurement=None
        if spec.get('out_dir'):
            shutil.rmtree(spec['out_dir'],ignore_errors=True)
        if rss:
            with tempfile.NamedTemporaryFile() as f:
                r=execute(['/usr/bin/time','-f','%M','-o',f.name,*argv],name,True)
                if isinstance(r,dict):return r
                if r.returncode:return {'status':'failed','arm':name,'argv':argv,'returncode':r.returncode,'stderr':r.stderr.decode(errors='replace')}
                measurement=int(pathlib.Path(f.name).read_text().strip())
        else:
            start=time.perf_counter_ns();r=execute(argv,name)
            measurement=(time.perf_counter_ns()-start)/1e9
            if isinstance(r,dict):return r
        if r.returncode:
            return {'status':'failed','arm':name,'argv':argv,'returncode':r.returncode,'stderr':r.stderr.decode(errors='replace')}
        result={'stdout_sha256':hashlib.sha256(r.stdout).hexdigest(),
                'artifacts':{f:digest(f) for f in spec.get('artifacts',[])}}
        if spec.get('golden_dir'):
            def tree(d):
                return {str(f.relative_to(d)):digest(f) for f in pathlib.Path(d).rglob('*') if f.is_file()}
            got=tree(pathlib.Path(spec['out_dir']));want=tree(pathlib.Path(spec['golden_dir']))
            if got!=want:return {'status':'output_mismatch','arm':name,'reason':'golden tree','got':got,'expected':want}
            result['golden_tree']=got
        if spec.get('expected_stdout'):
            if r.stdout!=pathlib.Path(spec['expected_stdout']).read_bytes():
                return {'status':'output_mismatch','arm':name,'reason':'expected stdout','stdout_sha256':result['stdout_sha256']}
        if oracle is None:oracle=result
        if result!=oracle:return {'status':'output_mismatch','arm':name,'reason':'reference oracle','got':result,'expected':oracle}
        return {'arm':name,'value':measurement,'output':result,'stderr':r.stderr.decode(errors='replace')}
    def attempt(name,phase,rnd=None,rss=False):
        if doc['arm_status'][name]['status']!='ok':return None
        try:sample=run(name,rss)
        except FileNotFoundError as error:
            sample={'status':'output_mismatch','arm':name,'reason':'missing output artifact','detail':str(error)}
        if rnd is not None:sample['round']=rnd
        if 'status' in sample:
            doc['arm_status'][name]={**sample,'phase':phase}
            checkpoint('arm_failure',doc['arm_status'][name])
            return None
        checkpoint(phase,sample)
        return sample
    attempt(spec.get('oracle',names[0]),'oracle')
    if relative_policy is None:
        assert 'zig-fast' in names and 'mylang-zero-rc' in names
        pilots=[]
        for rnd in range(a.calibration_warmups):
            attempt('zig-fast','calibration_warmup',rnd)
        for rnd in range(a.calibration_rounds):
            sample=attempt('zig-fast','calibration_sample',rnd)
            if sample is not None:pilots.append(sample)
        reference=statistics.median([row['value'] for row in pilots]) if len(pilots)==a.calibration_rounds else None
        relative_policy={'reference_arm':'zig-fast','factor':a.zig_factor,'calibration_samples':pilots,
                         'calibration_warmups':a.calibration_warmups,'reference_median_seconds':reference,
                         'absolute_ceiling_seconds':a.guest_timeout,
                         'budget_seconds':min(a.guest_timeout,a.zig_factor*reference) if reference is not None else None,
                         'applies_to':'checked-ownership uninstrumented warmup and wall invocations; RSS uses the absolute ceiling',
                         'interpretation':'A censor exceeded the calibrated wall-time budget; it is not an exact runtime or measured median ratio.'}
        if reference is None:
            doc['arm_status']['mylang-zero-rc']={'status':'reference_unavailable','phase':'calibration','reason':'Zig ReleaseFast calibration did not complete'}
    doc['relative_timeout_policy']=relative_policy
    checkpoint('relative_timeout_policy',relative_policy)
    for rnd in range(a.warmups):
        for name in names:attempt(name,'warmup',rnd)
    for rnd in range(a.round_start,a.round_start+a.rounds):
        for name in names if rnd%2==0 else list(reversed(names)):
            sample=attempt(name,'wall_sample',rnd)
            if sample is not None:doc['wall_samples'].append(sample)
    for rnd in range(a.rss_rounds):
        for name in names if rnd%2==0 else list(reversed(names)):
            sample=attempt(name,'rss_sample',rnd,True)
            if sample is not None:doc['rss_samples'].append(sample)
    doc['summary']={}
    for name in names:
        doc['summary'][name]={}
        for field,unit in [('wall_samples','seconds'),('rss_samples','child_peak_rss_kib')]:
            values=[v['value'] for v in doc[field] if v['arm']==name]
            if not values:continue
            doc['summary'][name][unit]={'median':statistics.median(values),'min':min(values),'max':max(values),'samples':values}
    assert identities==identities_now()
    doc['loadavg_end']=os.getloadavg()
    doc['finished_utc']=datetime.datetime.now(datetime.timezone.utc).isoformat()
    a.output.write_text(json.dumps(doc,indent=2)+'\n')
    print(json.dumps(doc['summary'],indent=2))
if __name__=='__main__':main()
