#!/usr/bin/env python3
"""One cell per exclusive lease. Uninstrumented wall time and separate child RSS.
Spec: {arms:{name:[argv...]}, oracle:name, files:[input paths], artifacts:[paths]}.
Invoke via scripts/build-slot.sh timing; do not nest admission.
"""
import argparse, datetime, hashlib, json, os, pathlib, shutil, statistics, subprocess, tempfile, time

def digest(p):
    return hashlib.sha256(pathlib.Path(p).read_bytes()).hexdigest()

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('spec',type=pathlib.Path);p.add_argument('output',type=pathlib.Path)
    p.add_argument('--cpu',type=int,default=8);p.add_argument('--rounds',type=int,default=9)
    p.add_argument('--round-start',type=int,default=0);p.add_argument('--warmups',type=int,default=2)
    p.add_argument('--rss-rounds',type=int,default=3)
    a=p.parse_args();assert not a.output.exists()
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
    doc={'started_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
         'host':os.uname()._asdict() if hasattr(os.uname(),'_asdict') else list(os.uname()),
         'loadavg_start':os.getloadavg(),'spec':spec,'spec_sha256':digest(a.spec),'cpu':a.cpu,'identities':identities,
         'warmups':a.warmups,'round_start':a.round_start,'rounds':a.rounds,'wall_samples':[],'rss_samples':[]}
    checkpoint('header',{k:v for k,v in doc.items() if k not in ['wall_samples','rss_samples']})
    oracle=None
    def run(name,rss=False):
        nonlocal oracle
        argv=arms[name];measurement=None
        if spec.get('out_dir'):
            shutil.rmtree(spec['out_dir'],ignore_errors=True)
        if rss:
            with tempfile.NamedTemporaryFile() as f:
                r=subprocess.run(['/usr/bin/time','-f','%M','-o',f.name,*argv],capture_output=True,cwd=spec.get('cwd'))
                measurement=int(pathlib.Path(f.name).read_text().strip())
        else:
            start=time.perf_counter_ns();r=subprocess.run(argv,capture_output=True,cwd=spec.get('cwd'))
            measurement=(time.perf_counter_ns()-start)/1e9
        if r.returncode:raise RuntimeError((name,r.returncode,r.stderr[-2000:]))
        result={'stdout_sha256':hashlib.sha256(r.stdout).hexdigest(),
                'artifacts':{f:digest(f) for f in spec.get('artifacts',[])}}
        if spec.get('golden_dir'):
            def tree(d):
                return {str(f.relative_to(d)):digest(f) for f in pathlib.Path(d).rglob('*') if f.is_file()}
            got=tree(pathlib.Path(spec['out_dir']));want=tree(pathlib.Path(spec['golden_dir']))
            assert got==want,(name,'golden mismatch',got,want)
            result['golden_tree']=got
        if spec.get('expected_stdout'):
            assert r.stdout==pathlib.Path(spec['expected_stdout']).read_bytes(),(name,'stdout oracle mismatch')
        if oracle is None:oracle=result
        assert result==oracle,(name,result,oracle)
        return {'arm':name,'value':measurement,'output':result,'stderr':r.stderr.decode(errors='replace')}
    checkpoint('oracle',run(spec.get('oracle',names[0])))
    for _ in range(a.warmups):
        for name in names:checkpoint('warmup',run(name))
    for rnd in range(a.round_start,a.round_start+a.rounds):
        for name in names if rnd%2==0 else list(reversed(names)):
            sample={'round':rnd,**run(name)}
            doc['wall_samples'].append(sample);checkpoint('wall_sample',sample)
    for rnd in range(a.rss_rounds):
        for name in names if rnd%2==0 else list(reversed(names)):
            sample={'round':rnd,**run(name,True)}
            doc['rss_samples'].append(sample);checkpoint('rss_sample',sample)
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
