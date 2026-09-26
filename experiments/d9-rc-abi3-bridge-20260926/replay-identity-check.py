import base64,importlib.util,json,subprocess
from pathlib import Path
from unittest.mock import patch
s=importlib.util.spec_from_file_location('replay','experiments/d9-rc-golden-replay-20260926/run.py');m=importlib.util.module_from_spec(s);s.loader.exec_module(m)
w=Path('.tmp-schematic/abi3-bridge/mock-replay').resolve();w.mkdir(exist_ok=True)
case={'id':'synthetic/counter-contract','source':'def main() -> int:\n    return 0\n','options':[],'expected':{'returncode':0,'stdout':base64.b64encode(b'0\n').decode(),'stderr':''}}
counts={'version':1,'runtime':'rc-v3-counting','saturated':False,'heap_allocate':0,'retire':0,'owner_acquire':0,'owner_release':0,'hold_acquire':0,'hold_release':0}
for version,wanted in [('rc-v3-counting',True),('rc-v2-counting',False)]:
 counts['runtime']=version
 run=subprocess.CompletedProcess([],0,b'0\n',b'MYLANG_RC_COUNTS '+json.dumps(counts).encode()+b'\n')
 with patch.object(m.subprocess,'run',return_value=run):
  _,row=m.execute(Path('/unused'),w,'qbe',case,'rc-v3-counting')
 assert row['matched'] and row['balanced'] and row['runtime_matches']==wanted and not row['missing_required_counters']
 print(version,'accepted' if wanted else 'rejected')
with patch.object(m.subprocess,'run',return_value=subprocess.CompletedProcess([],0,b'0\n',b'')):
 _,row=m.execute(Path('/unused'),w,'qbe',case,'rc-v3-counting')
assert row['missing_required_counters']
print('successful guest without counters rejected')
case['options']=['--legacy-sharing']
with patch.object(m.subprocess,'run',return_value=subprocess.CompletedProcess([],0,b'0\n',b'')):
 _,row=m.execute(Path('/unused'),w,'qbe',case,'rc-v3-counting')
assert row['runtime_matches'] and not row['missing_required_counters']
print('explicit legacy GC without counters accepted')
