from pathlib import Path
import gzip,hashlib,json,subprocess
R=Path.cwd();W=R/'.tmp-managed-readonly';O=R/'experiments/d9-rc-readonly-managed-calls-20260927'
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
def packed(source,name):
 target=O/name;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(gzip.compress(Path(source).read_bytes(),mtime=0))
def copy(source,name):
 target=O/name;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(Path(source).read_bytes())
d=json.loads((W/'performance/results.json').read_text());assert d['complete']
packed(W/'performance/results.json','schematic.json.gz')
for name in ('controls','controls-after','controls-debug','controls-bytes','split-controls','traps','baseline-llvm-fresh'):
 packed(W/(name+'.json'),name+'.json.gz')
packed(W/'cache-control/results.json','cache-control.json.gz')
for p in (W/'cache-control').glob('*.json'):
 if p.name!='results.json':packed(p,'cache/'+p.name+'.gz')
for p in (W/'cache-control').glob('*.my'):copy(p,'cache/'+p.name)
for p in W.glob('*emitted.json'):packed(p,'emissions/'+p.name+'.gz')
for name in ('emit-audit.json','emit-bytes-audit.json','frozen-source.json'):copy(W/name,name)
for p in W.glob('*.log'):packed(p,'logs/'+p.name+'.gz')
for p in W.glob('*.py'):copy(p,'scripts/'+p.name)
for p in W.glob('*.my'):copy(p,'controls/'+p.name)
for p in W.glob('*.bytecode.txt'):copy(p,'controls/'+p.name)
for name in ('rc_readonly_bytes.my','rc_readonly_managed_calls.my'):copy(R/'tests/lang'/name,'controls/'+name)
accepted=Path(d['accepted_gc_receipt']['path']);assert sha(accepted)==d['accepted_gc_receipt']['sha256']
packed(accepted,'accepted-gc.json.gz')
packed(W/'frozen-source.patch','source.patch.gz')
frozen=json.loads((W/'frozen-source.json').read_text())
live={str(R/p):h for p,h in frozen['files'].items()}
for p in frozen['files']:copy(R/p,'source/'+p)
for row in d['compilers'].values():live[row['path']]=row['sha256']
for row in d['builds'].values():
 cmd=row['cmd'];binary=cmd[cmd.index('-o')+1];live[binary]=row['sha256']
for name in ('controls','controls-after','controls-debug','controls-bytes','split-controls','traps'):
 data=json.loads((W/(name+'.json')).read_text())
 for b in data['builds']:
  if 'binary_sha256' not in b:continue
  cmd=b['command'];live[cmd[cmd.index('-o')+1]]=b['binary_sha256']
for p,h in live.items():assert sha(p)==h,p
identity={'compiler_mode':'Debug','before_source':frozen['base'],'candidate_base':frozen['base'],
 'candidate_source_patch_sha256':sha(W/'frozen-source.patch'),'candidate_compiler_sha256':frozen['compiler_sha256'],
 'source_files':frozen['files'],'live_files':live,'accepted_gc_receipt':d['accepted_gc_receipt'],
 'known_failure':'Combined managed guest LLVM ReleaseFast frame-map mismatch occurs before and after, also in fresh before cache. Split ReleaseFast and combined Debug pass.',
 'source_note':'Production and test snapshot is frozen; later report/archive edits do not change compiler source.'}
(O/'identity.json').write_text(json.dumps(identity,indent=2)+'\n')
manifest={str(p.relative_to(O)):sha(p) for p in sorted(O.rglob('*')) if p.is_file() and p.name!='archive-sha256.json'}
(O/'archive-sha256.json').write_text(json.dumps(manifest,indent=2)+'\n')
print('archived',len(manifest),'files')
