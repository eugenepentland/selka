from pathlib import Path
import os,importlib.util,json,subprocess,hashlib,statistics,re
root=Path.cwd();w=root/'.tmp-schematic-audit';w.mkdir(exist_ok=True)
os.environ.update(PC_WORK=str(w),TMPDIR=str(w/'tmp'),ZIG_LOCAL_CACHE_DIR=str(w/'bench-zig-cache'))
spec=importlib.util.spec_from_file_location('pc',root/'experiments/perf-gc-dict-20260925/scripts/pc.py');pc=importlib.util.module_from_spec(spec);spec.loader.exec_module(pc)
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
compilers={'before':root.parent/'d9-rc-integration/.tmp-rc/install-field-frame-span/bin/mylang','after':w/'install-final/bin/mylang'}
programs=[p for p in pc.programs() if p['kind']=='schematic'];assert len(programs)==3
r={'base':'e926d1e13bf61ae3125102b46309225ca963a38d','compiler_sha256':{k:sha(p) for k,p in compilers.items()},'builds':[],'checks':[],'runs':[],'il':{}}
def save():(w/'measure.json').write_text(json.dumps(r,indent=2)+'\n')
def balance(c):
 assert not c['saturated'] and c['heap_allocate']==c['retire'] and c['owner_acquire']+c['heap_allocate']==c['owner_release'] and c['hold_acquire']==c['hold_release'],c
for arm,compiler in compilers.items():
 cmd,cwd=pc.emit_command(programs[0],str(compiler));cmd=[str(root/'scripts/build-slot.sh'),'build',*cmd,'--rc-runtime'];d=subprocess.run(cmd,cwd=cwd,env=pc.clean_env(),capture_output=True,text=True);assert d.returncode==0,d.stderr
 (w/f'{arm}-emitted.json').write_text(d.stdout);j=json.loads(d.stdout);declared=pc.declared_of(d.stdout.encode());r['il'][arm]={'command':cmd,'sha256':sha(w/f'{arm}-emitted.json'),'counts':{}}
 for f in j['functions']:
  if f['name'] in ('layout::partPin','layout::depth','layout::innerPin'):
   r['il'][arm]['counts'][f['name']]={name:len(re.findall(r'call \$'+name+r'\b',f['il'])) for name in ('myl_rc_native_loan','myl_rc_native_retain','myl_rc_native_take')}
 for backend in ('qbe','llvm'):
  for counted in (True,False):
   binary=w/f'schematic-{arm}-{backend}-{int(counted)}';cmd,cwd=pc.build_command(programs[0],str(compiler),backend,binary,w/f'cache-{arm}');cmd=[str(root/'scripts/build-slot.sh'),'build',*cmd,'--keep-symbols',('--rc-runtime=stats' if counted else '--rc-runtime')]
   d=subprocess.run(cmd,cwd=cwd,env=pc.clean_env(),capture_output=True,text=True)
   b={'arm':arm,'backend':backend,'counted':counted,'command':cmd,'cwd':cwd,'exit':d.returncode,'stderr':d.stderr};r['builds'].append(b);save();assert d.returncode==0,b
   b.update(binary_sha256=sha(binary),manifest=json.loads(Path(str(binary)+'.qbe-manifest.json').read_text()));assert b['manifest']['backend']==backend
   for prog in programs:
    run=pc.run_spec(prog,binary,f'{arm}-{backend}-{counted}',declared);c=pc.check(prog,run);c.update(arm=arm,backend=backend,counted=counted,case=prog['case']);r['checks'].append(c);save();assert c['ok'],c
    if counted:
     c['counts']=json.loads(next(line.removeprefix('MYLANG_RC_COUNTS ') for line in c['stderr'].splitlines() if line.startswith('MYLANG_RC_COUNTS ')));balance(c['counts']);save();print('counts',arm,backend,prog['case'],c['counts'],flush=True)
    else:
     for repeat in range(3):
      cmd=['taskset','-c','3','perf','stat','--no-scale','-x,','-e','cpu_core/instructions/u','--',*run['argv']]
      d=subprocess.run(cmd,cwd=run['cwd'],env=run['env'],capture_output=True,text=True,timeout=30)
      x={'arm':arm,'backend':backend,'case':prog['case'],'repeat':repeat,'command':cmd,'exit':d.returncode,'stderr':d.stderr,'stdout':d.stdout,'svg_sha256':sha(run['svg'])};r['runs'].append(x);save();assert d.returncode==0 and x['svg_sha256']==pc.SCHEMATIC_SVG[prog['case']],x
      fields=next(line.split(',') for line in d.stderr.splitlines() if ',cpu_core/instructions/u,' in line);x.update(instructions=int(fields[0]),event_runtime_ns=int(fields[3]),percent_running=float(fields[4]));save()
 print('DONE',arm,r['il'][arm]['counts'],flush=True)
for backend in ('qbe','llvm'):
 for case in ('fixture','changed-net','changed-value'):
  m={arm:statistics.median(x['instructions'] for x in r['runs'] if x['arm']==arm and x['backend']==backend and x['case']==case) for arm in compilers};print('MEDIAN',backend,case,m,m['after']/m['before'],flush=True)
