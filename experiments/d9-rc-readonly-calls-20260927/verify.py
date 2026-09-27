#!/usr/bin/env python3
"""Independently verify archived plain-result composition receipts."""
from pathlib import Path
import argparse,gzip,hashlib,json,statistics

HERE=Path(__file__).resolve().parent
def read(name):
    p=HERE/name
    return json.loads(gzip.decompress(p.read_bytes()) if p.suffix=='.gz' else p.read_bytes())
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def balanced(n):
    assert not n['saturated'] and n['owner_limit']==n['hold_limit']==0
    assert n['hold_acquire']==n['hold_release']
    assert n['heap_allocate']==n['retire']
    assert n['owner_release']==n['owner_acquire']+n['heap_allocate']
def raw_count(row):
    assert row['status']==0
    found=[]
    for line in row['stderr'].splitlines():
        fields=line.split(',')
        if len(fields)<5 or 'instructions' not in fields[2] or 'cpu_atom' in fields[2]:continue
        assert fields[0].isdigit() and float(fields[4])==100.0
        found.append(int(fields[0]))
    assert len(found)==1 and found[0]==row['instructions'] and found[0]>0
    return found[0]
def backend(manifest):
    assert manifest['backend'] in ('qbe','llvm')
    if manifest['backend']=='llvm':assert str(manifest['optimization'])=='3' and manifest['lto'] and not manifest['thin_lto']
def samples(data):
    assert data['complete'] and data['diagnostic_only'] and not data['rss_measured']
    total=0
    for row in data['samples'].values():
        for side in ('before','after'):
            rows=row['observations'][side];assert len(rows)==3
            assert statistics.median(raw_count(r) for r in rows)==row['medians'][side]
            assert row['checks'][side]['ok'] and row['checks'][side]['status']==0
            total+=len(rows)
        assert row['after_before']==row['medians']['after']/row['medians']['before']
        assert row['after_gc']==row['medians']['after']/row['accepted_gc']
    for row in data['counted'].values():
        assert row['check']['ok'] and row['check']['status']==0
        parsed=[json.loads(s.split(' ',1)[1]) for s in row['check']['stderr'].splitlines() if s.startswith('MYLANG_RC_COUNTS ')]
        assert parsed==[row['counts']];balanced(row['counts'])
    for row in data['builds'].values():
        assert row['ok'];backend(row['manifest'])
    return total
def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--live',action='store_true');args=parser.parse_args()
    for name,digest in read('archive-sha256.json').items():assert sha(HERE/name)==digest,name
    schematic=read('schematic.json.gz');lox=read('lox.json.gz')
    assert len(schematic['samples'])==6 and len(schematic['counted'])==12
    assert len(lox['samples'])==2 and len(lox['counted'])==4
    assert samples(schematic)+samples(lox)==48
    accepted=read('accepted-gc.json.gz')
    for key,row in schematic['samples'].items():assert row['accepted_gc']==accepted['samples'][key]['medians']['gc']['instructions']
    for key,row in lox['samples'].items():assert row['accepted_gc']==accepted['samples']['lox/vm/binary_trees|'+key]['medians']['gc']['instructions']
    for row in schematic['samples'].values():assert row['checks']['before']['svg_sha256']==row['checks']['after']['svg_sha256']
    for row in lox['samples'].values():assert row['checks']['before']['stdout_sha256']==row['checks']['after']['stdout_sha256']
    controls=read('controls-initial.json.gz')
    assert len(controls['runs'])==8 and all(r['status']==0 for r in controls['runs'])
    for r in controls['runs']:
        if r['runtime']=='rc':balanced(r['counts'])
    for b in ('qbe','llvm'):
        rows=[r for r in controls['builds'] if r['runtime']=='gc' and r['backend']==b]
        assert len(rows)==2 and rows[0]['binary_sha256']==rows[1]['binary_sha256']
    assert controls['builds'][-1]['status']!=0 and 'E_MAIN' in controls['builds'][-1]['stderr']
    traps=read('traps-debug.json.gz');assert traps['complete'] and len(traps['runs'])==16
    for r in traps['runs']:
        assert r['status']==1 and r['expected_trap'] in r['stderr'];balanced(r['counts'])
    for b in ('qbe','llvm'):
        for case in ('bounds','overflow','steps','frames'):
            rows=[r for r in traps['runs'] if r['backend']==b and r['case']==case]
            cleaned=['\n'.join(s for s in r['stderr'].splitlines() if not s.startswith('MYLANG_RC_COUNTS ')) for r in rows]
            assert len(rows)==2 and cleaned[0]==cleaned[1] and rows[0]['stdout']==rows[1]['stdout']
    cache=read('cache-control.json.gz');assert cache['complete'] and len(cache['emissions'])==6 and len(cache['runs'])==4
    for state in ('plain','changed','allocated'):
        manifests=[read('cache/'+state+'-'+side+'.json.gz') for side in ('warm','cold')]
        il=[{f['name']:f['il'] for f in m['functions']} for m in manifests]
        assert il[0]==il[1]
        for name in ('selected','middle'):assert ('call $myl_qbe_rc_frame_enter' in il[0][name])==(state=='allocated')
    for r in cache['runs']:assert r['status']==4;balanced(r['counts'])
    audit=read('emit-audit.json');assert audit['complete']
    assert [r['name'] for r in audit['changed']['schematic']]==['layout::nearest']
    assert {r['name'] for r in audit['changed']['lox']}=={'table::get','resolver::resolve_local'}
    identity=read('identity.json')
    if args.live:
        for p,digest in identity['live_files'].items():assert sha(p)==digest,p
    print('Verified48 unscaled instruction samples,16 counted workload runs,48 guest assertions,16 exact Debug traps, warm/cold cache invalidation and unchanged GC binaries.')
if __name__=='__main__':main()
