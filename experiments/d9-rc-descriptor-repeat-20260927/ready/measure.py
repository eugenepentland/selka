"""Isolated repeated descriptor lookup: exact inputs and interleaved medians."""
import gzip,hashlib,importlib.util,json,os,shutil,statistics,subprocess
from pathlib import Path
root=Path.cwd();work=root/'.tmp-mut-argument/descriptor-ready/measure';work.mkdir(exist_ok=True)
os.environ['PC_WORK']=str(work);os.environ['TMPDIR']=str(root/'.tmp-mut-argument/descriptor-ready')
spec=importlib.util.spec_from_file_location('pc',root/'experiments/perf-gc-dict-20260925/scripts/pc.py');pc=importlib.util.module_from_spec(spec);spec.loader.exec_module(pc)
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
compilers={'before':root.parent/'d9-rc-integration/.tmp-rc/install-flat-retain-joined/bin/mylang','after':root/'.tmp-mut-argument/descriptor-ready/install/bin/mylang'}
assert sha(compilers['before'])=='12a3693929913d50385248a5938fcf57694de8a3538e65f150432c998936d268'
programs=[p for p in pc.programs() if p['kind']=='schematic' or p['id'] in ('parity/micro/alloc_churn','parity/micro/list_append_sum','parity/suite/sieve')]
assert len(programs)==6
identity={'base':'d1d8b3c46ac41e832410a03aad49a5a6a1a54b07','compilers':{k:{'path':str(p),'sha256':sha(p)} for k,p in compilers.items()},'cpu':2,'programs':programs,'production_sources':{n:sha(root/'src'/n) for n in ('native_rc_shapes.c','native_rc_internal.h','native_collections.c')}}
path=work/'results.json';data=json.loads(path.read_text()) if path.exists() else {'identity':identity,'builds':{},'samples':{},'counts':{},'emitted':{}}
assert data['identity']==identity
def save():path.write_text(json.dumps(data,indent=2)+'\n')
def run(cmd,cwd=root,env=None):
 p=subprocess.run(cmd,cwd=cwd,env=pc.clean_env() if env is None else env,capture_output=True,timeout=3600)
 if p.returncode: print(p.stderr.decode(),flush=True)
 p.check_returncode();return p
def receipt(spec):return {k:({n:v for n,v in v.items() if n.startswith('MYLANG_')} if k=='env' else str(v) if isinstance(v,Path) else v) for k,v in spec.items()}
def verify(prog,spec,p):
 if prog['kind']=='schematic':assert p.stdout in (b'',b'0\n') and not (spec['issue'].exists() and spec['issue'].read_bytes()) and sha(spec['svg'])==pc.SCHEMATIC_SVG[prog['case']]
 else:assert p.stdout==Path(prog['expected_path']).read_bytes()
for prog in programs:
 key=prog['build_key']
 for side,c in compilers.items():
  label=key+'-'+side
  if label in data['emitted']:continue
  command,cwd=pc.emit_command(prog,str(c));command=[str(root/'scripts/build-slot.sh'),'build',*command,'--rc-runtime'];p=run(command,cwd)
  (work/(label+'-emitted.json.gz')).write_bytes(gzip.compress(p.stdout,mtime=0));data['emitted'][label]={'command':command,'cwd':cwd,'sha256':hashlib.sha256(p.stdout).hexdigest()};save()
  if prog['kind']=='schematic':data['declared']=pc.declared_of(p.stdout);save()
 assert data['emitted'][key+'-before']['sha256']==data['emitted'][key+'-after']['sha256']
 for backend in ('qbe','llvm'):
  for side,c in compilers.items():
   for mode in ('production','stats'):
    label=f'{key}-{side}-{backend}-{mode}';binary=work/label
    if label in data['builds']:assert sha(binary)==data['builds'][label]['sha256'];continue
    if side=='before':
     prior=root/'.tmp-mut-argument/descriptor-repeat/measure';baseline=json.loads((prior/'results.json').read_text());shutil.copy2(prior/label,binary);data['builds'][label]={**baseline['builds'][label],'reused_binary':str(prior/label)};assert sha(binary)==data['builds'][label]['sha256'];save();continue
    command,cwd=pc.build_command(prog,str(c),backend,binary,work/('cache-'+side))
    if prog['kind']=='single':command+=['--mode','ReleaseFast']
    command=[str(root/'scripts/build-slot.sh'),'build',*command,'--keep-symbols','--rc-runtime'+('=stats' if mode=='stats' else '')]
    p=run(command,cwd);data['builds'][label]={'command':command,'cwd':cwd,'stderr':p.stderr.decode(),'sha256':sha(binary),'manifest':json.loads(Path(str(binary)+'.qbe-manifest.json').read_text())};save();print('built',label,flush=True)
  label=prog['id']+'|'+backend;entry=data['samples'].setdefault(label,{'samples':[]});save();completed={(s['repetition'],s['side']) for s in entry['samples']}
  for repetition in range(3):
   for side in (('before','after') if repetition%2==0 else ('after','before')):
    if (repetition,side) in completed:continue
    binary=work/f'{key}-{side}-{backend}-production';spec=pc.run_spec(prog,binary,label.replace('/','-')+'-'+side,data.get('declared'))
    command=['taskset','-c','2','perf','stat','-x,','-e','instructions:u,cycles:u','--',*spec['argv']];p=run(command,spec['cwd'],spec['env']);verify(prog,spec,p)
    counters={f[2]:int(f[0]) for line in p.stderr.decode().splitlines() if len(f:=line.split(','))>2 and f[0].isdigit()}
    entry['samples'].append({'repetition':repetition,'side':side,'command':command,'run':receipt(spec),'stdout':p.stdout.decode(),'stderr':p.stderr.decode(),'counters':counters});save()
  entry['medians']={side:statistics.median(s['counters']['cpu_core/instructions/u'] for s in entry['samples'] if s['side']==side) for side in compilers};entry['after_over_before']=entry['medians']['after']/entry['medians']['before'];save();print('median',label,entry['medians'],entry['after_over_before'],flush=True)
  for side in compilers:
   countkey=label+'|'+side
   if countkey in data['counts']:continue
   spec=pc.run_spec(prog,work/f'{key}-{side}-{backend}-stats',label.replace('/','-')+'-'+side+'-stats',data.get('declared'));p=run(['taskset','-c','2',*spec['argv']],spec['cwd'],spec['env']);verify(prog,spec,p)
   counts=[json.loads(line.split(' ',1)[1]) for line in p.stderr.decode().splitlines() if line.startswith('MYLANG_RC_COUNTS ')];assert len(counts)==1
   data['counts'][countkey]={'run':receipt(spec),'stdout':p.stdout.decode(),'stderr':p.stderr.decode(),'counts':counts[0]};save()
  assert data['counts'][label+'|before']['counts']==data['counts'][label+'|after']['counts']
