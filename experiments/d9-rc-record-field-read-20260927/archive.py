from pathlib import Path
import gzip, hashlib, json, shutil, statistics
root=Path.cwd(); work=root/'.tmp-mut-argument/field-list-read'; out=root/'experiments/d9-rc-record-field-read-20260927';out.mkdir(exist_ok=True)
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def put(name, compress=False):
    p=work/name; q=out/(name+('.gz' if compress else ''))
    q.write_bytes(gzip.compress(p.read_bytes(),mtime=0) if compress else p.read_bytes())
for name in ('builds.json','branch-attribution.json','current-loan-sites.json','qbe-results.json','llvm-results.json','current-vm-run.il','accounted-vm-run.il','qbe-vm-run.asm','llvm-vm-run.asm','qbe.branches.txt','llvm.branches.txt','qbe.samples.txt','llvm.samples.txt','qbe.perf-raw.txt','llvm.perf-raw.txt'):
    put(name,True)
for name in ('emitted.json.gz','accounted-emitted.json.gz','interval-production.il','interval-accounted.il','build.py','measure.py','archive.py','qbe.data','llvm.data'):
    put(name)
shutil.copyfile(root/'experiments/d9-rc-plain-record-write-20260927/expected-n10.txt',out/'expected-n10.txt')
builds=json.loads((work/'builds.json').read_text())
identity={'source':builds['source'],'compiler':builds['compiler'],'compiler_sha256':builds['compiler_sha256'],'guest':builds['builds'][0]['cwd'],'sources':builds['sources'],'binaries':{r['backend']+('-stats' if r['counted'] else '-production'):{'path':r['binary'],'sha256':r['binary_sha256']} for r in builds['builds']}}
gc=json.loads((root/'experiments/d9-rc-native-type-facts-20260927/accepted-gc-observations.json').read_text())
gc['samples']={k:v for k,v in gc['samples'].items() if k.startswith('lox/vm/binary_trees|')}
(out/'accepted-gc-observations.json').write_text(json.dumps(gc,indent=2)+'\n')
gci=json.loads((root/'.tmp-mut-argument/type-facts/accepted-gc-identities.json').read_text())
(out/'accepted-gc-identities.json').write_text(json.dumps(gci,indent=2)+'\n')
summary={}
for backend in ('qbe','llvm'):
    r=json.loads((work/(backend+'-results.json')).read_text())
    samples=[x['instructions'] for x in r['runs'] if 'instructions' in x];median=statistics.median(samples)
    reference=gc['samples']['lox/vm/binary_trees|'+backend]['medians']['instructions']
    summary[backend]={'samples':samples,'median':median,'archival_accepted_gc':reference,'over_gc':median/reference,'counts':r['runs'][-1]['counts'],'profile':{k:r['runs'][0][k] for k in ['throttle','unthrottle','lost','attribution']}}
    identity['input']={'path':r['input'],'sha256':r['input_sha256']};shutil.copyfile(r['input'],out/'binary_trees.tree.lox')
(out/'identity.json').write_text(json.dumps(identity,indent=2)+'\n')
(out/'summary.json').write_text(json.dumps(summary,indent=2)+'\n')
checks={str(p.relative_to(out)):sha(p) for p in out.rglob('*') if p.is_file() and p.name not in ('archive-sha256.json','verify.py','README.md')}
(out/'archive-sha256.json').write_text(json.dumps(checks,indent=2)+'\n')
print('ARCHIVE',len(checks),'files',sum(p.stat().st_size for p in out.rglob('*') if p.is_file()))
