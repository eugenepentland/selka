#!/usr/bin/env python3
import hashlib,json,statistics,sys
from pathlib import Path
root=Path(__file__).resolve().parent
r=json.loads((root/'results.json').read_text());identity=json.loads((root/'identity.json').read_text());sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
assert len(r['patches'])==4 and len(r['runs'])==16 and r['cpu']==3
for p in r['patches']:
 assert p['symbol']=='myl_rc_list_plain_ready' and p['after_hex']=='b801000000c3'
 if '--live' in sys.argv:
  old=Path(p['source']);new=Path(p['diagnostic']);assert sha(old)==p['source_sha256'] and sha(new)==p['diagnostic_sha256']
  a=bytearray(old.read_bytes());offset=p['file_offset'];assert a[offset:offset+6].hex()==p['before_hex'];a[offset:offset+6]=bytes.fromhex(p['after_hex']);assert bytes(a)==new.read_bytes()
for key,med in r['medians'].items():
 rows=[s for s in r['runs'] if s['workload']==key];assert len(rows)==8 and len({s['stdout'] for s in rows})==1
 for side in ['before','diagnostic']:
  raw=[s for s in rows if s['side']==side and not s.get('counted')];assert len(raw)==3
  values=[]
  for s in raw:
   fields=next(x.split(',') for x in s['stderr'].splitlines() if ',cpu_core/instructions/u,' in x)
   assert s['status']==0 and float(fields[4])==100 and int(fields[0])==s['instructions'];values.append(int(fields[0]))
  assert med[side]==statistics.median(values)
 counts=[s['counts'] for s in rows if s.get('counted')];assert len(counts)==2 and counts[0]==counts[1] and not counts[0]['saturated']
 assert med['diagnostic_over_before']==med['diagnostic']/med['before']
if '--live' in sys.argv:
 assert sha(Path(identity['original_compiler']))==identity['compiler_sha256']
 assert sha(Path(identity['llvm_binary']))==identity['llvm_binary_sha256']
print('verified 12 deliberately unchecked QBE diagnostic samples, four count runs and exact six-byte patches; NOT production acceptance')
