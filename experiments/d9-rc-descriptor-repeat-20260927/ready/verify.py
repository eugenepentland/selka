"""Verify archived lookup experiment without executing guests or rebuilding."""
import gzip,hashlib,json
from pathlib import Path
here=Path(__file__).resolve().parent
read=lambda name:json.loads(gzip.decompress((here/name).read_bytes()))
x=read('measurements.json.gz');assert x['identity']['base']=='d1d8b3c46ac41e832410a03aad49a5a6a1a54b07'
assert len(x['builds'])==32 and len(x['samples'])==12 and len(x['counts'])==24
inputs=json.loads((here/'inputs.json').read_text())
for label,row in x['builds'].items():
 backend='llvm' if '-llvm-' in label else 'qbe';assert row['manifest']['backend']==backend
 if backend=='llvm':assert row['manifest']['optimization']=='3' and row['manifest']['lto'] and not row['manifest']['thin_lto']
for label,row in x['samples'].items():
 assert len(row['samples'])==6 and {(r['side'],r['repetition']) for r in row['samples']}=={(s,i) for s in ('before','after') for i in range(3)}
 for run in row['samples']:
  program=label.split('|')[0]
  assert run['stdout']==inputs['stdout'][program] if program in inputs['stdout'] else run['stdout'] in ('','0\n')
  for line in run['stderr'].splitlines():
   f=line.split(',')
   if len(f)>4 and f[2]=='cpu_core/instructions/u':assert f[0].isdigit() and float(f[4])==100, (label,line)
 before=x['counts'][label+'|before']['counts'];after=x['counts'][label+'|after']['counts'];assert before==after
 assert not before['saturated'] and before['heap_allocate']==before['retire'] and before['owner_acquire']+before['heap_allocate']==before['owner_release'] and before['hold_acquire']==before['hold_release']
for key,row in x['emitted'].items():
 if key.endswith('-before'):assert row['sha256']==x['emitted'][key.removesuffix('-before')+'-after']['sha256']
v=read('validation.json.gz');assert len(v['runs'])==20 and all(row['status']==0 and '0 cached, 0 failed' in row['stdout'] for row in v['runs'])
layout=json.loads((here/'layout.json').read_text());assert layout['before']['stdout']==layout['after']['stdout'] and layout['counting-before']['stdout']==layout['counting-after']['stdout']
print('Verified32 builds,72 samples,24 exact balanced counts,20 paired guest rows, emission and layout identity.')
