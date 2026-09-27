#!/usr/bin/env python3
from pathlib import Path
import gzip,json,hashlib,re,sys
p=Path(__file__).resolve().parent;r=p.parents[1];live='--live' in sys.argv
sha=lambda q:hashlib.sha256(q.read_bytes()).hexdigest()
def read(name):
 q=p/name;return json.loads(gzip.decompress(q.read_bytes()) if name.endswith('.gz') else q.read_bytes())
for name,digest in read('archive-sha256.json').items():assert sha(p/name)==digest
identity=read('identity.json');old=r/identity['measured_baseline_archive'];fixed=json.loads(gzip.decompress((old/'proof-final-builds.json.gz').read_bytes()))
assert identity['compiler']['compiler_sha256']==fixed['compiler_sha256']
if live:assert sha(Path(identity['compiler']['compiler']))==fixed['compiler_sha256']
assert sha(old/'binary_trees.tree.lox')==identity['input_sha256'] and sha(old/'expected-n10.txt')==identity['oracle_sha256']
for backend,count in (('qbe',305),('llvm',234)):
 d=read(backend+'-results.json.gz');assert len(d['runs'])==1
 original=next(x for x in fixed['builds'] if x['backend']==backend and not x['counted'])
 assert d['binary_sha256']==original['binary_sha256'] and d['input_sha256']==identity['input_sha256']
 if live:assert sha(Path(d['binary']))==d['binary_sha256'] and sha(Path(d['input']))==d['input_sha256']
 observation=d['runs'][0];assert observation['exit']==0 and observation['stdout']==(old/'expected-n10.txt').read_text()
 assert observation['attribution']=='qualitative only' and observation['lost']==0 and observation['throttle']==count
 raw=gzip.decompress((p/(backend+'.perf-raw.txt.gz')).read_bytes()).decode()
 assert len(re.findall(r': PERF_RECORD_THROTTLE\b',raw))==count and not re.search(r': PERF_RECORD_LOST\b',raw)
 assert read('branch-attribution.json.gz')[backend]['samples']==count
pairs=read('vm-read-pairs.json.gz');assert len(pairs)==13
assert sum('CallFrame' in x['type'] for x in pairs)==5 and sum('Value' in x['type'] for x in pairs)==8
for name,count in (('vm-read_byte',2),('vm-read_short',4)):
 assert gzip.decompress((p/(name+'.il.gz')).read_bytes()).decode().count('call $myl_rc_native_loan(')==count
print('verified two exact current N10 profiles; all539 samples throttled, zero lost; thirteen nonscalar VM pairs and scalar helper loans'+(' with live identities' if live else ''))
