"""Isolated flat-retain candidate versus immutable joined 636 production."""
import gzip,hashlib,importlib.util,json,os,statistics,subprocess
from pathlib import Path
root=Path.cwd();work=root/'.tmp-mut-argument/flat-retain-measure';work.mkdir(exist_ok=True)
control=root/'.tmp-mut-argument/joined-flat-measure';baseline=json.loads((control/'results.json').read_text())
compiler=root/'.tmp-mut-argument/flat-retain-candidate/bin/mylang'
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
os.environ['PC_WORK']=str(work);os.environ['TMPDIR']=str(work)
spec=importlib.util.spec_from_file_location('pc',root/'experiments/perf-gc-dict-20260925/scripts/pc.py');pc=importlib.util.module_from_spec(spec);spec.loader.exec_module(pc)
pc.LOX_PORT=control/'lox-guest';pc.LOX_BENCH=root.parent/'d9-rc-performance/.tmp-rc-performance/lox/bench'
programs=baseline['identity']['programs'];identity={'before':baseline['identity'],'after_compiler':str(compiler),'after_compiler_sha256':sha(compiler),'cpu':2,'production_source_sha256':sha(root/'src/native_rc_values.c')}
path=work/'results.json';result=json.loads(path.read_text()) if path.exists() else {'identity':identity,'builds':{},'samples':{},'counts':{}}
assert result['identity']==identity
def save():path.write_text(json.dumps(result,indent=2)+'\n')
def run(command,cwd=root,env=None):return subprocess.run(command,cwd=cwd,env=pc.clean_env() if env is None else env,capture_output=True,check=True,timeout=3600)
def receipt(spec):return {k:({n:v for n,v in v.items() if n.startswith('MYLANG_')} if k=='env' else str(v) if isinstance(v,Path) else v) for k,v in spec.items()}
def verify(program,spec,done):
 if program['kind']=='schematic':assert done.stdout in (b'',b'0\n') and not (spec['issue'].exists() and spec['issue'].read_bytes()) and sha(spec['svg'])==pc.SCHEMATIC_SVG[program['case']]
 else:assert done.stdout==Path(program['expected_path']).read_bytes()
if 'declared' not in result:
 command,cwd=pc.emit_command(programs[0],str(compiler));done=run([str(root/'scripts/build-slot.sh'),'build',*command,'--rc-runtime'],cwd)
 (work/'schematic-emitted.json.gz').write_bytes(gzip.compress(done.stdout,mtime=0));result['declared']=pc.declared_of(done.stdout)
 assert result['declared']==baseline['declared'];save()
for backend in ('qbe','llvm'):
 for key in ('schematic','lox'):
  program=next(p for p in programs if p['build_key']==key)
  for mode in ('production','stats'):
   label=f'{key}-{backend}-{mode}';binary=work/label
   if label in result['builds']:assert sha(binary)==result['builds'][label]['sha256'];continue
   command,cwd=pc.build_command(program,str(compiler),backend,binary,work/'cache')
   command=[str(root/'scripts/build-slot.sh'),'build',*command,'--keep-symbols','--rc-runtime'+('=stats' if mode=='stats' else '')]
   done=run(command,cwd);result['builds'][label]={'command':command,'cwd':cwd,'stderr':done.stderr.decode(),'sha256':sha(binary),'manifest':json.loads(Path(str(binary)+'.qbe-manifest.json').read_text())};save();print('built',label,flush=True)
 for program in programs:
  label=program['id']+'|'+backend;key=program['build_key']+'-'+backend+'-production'
  binaries={'before':control/key,'after':work/key};assert sha(binaries['before'])==baseline['builds'][key]['sha256']
  entry=result['samples'].setdefault(label,{'runs':{},'samples':[]});save()
  for arm,binary in binaries.items():entry['runs'][arm]=receipt(pc.run_spec(program,binary,label.replace('/','-')+'-'+arm,result['declared']))
  completed={(s['repetition'],s['arm']) for s in entry['samples']}
  for repetition in range(3):
   for arm in (('before','after') if repetition%2==0 else ('after','before')):
    if (repetition,arm) in completed:continue
    spec=pc.run_spec(program,binaries[arm],label.replace('/','-')+'-'+arm,result['declared'])
    command=['taskset','-c','2','perf','stat','-x,','-e','instructions:u,cycles:u','--',*spec['argv']];done=run(command,spec['cwd'],spec['env']);verify(program,spec,done)
    counters={f[2]:int(f[0]) for line in done.stderr.decode().splitlines() if len(f:=line.split(','))>2 and f[0].isdigit()}
    entry['samples'].append({'arm':arm,'repetition':repetition,'command':command,'stdout':done.stdout.decode(),'stderr':done.stderr.decode(),'counters':counters});save();print('sample',label,arm,repetition,counters,flush=True)
  entry['medians']={arm:statistics.median(s['counters']['cpu_core/instructions/u'] for s in entry['samples'] if s['arm']==arm) for arm in binaries}
  entry['after_over_before']=entry['medians']['after']/entry['medians']['before'];save();print('median',label,entry['after_over_before'],flush=True)
  if label not in result['counts']:
   spec=pc.run_spec(program,work/f"{program['build_key']}-{backend}-stats",label.replace('/','-')+'-stats',result['declared']);done=run(['taskset','-c','2',*spec['argv']],spec['cwd'],spec['env']);verify(program,spec,done)
   counts=[json.loads(line.split(' ',1)[1]) for line in done.stderr.decode().splitlines() if line.startswith('MYLANG_RC_COUNTS ')]
   assert counts==[baseline['counts'][label]['counts']]
   result['counts'][label]={'before_receipt':str(control/'results.json'),'run':receipt(spec),'stdout':done.stdout.decode(),'stderr':done.stderr.decode(),'counts':counts[0]};save();print('counts',label,counts[0],flush=True)
