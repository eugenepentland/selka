#!/usr/bin/env python3
"""Verify/freeze completed source-only qualification receipts, including v1 refusal."""
from pathlib import Path
from collections import Counter
import gzip,hashlib,json,re
lane=Path(__file__).resolve().parents[2]
here=Path(__file__).resolve().parent
work=lane/'.tmp-lox-vm-bytecode-20261003'
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
read=lambda name:json.loads((work/name).read_text())
sources=json.loads((here/'sources.json').read_text())
files=lambda d:{str(p.relative_to(d)):sha(p) for p in sorted(d.rglob('*')) if p.is_file()}
summary={'compiler_sha256':'d14a704083bcc5f5174932a751f7d9dda73100dbd62403626b42b52436cad040',
         'qbe_sha256':'99ad919d70ad582dee6202b045bd53e1ab18fec356de98849610f49983756d63',
         'variants':{},'provider_execution':'directory commands omit --cases; provider=""; driver_cases.json structural preservation only',
         'performance':'none; generated-code diagnostics only'}
raw_paths={'base.json','static-final.json','static-v1.json','exact-control-helper-static.json','shape-v3-static.json',
           'control-emission-receipt.json','octets-v1-build.json','octets-qualification.json',
           'native/completed.json','native/observations.json','native/constant-255-boundary.json','native/rc-native-stress-refusals.json',
           'gc-builds.json','argument-overflow-v1/observations.json','argument-overflow-v1/slot-observations.json'}
for label,tag in [('octets-v2','v2'),('octets-shape-v3','v3')]:
    source=work/label
    assert files(source)==sources[label]['source37'] and len(files(source))==37
    build=read(label+'-build.json');tests=read(label+'-qualification.json');gc=read(tag+'-gc/gc-builds.json');native=read(tag+'-native/completed.json')
    assert all(x['verified_after'] for x in [build,tests,gc,native])
    assert build['source_sha256']==tests['source_sha256']==gc['source37']==native['before']['candidate37']==files(source)
    assert native['before']['candidate37']==native['after']['candidate37']
    assert native['before']['control37']==native['after']['control37']==sources['control37']
    assert native['before']['artifacts_sha256']==native['after']['artifacts_sha256']
    for receipt in [build,tests,gc]:
        assert receipt['compiler_sha256']==summary['compiler_sha256'] and receipt['qbe_sha256']==summary['qbe_sha256']
    expected={p.stem+'::'+m for p in source.glob('*.my') for m in re.findall(r'^public def (test_\w+)\(',p.read_text(),re.M)}
    assert len(expected)==88
    assert len(tests['runs'])==4
    for row in tests['runs']:
        assert row['status']==0 and row['summaries']==['88 passed, 0 cached, 0 failed, 0 skipped, 0 dropped across 10 programs']
        log=Path(row['log']);assert sha(log)==row['log_sha256']
        names=re.findall(r'^passed (\S+)$',log.read_text(),re.M)
        assert len(names)==88 and set(names)==expected
        raw_paths.add(str(log.relative_to(work)))
    for row in build['runs']+gc['runs']:
        assert row['status']==0
        if 'binary' in row:assert sha(row['binary'])==row['binary_sha256']
    observation=read(tag+'-native/observations.json')
    assert len(observation['samples'])==1192 and len(observation['unrun'])==80
    assert all(r['actual']==r['expected'] for r in observation['samples'])
    arguments=read(tag+'-native/argument-limits.json')
    assert len(arguments['pairs'])==192 and all(r['actual']==r['expected'] for r in arguments['pairs'])
    assert native['bounded_observations']==1192 and native['boundary_observations']==12
    assert native['argument_limit_pairs']==192 and native['rc_native_stress_refusal_pairs']==8
    summary['variants'][label]={'source':str(source),'public_fresh':352,'public_names':sorted(expected),
        'native_bounded':1192,'native_mode_counts':native['mode_counts'],'operand255_pairs':12,
        'argument_limit_pairs':192,'rc_native_stress_refusal_pairs':8,'native_smoke_unrun':80,
        'rc_builds':build,'gc_builds':gc,'source37':files(source),'overlay_sha256':sha(here/(label+'.patch'))}
    raw_paths.update([label+'-build.json',label+'-qualification.json',tag+'-gc/gc-builds.json'])
    raw_paths.update(str(p.relative_to(work)) for p in (work/(tag+'-native')).glob('*.json'))
# The initial variant is explicitly rejected: its strict byte cast interrupted Lox argument error recovery.
failed=read('argument-overflow-v1/slot-observations.json')
summary['rejected_variant']='octets-v1: >255 argument count causes native checked-cast trap after Lox diagnostic; use corrected v2/v3 only'
payload={'raw_files':{name:{'sha256':sha(work/name),'text':(work/name).read_text()} for name in sorted(raw_paths)}}
text=json.dumps(payload,sort_keys=True,separators=(',',':')).encode()
archive=here/'receipts.json.gz';assert not archive.exists()
archive.write_bytes(gzip.compress(text,mtime=0))
summary['evidence']={'archive_sha256':sha(archive),'raw_json_sha256':hashlib.sha256(text).hexdigest(),'raw_file_count':len(raw_paths)}
(here/'qualification.json').write_text(json.dumps(summary,indent=2)+'\n')
print('Verified/frozen corrected v2+v3, all37/ELFs, 704 public fresh, 2384 bounded native plus separate boundaries/recovery/refusals')
