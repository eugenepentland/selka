#!/usr/bin/env python3
"""Untimed checksum/counter qualification; clocks are excluded from performance evidence."""
import importlib.util,json,subprocess,hashlib
from pathlib import Path
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[3]
def load(name,path):
    spec=importlib.util.spec_from_file_location(name,path);module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);return module
prepare=load('final_micro_prepare',HERE/'prepare.py')
measure=load('final_micro_validator',prepare.TOOLS/'measure.py')
pins=json.loads((HERE/'inputs.json').read_text());prepare.validate_original(pins)
build=json.loads((HERE/'builds.json').read_text())
for file,sha in build['installation_files'].items():assert prepare.digest(file)==sha
assert build['compiler_sha256']=='6842cc711ca6f6eadf2967a76ca60f57044ec06e0c9c2cf15b2834fd3cdebbaf'
dest=HERE/'untimed-controls';dest.mkdir(exist_ok=False);rows=[]
for path in sorted((HERE/'specs').glob('*.json')):
    spec=json.loads(path.read_text());expected=measure.registry.checksum(spec['case'],spec['size'],1,spec['seed'])
    assert (spec['warmups'],spec['rounds'],spec['rss_rounds'])==(3,15,3)
    assert len(spec['arms'])==7 and len(spec['counted'])==3
    for kind in ('arms','counted'):
        for name,entry in spec[kind].items():
            assert prepare.digest(entry['binary'])==entry['sha256']
            assert prepare.digest(entry['source'])==entry['source_sha256']
            argv=[entry['binary'],spec['case'],str(spec['size']),'1',str(spec['seed'])]
            env=measure.runtime_environment();tag=path.stem+'.'+kind+'.'+name
            counter=dest/(tag+'.counters.json')
            if kind=='counted':env['MYLANG_COUNTERS']=str(counter)
            result=subprocess.run(argv,env=env,capture_output=True,text=True,timeout=120)
            (dest/(tag+'.stdout')).write_text(result.stdout);(dest/(tag+'.stderr')).write_text(result.stderr)
            checked=measure.validate({'status':'ok' if result.returncode==0 else 'failed','stdout':result.stdout,'stderr':result.stderr},expected,spec['protocol'])
            row={'cell':path.stem,'kind':kind,'arm':name,'command':argv,'exit_status':result.returncode,'status':checked['status'],'expected_checksum':expected,'binary_sha256':entry['sha256'],'iterations':1,'purpose':'untimed correctness only; all clock values excluded from performance evidence'}
            if kind=='counted' and row['status']=='ok':
                metrics=measure.counters(counter);row['metrics']=metrics;row['counter_sha256']=prepare.digest(counter)
                assert metrics['live_bytes_at_exit']==0
                assert not entry.get('zero_rc') or metrics['rc_events']==metrics['unique_test']==json.loads(counter.read_text())['totals'].get('share_marks',0)==0
            rows.append(row);(HERE/'untimed-qualification.json').write_text(json.dumps(rows,indent=2)+'\n')
            assert row['status']=='ok',row
prepare.validate_original(pins)
for file,sha in build['installation_files'].items():assert prepare.digest(file)==sha
validation={'status':'two C3 builds and6 frozen specs qualified; timing held','compiler_source_commit':'91f5b5d3010893e7642a8fbee90fa910aa7fabab','compiler_sha256':build['compiler_sha256'],'entries':build['entries'],'spec_sha256':{p.name:prepare.digest(p) for p in sorted((HERE/'specs').glob('*.json'))},'untimed_runtime_controls':sum(r['kind']=='arms' for r in rows),'untimed_counted_controls':sum(r['kind']=='counted' for r in rows),'all_original_pins_unchanged':True,'installation_pins_unchanged':True}
prepare.write_new(HERE/'build-validation.json',validation)
print('PASS42 runtime+18counted untimed controls;6specs ready; no timing submitted')
