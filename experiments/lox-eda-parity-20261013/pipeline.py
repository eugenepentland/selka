#!/usr/bin/env python3
"""Isolated all-case parity preparation and timing; scheduler alone owns admission."""
import argparse, hashlib, json, os, pathlib, shutil, statistics, subprocess, sys
P=pathlib.Path
HERE=P(__file__).resolve().parent

def sha(p): return hashlib.sha256(P(p).read_bytes()).hexdigest()
def save(p,v):
    p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(v,indent=2)+'\n')
def tree(p): return {str(x.relative_to(p)):sha(x) for x in sorted(P(p).rglob('*')) if x.is_file()}
def assert_pins(pins):
    for path,digest in pins.items(): assert sha(path)==digest, ('identity changed',path)
def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('command',choices=['prepare','schedule','count','report'])
    p.add_argument('--root',type=P,required=True);p.add_argument('--compiler',type=P,required=True)
    p.add_argument('--install',type=P,required=True);p.add_argument('--attempt',required=True)
    p.add_argument('--prior-root',type=P,required=True);p.add_argument('--lox-build',type=P,required=True);p.add_argument('--eda-build',type=P,required=True)
    p.add_argument('--case',action='append');p.add_argument('--cpu',type=int,default=8);p.add_argument('--freeze',type=P);p.add_argument('--resume',action='store_true')
    a=p.parse_args();a.root=a.root.resolve();a.prior_root=a.prior_root.resolve()
    dest=a.root/'experiments/lox-eda-parity-20261013/attempts'/a.attempt
    work=a.root/'.tmp/lox-eda-parity/P6'/a.attempt
    if a.command=='prepare':
        assert not dest.exists();dest.mkdir(parents=True);work.mkdir(parents=True,exist_ok=False)
        builds={app:json.loads(path.read_text()) for app,path in [('lox',a.lox_build),('eda',a.eda_build)]}
        pins={str(a.compiler.resolve()):sha(a.compiler)}
        pins.update({str(a.install.resolve()/name):v for name,v in tree(a.install.resolve()).items()})
        for app,path in [('lox',a.lox_build),('eda',a.eda_build)]:
            b=builds[app];assert b['compiler_sha256']==sha(a.compiler)
            pins[str(path.resolve())]=sha(path)
            for source in b['sources'].values():
                for name,digest in source['files'].items():
                    file=P(source['root'])/name;assert sha(file)==digest;pins[str(file)]=digest
            for binary in b['binaries'].values(): assert binary['status']=='ok' and sha(binary['path'])==binary['sha256']
        recovery=json.loads((a.prior_root/'input-recovery/manifest.json').read_text())['entries']
        prior_specs=sorted((a.prior_root/'specs').glob('*.json'));assert len(prior_specs)==60
        for original in prior_specs:
            spec=json.loads(original.read_text());app=spec['cell'].split('/')[0];old_arms=spec['arms']
            def relocate(path):
                if path not in recovery:return path
                entry=recovery[path];candidate=P(entry['path'])
                if not candidate.exists():candidate=a.prior_root/'input-recovery/expected'/candidate.name
                assert sha(candidate)==entry['sha256']
                target=dest/'expected'/candidate.name;target.parent.mkdir(exist_ok=True)
                if target.exists(): assert sha(target)==entry['sha256']
                else:shutil.copyfile(candidate,target)
                return str(target)
            spec['files']=[relocate(path) for path in spec['files']]
            if 'expected_stdout' in spec:spec['expected_stdout']=relocate(spec['expected_stdout'])
            previous=old_arms['mylang-zero-rc']
            prior_build_path=a.prior_root/'build'/app/'build-receipt.json'
            prior_build=json.loads(prior_build_path.read_text());entry=prior_build['binaries']['zero-rc']
            assert previous[0]==entry['path'] and sha(previous[0])==entry['sha256']
            pins[str(prior_build_path)]=sha(prior_build_path)
            spec['arms']={'zig-fast':old_arms['zig-fast'],'mylang-before':previous,
                          'mylang-zero-rc':[builds[app]['binaries']['zero-rc']['path'],*previous[1:]]}
            if builds[app].get('before_same_compiler',{}).get('status')=='ok':
                same=builds[app]['before_same_compiler'];assert sha(same['path'])==same['sha256']
                spec['arms']['mylang-before-same-compiler']=[same['path'],*previous[1:]]
            spec['oracle']='zig-fast';spec['relative_timeout_arms']=[n for n in spec['arms'] if n.startswith('mylang-')]
            if spec.get('out_dir'):
                old=spec['out_dir'];new=str(work/'outputs'/original.stem);spec['out_dir']=new
                spec['arms']={n:[v.replace(old,new) for v in argv] for n,argv in spec['arms'].items()}
                spec['artifacts']=[v.replace(old,new) for v in spec.get('artifacts',[])]
            for path in spec['files']+[argv[0] for argv in spec['arms'].values()]: pins[path]=sha(path)
            for folder in spec.get('identity_dirs',[]):
                pins.update({str(P(folder)/n):v for n,v in tree(P(folder)).items()})
            spec['files']=sorted(set(spec['files'])|set(pins))
            spec['prior_spec']={'path':str(original),'sha256':sha(original)}
            save(dest/'specs'/original.name,spec)
        counts={g:len(list((dest/'specs').glob(g+'-*.json'))) for g in ['tree','vm','eda']};assert counts=={'tree':13,'vm':13,'eda':34}
        save(dest/'pins.json',pins);save(dest/'configuration.json',{'compiler':str(a.compiler),'installation':str(a.install),'installation_files':tree(a.install),'prior_root':str(a.prior_root),'counts':counts,'harness_sha256':sha(__file__)})
        print(dest);return
    pins=json.loads((dest/'pins.json').read_text());assert_pins(pins)
    specs=sorted((dest/'specs').glob('*.json'))
    if a.case:
        specs=[s for s in specs if s.stem in a.case];assert len(specs)==len(set(a.case)), 'unknown case'
    if a.command=='schedule':
        assert a.cpu in os.sched_getaffinity(0)
        if not a.case:
            assert a.freeze and a.freeze.exists(), 'coordinator freeze required for full benchmark'
            freeze=json.loads(a.freeze.read_text());assert freeze['pins_sha256']==sha(dest/'pins.json')
        env=dict(os.environ);env.pop('MYLANG_COUNTERS',None);env.pop('MYL_CORE_LEAKCHECK',None)
        for spec_path in specs:
            base=json.loads(spec_path.read_text());prior=None
            # One paired round per lease bounds expensive cases; initial calibration alone can exceed 60s.
            chunks=[(0,0,2,0)]+[(i,1,0,0) for i in range(9)]+[(9+i,0,0,1) for i in range(3)]
            for index,(start,rounds,warmups,rss) in enumerate(chunks):
                stem=f'{spec_path.stem}.chunk{index:02d}';output=dest/'runtime'/(stem+'.json');generated=dest/'runtime'/(stem+'.spec.json')
                if output.exists():
                    assert a.resume;data=json.loads(output.read_text());assert_pins(data['identities']);assert data['spec']['arms']==base['arms'];prior=output;continue
                assert not generated.exists(), ('interrupted chunk requires explicit inspection',generated)
                spec=dict(base)
                if prior:spec['prior_receipt']=str(prior)
                save(generated,spec)
                cmd=[str(a.root/'scripts/build-slot.sh'),'timing',sys.executable,'-B',str(HERE/'measure.py'),str(generated),str(output),'--cpu',str(a.cpu),'--round-start',str(start),'--rounds',str(rounds),'--warmups',str(warmups),'--rss-rounds',str(rss),'--calibration-rounds','3','--calibration-warmups','0','--guest-timeout','120']
                with (dest/'runtime'/(stem+'.log')).open('w') as log:subprocess.run(cmd,cwd=a.root,env=env,stdout=log,stderr=subprocess.STDOUT,check=True)
                prior=output
        return
    if a.command=='count':
        for spec in specs:
            raw=json.loads(spec.read_text());app=raw['cell'].split('/')[0]
            candidate=json.loads((a.lox_build if app=='lox' else a.eda_build).read_text())
            previous=json.loads((a.prior_root/'build'/app/'build-receipt.json').read_text())
            entries={'mylang-zero-rc':candidate['binaries']['zero-rc-counted'],'mylang-before':previous['binaries']['zero-rc-counted']}
            runtime=dest/'runtime'/(spec.stem+'.chunk12.json');statuses=json.loads(runtime.read_text())['arm_status']
            included=[n for n in entries if statuses[n]['status']=='ok']
            counted=dest/'counted';counted.mkdir(exist_ok=True)
            if included:
                runner=a.prior_root.parent/'lox-eda-zero-rc-20261012/bench/run-counted.py'
                cmd=[str(a.root/'scripts/build-slot.sh'),'timing',sys.executable,'-B',str(runner),'--output',str(counted),'--cpu',str(a.cpu),'--guest-timeout','120']
                for n in included:
                    e=entries[n];assert sha(e['path'])==e['sha256'];cmd+=['--arm',n+'='+e['path']]
                count_spec=dest/'count-specs'/spec.name
                count_document=dict(raw);count_document['arms']={**raw['arms'],'zig-safe':raw['arms']['zig-fast']}
                save(count_spec,count_document)
                cmd.append(str(count_spec))
                summary=counted/(spec.stem+'.counted.spec.summary.json')
                assert not summary.exists(), 'explicit counter recovery required'
                with (counted/(spec.stem+'.log')).open('w') as log:subprocess.run(cmd,cwd=a.root,stdout=log,stderr=subprocess.STDOUT,check=True)
            save(counted/(spec.stem+'.eligibility.json'),{'runtime_receipt':str(runtime),'runtime_receipt_sha256':sha(runtime),'included':included,'skipped':{n:statuses[n] for n in entries if n not in included},'binaries':entries})
        return
    rows={}
    for spec in specs:
        receipts=[json.loads(x.read_text()) for x in sorted((dest/'runtime').glob(spec.stem+'.chunk[0-9][0-9].json'))]
        assert len(receipts)==13, ('incomplete cell',spec.stem)
        arms={}
        for name in json.loads(spec.read_text())['arms']:
            wall=[x['value'] for r in receipts for x in r['wall_samples'] if x['arm']==name];rss=[x['value'] for r in receipts for x in r['rss_samples'] if x['arm']==name]
            status=receipts[-1]['arm_status'][name]['status']
            if status=='ok':assert len(wall)==9 and len(rss)==3
            for r in receipts:assert_pins(r['identities'])
            arms[name]={'status':status,'wall_seconds':statistics.median(wall) if status=='ok' else None,'rss_kib':statistics.median(rss) if status=='ok' else None,'wall_samples':wall,'rss_samples':rss}
        candidate=arms['mylang-zero-rc'];zig=arms['zig-fast'];ratio=candidate['wall_seconds']/zig['wall_seconds'] if candidate['status']==zig['status']=='ok' else None
        counter_path=dest/'counted'/(spec.stem+'.counted.spec.summary.json')
        counter=json.loads(counter_path.read_text()) if counter_path.exists() else None
        if counter:
            for n,row in counter['arms'].items():
                if row.get('metrics') is not None:
                    assert row['metrics']['live_bytes_at_exit']==0
                    assert row['metrics']['runtime_retains']==row['metrics']['runtime_releases']==row['metrics']['compiler_retains']==row['metrics']['compiler_releases']==0
                    assert json.loads(P(row['counter_path']).read_text())==row['counters']
        rows[spec.stem]={'counters':counter,'arms':arms,'candidate_over_zig_fast':ratio,'parity_pass':ratio is not None and ratio<=1.0}
    save(dest/'parity-report.json',{'cells':rows,'all_cases_pass':len(rows)==60 and all(r['parity_pass'] for r in rows.values()),'scope':len(rows),'counter_note':'Counters are separate instrumented runs; runtime and RSS do not imply managed traffic, peak, exit-live or RC counts.'})
    assert_pins(pins)
if __name__=='__main__':main()
