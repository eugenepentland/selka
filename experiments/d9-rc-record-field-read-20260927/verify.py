#!/usr/bin/env python3
"""Verify fixed-source attribution receipts; --live checks original files too."""
from pathlib import Path
import gzip, hashlib, json, re, statistics, sys
root=Path(__file__).resolve().parent; live='--live' in sys.argv
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def read(name):
    p=root/name
    return json.loads(gzip.decompress(p.read_bytes()) if name.endswith('.gz') else p.read_bytes())
def existing(path,digest):
    if live:assert sha(Path(path))==digest,path
def instructions(text):
    rows=[line.split(',') for line in text.splitlines() if ',cpu_core/instructions/u,' in line]
    assert len(rows)==1 and float(rows[0][4])==100,rows
    return int(rows[0][0])
for name,digest in read('archive-sha256.json').items():assert sha(root/name)==digest,name
identity=read('identity.json');existing(identity['compiler'],identity['compiler_sha256'])
for name,digest in identity['sources'].items():existing(Path(identity['guest'])/name,digest)
for row in identity['binaries'].values():existing(row['path'],row['sha256'])
existing(identity['input']['path'],identity['input']['sha256'])
assert sha(root/'binary_trees.tree.lox')==identity['input']['sha256']
expected=(root/'expected-n10.txt').read_text();builds=read('builds.json.gz')
assert builds['source']==identity['source'] and builds['compiler_sha256']==identity['compiler_sha256']
assert len(builds['builds'])==4
for row in builds['builds']:
    assert row['exit']==0 and row['manifest']['backend']==row['backend']
    if row['backend']=='llvm':assert row['manifest']['optimization']=='3' and row['manifest']['lto'] and not row['manifest']['thin_lto']
for key,file in [('emission','emitted.json.gz'),('accounted_emission','accounted-emitted.json.gz')]:
    assert builds[key]['exit']==0 and hashlib.sha256(gzip.decompress((root/file).read_bytes())).hexdigest()==builds[key]['sha256']
summary=read('summary.json');gc=read('accepted-gc-observations.json');allcounts=[]
gc_identity=read('accepted-gc-identities.json')
existing(gc_identity['compiler'],gc_identity['compiler_sha256'])
gc_sources={k.split('/benchmarks/lox/ports/mylang/',1)[1]:v for k,v in gc_identity['inputs'].items() if '/benchmarks/lox/ports/mylang/' in k}
assert all(gc_sources.get(k)==v for k,v in identity['sources'].items())
for backend in ['qbe','llvm']:
    result=read(backend+'-results.json.gz');assert result['source']==identity['source']
    assert result['binary_sha256']==identity['binaries'][backend+'-production']['sha256']
    assert len(result['runs'])==5
    for row in result['runs']:assert row['exit']==0 and row['stdout']==expected
    measured=[instructions(row['stderr']) for row in result['runs'] if 'instructions' in row]
    assert len(measured)==3 and measured==summary[backend]['samples']
    assert statistics.median(measured)==summary[backend]['median']
    reference=gc['samples']['lox/vm/binary_trees|'+backend]
    gc_build=gc_identity['builds']['lox.'+backend]
    existing(reference['run']['argv'][0],gc_build['sha256'])
    reference_values=[instructions(row['stderr']) for row in reference['observations']['perf']]
    assert len(reference_values)==3 and statistics.median(reference_values)==summary[backend]['archival_accepted_gc']
    assert summary[backend]['over_gc']==summary[backend]['median']/summary[backend]['archival_accepted_gc']
    row=result['runs'][-1];counts=json.loads(next(line.split(' ',1)[1] for line in row['stderr'].splitlines() if line.startswith('MYLANG_RC_COUNTS ')))
    assert counts==row['counts']==summary[backend]['counts'] and not counts['saturated']
    assert counts['heap_allocate']==counts['retire'] and counts['owner_acquire']+counts['heap_allocate']==counts['owner_release'] and counts['hold_acquire']==counts['hold_release']
    assert row['binary_sha256']==identity['binaries'][backend+'-stats']['sha256'];allcounts.append(counts)
    raw=gzip.decompress((root/(backend+'.perf-raw.txt.gz')).read_bytes()).decode()
    profile=result['runs'][0]
    for key,event in [('throttle','THROTTLE'),('unthrottle','UNTHROTTLE'),('lost','LOST')]:
        assert len(re.findall(r': PERF_RECORD_'+event+r'\b',raw))==profile[key]
    assert profile['throttle']>0 and profile['lost']==0 and profile['attribution']=='qualitative only'
assert allcounts[0]==allcounts[1]
emission=read('emitted.json.gz');vm=next(f for f in emission['functions'] if f['name']=='vm::run')
assert vm['il'].count('call $myl_rc_native_loan(')==50
pc=None;sites=[]
for number,line in enumerate(vm['il'].splitlines(),1):
    match=re.match(r' dbgloc (\d+)',line)
    if match:pc=int(match[1])-1
    if 'call $myl_rc_native_loan(' in line:sites.append({'pc':pc,'il_line':number,**vm['locations'][pc],'call':line.strip()})
assert sites==read('current-loan-sites.json.gz')
assert [r['pc'] for r in sites[2:4]]==[23,24] and all(r['line']==473 for r in sites[2:4])
print('verified: six raw median samples at 100% running, two balanced counted runs, exact compiler/input/binary identities, six archival GC samples, throttled qualitative profiles, 50 mapped emitted loan sites'+(' (live)' if live else ''))
