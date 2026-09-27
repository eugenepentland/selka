from pathlib import Path
import gzip,hashlib,json,subprocess
R=Path.cwd();W=R/'.tmp-readonly';O=R/'experiments/d9-rc-readonly-calls-20260927'
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
def packed(source,name):
    target=O/name;target.parent.mkdir(parents=True,exist_ok=True)
    target.write_bytes(gzip.compress(Path(source).read_bytes(),mtime=0))
def copy(source,name):
    target=O/name;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(Path(source).read_bytes())
schematic=json.loads((W/'performance/results.json').read_text());lox=json.loads((W/'lox-control/results.json').read_text())
assert schematic['complete'] and lox['complete']
packed(W/'performance/results.json','schematic.json.gz');packed(W/'lox-control/results.json','lox.json.gz')
packed(W/'controls.json','controls-initial.json.gz');packed(W/'traps.json','traps-release-refusal.json.gz')
packed(W/'traps-debug.json','traps-debug.json.gz');packed(W/'cache-control/results.json','cache-control.json.gz')
copy(W/'emit-audit.json','emit-audit.json')
for p in W.glob('*-emitted.json'):
    packed(p,'emissions/'+p.name+'.gz')
for p in (W/'cache-control').glob('*.json'):
    if p.name!='results.json':packed(p,'cache/'+p.name+'.gz')
for p in (W/'cache-control').glob('*.my'):copy(p,'cache/'+p.name)
for p in W.glob('*.log'):packed(p,'logs/'+p.name+'.gz')
for p in W.glob('*.py'):copy(p,'scripts/'+p.name)
for p in W.glob('traps*.my'):copy(p,'controls/'+p.name)
copy(R/'tests/lang/rc_readonly_calls.my','controls/rc_readonly_calls.my')
before=R.parent/'d9-rc-performance/.tmp-rc-performance/ownership-joined-e5d47d20/results.json'
packed(before,'accepted-gc.json.gz')
delta=subprocess.check_output(['git','diff','--binary','HEAD'],cwd=R)
(O/'source.patch.gz').write_bytes(gzip.compress(delta,mtime=0))
for name in ('src/rc_readonly_calls.zig','src/rc_readonly_calls_test.zig','tests/lang/rc_readonly_calls.my'):copy(R/name,'new-source/'+name)
source_files=('src/qbe.zig','src/qbe_rc_cache.zig','src/rc_readonly_body.zig','src/rc_readonly_calls.zig')
live={str(R/name):sha(R/name) for name in source_files}
for row in schematic['compilers'].values():live[row['path']]=row['sha256']
for group in (schematic['builds'],lox['builds']):
    for row in group.values():
        cmd=row['cmd'];binary=cmd[cmd.index('-o')+1];live[binary]=row['sha256']
# Counted Lox argv is taskset,-c,2,binary,--engine=vm,script.
for row in lox['counted'].values():live[row['run']['argv'][3]]=row['binary_sha256']
for row in lox['samples'].values():live[row['runs']['before']['argv'][0]]=row['before_binary_sha256']
for p,digest in live.items():assert sha(p)==digest,p
identity={'compiler_mode':'Debug','before_source':'e5d47d20 (compiler identical to c90c84be)',
          'candidate_base':subprocess.check_output(['git','rev-parse','HEAD'],cwd=R,text=True).strip(),
          'candidate_patch_sha256':hashlib.sha256(delta).hexdigest(),'live_files':live,
          'source_files':{name:sha(R/name) for name in source_files},'gc_reference':str(before),'gc_reference_sha256':sha(before)}
(O/'identity.json').write_text(json.dumps(identity,indent=2)+'\n')
manifest={str(p.relative_to(O)):sha(p) for p in sorted(O.rglob('*')) if p.is_file() and p.name!='archive-sha256.json'}
(O/'archive-sha256.json').write_text(json.dumps(manifest,indent=2)+'\n')
print('archived',len(manifest),'files')
