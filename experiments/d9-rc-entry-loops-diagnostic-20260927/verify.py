#!/usr/bin/env python3
"""Verify the explicitly partial 31-program diagnostic without rebuilding."""
from pathlib import Path
import argparse, gzip, hashlib, json, math, statistics
ROOT = Path(__file__).resolve().parent
sha = lambda path: hashlib.sha256(Path(path).read_bytes()).hexdigest()
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--results', type=Path)
p.add_argument('--live', action='store_true')
a = p.parse_args()
if (ROOT/'files.json').exists():
    for name, info in json.loads((ROOT/'files.json').read_text()).items():
        value=gzip.decompress((ROOT/(name+'.gz')).read_bytes())
        assert len(value)==info['bytes'] and hashlib.sha256(value).hexdigest()==info['sha256']
raw = a.results.read_bytes() if a.results else gzip.decompress((ROOT/'results.json.gz').read_bytes())
r = json.loads(raw)
assert r['diagnostic_only'] and r['complete_diagnostic']
i = r['identity']; assert i['cpu']==11 and len(i['programs'])==31
gc_raw=gzip.decompress((ROOT/'gc-builds.json.gz').read_bytes())
prior_raw=gzip.decompress((ROOT/'prior-joined30.json.gz').read_bytes())
assert hashlib.sha256(gc_raw).hexdigest()==i['baseline_manifest_sha256']
assert hashlib.sha256(prior_raw).hexdigest()==i['prior_receipt_sha256']
gc=json.loads(gc_raw); prior=json.loads(prior_raw)
assert gc['compiler_sha256']==i['accepted_gc_compiler_sha256']
programs={v['id']:v for v in i['programs']}
assert all(i['inputs'][path]==digest for path,digest in gc['inputs'].items())
assert sum(x['kind']=='lox' for x in i['programs'])==1
lox = next(x for x in i['programs'] if x['kind']=='lox')
assert lox['id']=='lox/vm/binary_trees' and lox['size']==10
assert len(r['builds'])==116 and len(r['samples'])==len(r['counted'])==62
assert i['driver_sha256']==sha(ROOT/'run.py')
for key,b in r['builds'].items():
    assert b['ok']
    m=b['manifest']['value']; arm=key.split('.')[1]
    assert m['backend']==arm
    if arm=='llvm': assert m['optimization']=='3' and m['lto'] and not m['thin_lto']
for key,row in r['samples'].items():
    assert all(v['ok'] for v in row['checks'].values())
    program,backend=key.rsplit('|',1)
    assert row['binaries']['gc']['sha256']==gc['builds'][programs[program]['build_key']+'.'+backend]['sha256']
    assert row['checks']['gc']['stdout_sha256']==row['checks']['rc']['stdout_sha256']
    if program!='lox/vm/binary_trees':
        h=row['historical_joined30']; old=prior['samples'][key]
        assert h['source']==prior['identity']['compiler_commit'] and h['cpu']==prior['identity']['cpu']
        assert h['instruction_ratio']==old['instruction_ratio']
        assert h['rc_instructions']==old['medians']['rc']['instructions']
        assert h['current_rc_over_prior_rc']==row['medians']['rc']['instructions']/h['rc_instructions']
    for side in ['gc','rc']:
        obs=row['observations'][side]
        assert len(obs['perf'])==len(obs['rss'])==3
        for sample in obs['perf']:
            assert sample['ok'] and sample['status']==0
            event=[v for v in sample['events'] if v['metric']=='instructions']
            assert len(event)==1 and event[0]['enabled_percent']==100.0
            assert sample['instructions']==event[0]['count']
            raw_events=[v.split(',') for v in sample['stderr'].splitlines() if 'instructions' in v and v.split(',')[0].isdigit()]
            assert len(raw_events)==1 and int(raw_events[0][0])==sample['instructions'] and float(raw_events[0][4])==100
        assert all(v['ok'] and v['status']==0 and v['peak_rss_kb']>0 for v in obs['rss'])
        assert row['medians'][side]['instructions']==statistics.median(v['instructions'] for v in obs['perf'])
        assert row['medians'][side]['rss_kb']==statistics.median(v['peak_rss_kb'] for v in obs['rss'])
    ratio=row['medians']['rc']['instructions']/row['medians']['gc']['instructions']
    assert ratio==row['instruction_ratio']
    assert row['remaining_reduction_to_1_3']==max(0,1-1.3/ratio)
    c=r['counted'][key];n=c['counts']; assert c['check']['ok']
    assert n['runtime']=='rc-v3-counting' and not n['saturated']
    assert n['heap_allocate']==n['retire'] and n['hold_acquire']==n['hold_release']
    assert n['owner_acquire']+n['heap_allocate']==n['owner_release']
    assert c['check']['stdout_sha256']==row['checks']['rc']['stdout_sha256']
    if key.startswith('schematic/'):
        assert c['check']['svg_sha256']==row['checks']['rc']['svg_sha256']==row['checks']['gc']['svg_sha256']
    if a.live:
        for b in row['binaries'].values(): assert sha(b['path'])==b['sha256']
        assert sha(c['run']['argv'][3])==c['binary_sha256']
for program in programs:
    assert r['counted'][program+'|qbe']['counts']==r['counted'][program+'|llvm']['counts']
for nonlox,label in [(False,'summary31'),(True,'summary30')]:
    for arm in ['qbe','llvm']:
        rows=[v for k,v in r['samples'].items() if k.endswith('|'+arm) and (not nonlox or not k.startswith('lox/'))]
        s=r[label][arm]; assert s['complete'] and s['programs']==len(rows)
        assert math.isclose(s['instruction_geomean'],math.exp(statistics.mean(math.log(v['instruction_ratio']) for v in rows)),rel_tol=1e-14)
        assert s['maximum_instruction_ratio']==max(v['instruction_ratio'] for v in rows)
        assert s['rows_within_1_3']==sum(v['instruction_ratio']<=1.3 for v in rows)
        for side in ['gc','rc']: assert s['median_peak_rss_kb'][side]==statistics.median(v['medians'][side]['rss_kb'] for v in rows)
if a.live:
    assert sha(i['compiler'])==i['compiler_sha256']
    assert sha(gc['compiler'])==gc['compiler_sha256']
    for path,digest in i['inputs'].items(): assert sha(path)==digest,path
print('Verified 31-program diagnostic: 372 instruction observations at 100%, 372 separate RSS observations, 62 balanced counted runs. This is not full 43-program acceptance.')
