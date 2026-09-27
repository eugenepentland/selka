"""Isolated flat-loan diagnostic using the unchanged three schematic inputs."""
import gzip,hashlib,importlib.util,json,os,statistics,subprocess
from pathlib import Path
root=Path.cwd();work=root/'.tmp-mut-argument/loan-measure';work.mkdir(exist_ok=True)
os.environ['PC_WORK']=str(work)
os.environ['TMPDIR']=str(work)
spec=importlib.util.spec_from_file_location('pc',root/'experiments/perf-gc-dict-20260925/scripts/pc.py');pc=importlib.util.module_from_spec(spec);spec.loader.exec_module(pc)
compilers={arm:root/f'.tmp-mut-argument/{name}/bin/mylang' for arm,name in [('before','retain-final'),('after','loan-candidate')]}
programs=[p for p in pc.programs() if p['kind']=='schematic'];assert len(programs)==3
identity=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
inputs=list(pc.SCHEMATIC_GUEST.rglob('*.my'))+[pc.SCHEMATIC_PROVIDER]
inputs += [pc.SCHEMATIC_PROJECTS/p['case']/d for p in programs for d in pc.SCHEMATIC_DOCS]
result={'compilers':{a:{'path':str(p),'sha256':identity(p)} for a,p in compilers.items()},'inputs':{str(p):identity(p) for p in inputs},'cpu':2,'builds':[],'runs':[],'samples':[],'medians':{}}
def save(): (work/'results.json').write_text(json.dumps(result,indent=2)+'\n')
def command(argv,cwd=root,env=None):return subprocess.run(argv,cwd=cwd,env=pc.clean_env() if env is None else env,capture_output=True,check=True)
declarations={}
for arm,compiler in compilers.items():
 cmd,cwd=pc.emit_command(programs[0],str(compiler));done=command([str(root/'scripts/build-slot.sh'),'build',*cmd,'--rc-runtime'],cwd)
 (work/f'{arm}-emitted.json.gz').write_bytes(gzip.compress(done.stdout,mtime=0));declarations[arm]=pc.declared_of(done.stdout)
for backend in ('qbe','llvm'):
 for arm,compiler in compilers.items():
  for mode in ('production','stats'):
   binary=work/f'{backend}-{arm}-{mode}'
   cmd,cwd=pc.build_command(programs[0],str(compiler),backend,binary,work/'cache');cmd=[str(root/'scripts/build-slot.sh'),'build',*cmd,'--keep-symbols','--rc-runtime'+('=stats' if mode=='stats' else '')]
   done=command(cmd,cwd);result['builds'].append({'command':cmd,'stderr':done.stderr.decode(),'sha256':identity(binary),'manifest':json.loads(Path(str(binary)+'.qbe-manifest.json').read_text())});save()
   for program in programs:
    run=pc.run_spec(program,binary,f'{backend}-{arm}-{mode}',declarations[arm]);done=command(run['argv'],run['cwd'],run['env'])
    assert done.stdout in (b'',b'0\n') and not (run['issue'].exists() and run['issue'].read_bytes())
    svg=identity(run['svg']);assert svg==pc.SCHEMATIC_SVG[program['case']]
    counts=[json.loads(line.split(' ',1)[1]) for line in done.stderr.decode().splitlines() if line.startswith('MYLANG_RC_COUNTS ')]
    result['runs'].append({'backend':backend,'arm':arm,'mode':mode,'case':program['case'],'argv':run['argv'],'env':{k:v for k,v in run['env'].items() if k.startswith('MYLANG_')},'stdout':done.stdout.decode(),'stderr':done.stderr.decode(),'svg_sha256':svg,'counts':counts});save()
   print('built',backend,arm,mode,flush=True)
 for program in programs:
  rows=[r for r in result['runs'] if r['backend']==backend and r['case']==program['case'] and r['mode']=='stats']
  assert rows[0]['counts']==rows[1]['counts'],rows
 for repetition in range(3):
  for arm in (('before','after') if repetition%2==0 else ('after','before')):
   run=pc.run_spec(programs[0],work/f'{backend}-{arm}-production',f'{backend}-{arm}-perf{repetition}',declarations[arm])
   cmd=['taskset','-c','2','perf','stat','-x,','-e','instructions:u,cycles:u','--',*run['argv']];done=command(cmd,run['cwd'],run['env']);assert identity(run['svg'])==pc.SCHEMATIC_SVG[programs[0]['case']]
   counters={f[2]:int(f[0]) for line in done.stderr.decode().splitlines() if len(f:=line.split(','))>2 and f[0].isdigit()}
   result['samples'].append({'backend':backend,'arm':arm,'command':cmd,'stderr':done.stderr.decode(),'counters':counters});save()
 medians={arm:statistics.median(s['counters']['cpu_core/instructions/u'] for s in result['samples'] if s['backend']==backend and s['arm']==arm) for arm in compilers}
 result['medians'][backend]={'instructions':medians,'after_over_before':medians['after']/medians['before']};save();print(backend,result['medians'][backend],flush=True)
