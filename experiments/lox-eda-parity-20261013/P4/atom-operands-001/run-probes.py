#!/usr/bin/env python3
"""Paired public checked-AST probes; locations/call traces may change, traps may not."""
import json,os,re,subprocess,hashlib
from pathlib import Path
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[3]
SCRATCH=ROOT/'.tmp/lox-eda-parity/P4/atom-operands-001'
MODES=('valid','literal','logical','logical-short-invalid-rhs','expr-negative','expr-end','expr-and-stack','stack-end','literal-stack-end','stack-negative','stack-empty','slot-negative','slot-end','slot-and-stack','hops-negative','invalid-handle','invalid-kind','kind-and-stack','global-missing')
ACCEPTED={'valid','literal','logical','logical-short-invalid-rhs','expr-negative','stack-negative','slot-negative','hops-negative'}
rows=[]
def normalize(raw):
 text=raw.decode(errors='replace')
 first=re.search(r'error\[([^]]+)\]: ([^\n]+)',text)
 trap=re.search(r'\x1eMYLANG-TRAP (\{[^\n]+\})',text)
 return {'category':first[1] if first else None,'message':first[2] if first else None,'trap':json.loads(trap[1]) if trap else None}
for mode in MODES:
 pair={}
 for arm in ('baseline','candidate'):
  binary=SCRATCH/('probe-'+arm)/'atom-probe';command=[str(binary),mode]
  run=subprocess.run(command,env=dict(os.environ,MYL_CORE_LEAKCHECK='1'),capture_output=True,timeout=30)
  folder=HERE/'probes';folder.mkdir(exist_ok=True)
  (folder/(mode+'.'+arm+'.stdout')).write_bytes(run.stdout);(folder/(mode+'.'+arm+'.stderr')).write_bytes(run.stderr)
  pair[arm]={'command':command,'returncode':run.returncode,'stdout':run.stdout.decode(errors='replace'),'normalized_stderr':normalize(run.stderr),'binary_sha256':hashlib.sha256(binary.read_bytes()).hexdigest()}
 comparable=lambda row:{k:row[k] for k in ('returncode','stdout','normalized_stderr')}
 passed=comparable(pair['baseline'])==comparable(pair['candidate'])
 assert pair['baseline']['returncode']==0 if mode in ACCEPTED else pair['baseline']['returncode']!=0
 rows.append({'mode':mode,'passed':passed,'arms':pair});(HERE/'probe-results.json').write_text(json.dumps(rows,indent=2)+'\n')
 assert passed,(mode,pair)
print('PASS',len(rows),'paired public AST/negative/bounds/order controls')
