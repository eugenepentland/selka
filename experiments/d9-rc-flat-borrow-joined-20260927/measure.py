"""Joined runtime/compiler diagnostic: exact schematic inputs and full Lox N10."""
import gzip,hashlib,importlib.util,json,os,shutil,statistics,subprocess
from pathlib import Path
root=Path.cwd();work=root/'.tmp-mut-argument/joined-flat-measure';work.mkdir(exist_ok=True)
base=root.parent/'d9-rc-performance/.tmp-rc-performance'
compiler=root.parent/'d9-rc-integration/.tmp-rc/install-flat-borrow-loops/bin/mylang'
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
assert sha(compiler)=='32e272cf75968d2fe913f636739d4b11d83701448e515f057dfa87f1ed8cba46'
baseline=json.loads((base/'gc-builds.json').read_text());assert baseline['compiler_sha256']=='8c8134078fc56eeb468e65d229db2480d99c39458b044e976d604bf64de69478'
port=base/'lox/benchmarks/lox/ports/mylang';own_port=work/'lox-guest';own_port.mkdir(exist_ok=True)
for p in port.rglob('*'):
 if p.is_file() and (p.suffix=='.my' or p.name=='mylang.json'):
  target=own_port/p.relative_to(port);target.parent.mkdir(parents=True,exist_ok=True)
  if target.exists():assert target.read_bytes()==p.read_bytes()
  else:shutil.copyfile(p,target)
os.environ['PC_WORK']=str(work);os.environ['TMPDIR']=str(work)
spec=importlib.util.spec_from_file_location('pc',root/'experiments/perf-gc-dict-20260925/scripts/pc.py');pc=importlib.util.module_from_spec(spec);spec.loader.exec_module(pc)
pc.LOX_PORT=own_port;pc.LOX_BENCH=base/'lox/bench'
programs=[p for p in pc.programs() if p['kind']=='schematic' or p['id']=='lox/vm/binary_trees'];assert len(programs)==4
inputs=list(pc.SCHEMATIC_GUEST.rglob('*.my'))+[pc.SCHEMATIC_PROVIDER]+list(own_port.rglob('*.my'))
inputs += [pc.SCHEMATIC_PROJECTS/p['case']/d for p in programs if p['kind']=='schematic' for d in pc.SCHEMATIC_DOCS]
lox=next(p for p in programs if p['kind']=='lox');assert lox['size']==10
inputs += [pc.LOX_BENCH/'sizes.json',pc.LOX_BENCH/'scripts/binary_trees.lox',Path(lox['expected_path'])]
identity={'compiler':str(compiler),'compiler_sha256':sha(compiler),'source':'636524b81562e30285b15e297078fac24ffccb58','gc_manifest_sha256':sha(base/'gc-builds.json'),'inputs':{str(p):sha(p) for p in inputs},'cpu':2,'programs':programs}
path=work/'results.json'
result=json.loads(path.read_text()) if path.exists() else {'identity':identity,'builds':{},'samples':{},'counts':{},'profiles':{}}
assert result['identity']==identity
def save():path.write_text(json.dumps(result,indent=2)+'\n')
def run(cmd,cwd=root,env=None,timeout=3600):return subprocess.run(cmd,cwd=cwd,env=pc.clean_env() if env is None else env,capture_output=True,check=True,timeout=timeout)
def receipt(spec):return {k:({n:v for n,v in v.items() if n.startswith('MYLANG_')} if k=='env' else str(v) if isinstance(v,Path) else v) for k,v in spec.items()}
def verify(program,spec,done):
 if program['kind']=='schematic':assert done.stdout in (b'',b'0\n') and not (spec['issue'].exists() and spec['issue'].read_bytes()) and sha(spec['svg'])==pc.SCHEMATIC_SVG[program['case']]
 else:assert done.stdout==Path(program['expected_path']).read_bytes()
if 'declared' not in result:
 cmd,cwd=pc.emit_command(programs[0],str(compiler));done=run([str(root/'scripts/build-slot.sh'),'build',*cmd,'--rc-runtime'],cwd)
 (work/'schematic-emitted.json.gz').write_bytes(gzip.compress(done.stdout,mtime=0));result['declared']=pc.declared_of(done.stdout);save()
for backend in ('qbe','llvm'):
 for key in ('schematic','lox'):
  program=next(p for p in programs if p['build_key']==key)
  for mode in ('production','stats'):
   label=f'{key}-{backend}-{mode}';binary=work/label
   if label in result['builds']:assert sha(binary)==result['builds'][label]['sha256'];continue
   cmd,cwd=pc.build_command(program,str(compiler),backend,binary,work/'cache');cmd=[str(root/'scripts/build-slot.sh'),'build',*cmd,'--keep-symbols','--rc-runtime'+('=stats' if mode=='stats' else '')]
   done=run(cmd,cwd);result['builds'][label]={'command':cmd,'cwd':cwd,'stderr':done.stderr.decode(),'sha256':sha(binary),'manifest':json.loads(Path(str(binary)+'.qbe-manifest.json').read_text())};save();print('built',label,flush=True)
 for program in programs:
  label=program['id']+'|'+backend
  binaries={'gc':base/'bin/gc'/f"{program['build_key']}.{backend}",'rc':work/f"{program['build_key']}-{backend}-production"}
  assert sha(binaries['gc'])==baseline['builds'][f"{program['build_key']}.{backend}"]['sha256']
  entry=result['samples'].setdefault(label,{'runs':{},'samples':[]});save()
  for arm,binary in binaries.items():
   spec=pc.run_spec(program,binary,label.replace('/','-')+'-'+arm,result['declared'] if arm=='rc' else baseline['schematic_declared']);entry['runs'][arm]=receipt(spec)
  completed={(s['repetition'],s['arm']) for s in entry['samples']}
  for repetition in range(3):
   for arm in (('gc','rc') if repetition%2==0 else ('rc','gc')):
    if (repetition,arm) in completed:continue
    spec=pc.run_spec(program,binaries[arm],label.replace('/','-')+'-'+arm,result['declared'] if arm=='rc' else baseline['schematic_declared'])
    cmd=['taskset','-c','2','perf','stat','-x,','-e','instructions:u,cycles:u','--',*spec['argv']];done=run(cmd,spec['cwd'],spec['env']);verify(program,spec,done)
    counters={f[2]:int(f[0]) for line in done.stderr.decode().splitlines() if len(f:=line.split(','))>2 and f[0].isdigit()}
    entry['samples'].append({'arm':arm,'repetition':repetition,'command':cmd,'stdout':done.stdout.decode(),'stderr':done.stderr.decode(),'counters':counters});save();print('sample',label,arm,repetition,counters,flush=True)
  medians={arm:statistics.median(s['counters']['cpu_core/instructions/u'] for s in entry['samples'] if s['arm']==arm) for arm in binaries}
  entry['medians']=medians;entry['rc_over_gc']=medians['rc']/medians['gc'];save();print('median',label,entry['rc_over_gc'],flush=True)
  if label not in result['counts']:
   spec=pc.run_spec(program,work/f"{program['build_key']}-{backend}-stats",label.replace('/','-')+'-stats',result['declared']);done=run(['taskset','-c','2',*spec['argv']],spec['cwd'],spec['env']);verify(program,spec,done)
   counts=[json.loads(line.split(' ',1)[1]) for line in done.stderr.decode().splitlines() if line.startswith('MYLANG_RC_COUNTS ')]
   assert len(counts)==1;counts=counts[0];assert counts['heap_allocate']==counts['retire'] and counts['heap_allocate']+counts['owner_acquire']==counts['owner_release'] and counts['hold_acquire']==counts['hold_release']
   result['counts'][label]={'run':receipt(spec),'stdout':done.stdout.decode(),'stderr':done.stderr.decode(),'counts':counts};save();print('counts',label,counts,flush=True)
