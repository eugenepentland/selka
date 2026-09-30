#!/usr/bin/env bash
set -euo pipefail
export TMPDIR="$PWD/.tmp" ZIG_GLOBAL_CACHE_DIR="$PWD/.zig-global-cache" RC_QUICK_CPUS=2,3,10,11
phase_b_dest=$PWD/.tmp/phase-b-fresh-a5-pinned-control
test ! -e "$phase_b_dest"
mkdir -p "$phase_b_dest"
for phase_b_size in dev full smoke; do
 python3 experiments/rc-perf-20260927/quick.py measure --tag m17-codex --size "$phase_b_size" --jobs 4 --out "$phase_b_dest/results-$phase_b_size.json" > "$phase_b_dest/measure-$phase_b_size.log" 2>&1
 cat "$phase_b_dest/measure-$phase_b_size.log"
done
python3 - <<'PY'
from pathlib import Path
import hashlib,json,os
p=Path('.tmp/phase-b-fresh-a5-pinned-control');old=Path('.tmp/phase-b-fresh-a5-control');q=Path('.tmp-rc-quick');sha=lambda f:hashlib.sha256(f.read_bytes()).hexdigest()
i=json.loads((old/'identity.json').read_text());assert os.environ['RC_QUICK_CPUS']=='2,3,10,11';i.update(measurement_cpus=os.environ['RC_QUICK_CPUS'],measurement_cpu_source='Explicit export in recorded runner, inherited by quick.py',runner_sha256=sha(Path('.tmp/run-phase-b-pinned-control.sh')))
assert sha(q/'compilers/m17-codex/bin/mylang')==i['compiler_sha256']
for n,h in i['binaries'].items():assert sha(q/'bin/m17-codex'/n)==h,n
(p/'identity.json').write_text(json.dumps(i,indent=2)+'\n');receipt={'identity_sha256':sha(p/'identity.json'),'sizes':{}}
for size in ['dev','full','smoke']:
 c=json.loads((p/f'results-{size}.json').read_text());a=json.loads((q/f'results-m17-codex-{size}.json').read_text());assert not c['failures'] and len(c['rows'])==86;A={(r['id'],r['arm']):r for r in a['rows']};assert len(A)==86
 moves=[]
 for r in c['rows']:
  o=A[(r['id'],r['arm'])];assert r['gc']==o['gc'];move=(r['rc']/o['rc']-1)*100;assert abs(move)<=1; moves.append(move)
 receipt['sizes'][size]={'matching_output_pairs':86,'gc_denominators_unchanged':True,'summary':c['summary'],'results_sha256':sha(p/f'results-{size}.json'),'maximum_absolute_control_movement_percent':max(map(abs,moves))}
accepted=json.loads(Path('.tmp/a5/accepted-gc-verification.json').read_text());assert sha(q/'gc-builds.json')==accepted['manifest_sha256']
for n,h in accepted['binary_sha256'].items():assert sha(q/'bin/gc'/n)==h,n
assert sha(q/'gc-cache.json')=='d2580b2f6327db8f1a30006074be7871f0b0545cb2fe1ea149b3539aceb650de'
receipt['environment']={'RC_QUICK_CPUS':os.environ['RC_QUICK_CPUS'],'inherited_by_quick_py':True};receipt['artifacts_sha256']={f.name:sha(f) for f in p.glob('*.log')};receipt['runner_sha256']=i['runner_sha256'];(p/'receipt.json').write_text(json.dumps(receipt,indent=2)+'\n');print(json.dumps(receipt,indent=2))
PY
