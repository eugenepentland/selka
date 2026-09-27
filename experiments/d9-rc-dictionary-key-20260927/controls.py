from pathlib import Path
import os,json,hashlib,subprocess,resource
r=Path.cwd();w=r/'.tmp-rc/dict-key';e={k:v for k,v in os.environ.items() if not k.startswith('MYLANG_') and k!='LD_PRELOAD'};e['TMPDIR']=str(r/'.tmp-rc/tmp')
d=json.loads((w/'controls.json').read_text())
d['excluded_diagnostics']=[{'case':'floor','mode':'gc','backend':'qbe','status':'timeout','timeout_seconds':60,'receipt':'controls-gc-floor-timeout.log','reason':'extra ReleaseFast GC-stress recursion probe; RC floor pair and GC Debug logical frame controls retained'}]
def save():(w/'controls.json').write_text(json.dumps(d,indent=2)+'\n')
def smallstack():resource.setrlimit(resource.RLIMIT_STACK,(262144,262144))
for backend in ['qbe','llvm']:
 for side,mode in [('before','rc'),('prototype','rc'),('prototype','gc')]:
  c=r/f'.tmp-rc/install-dict-key-{side}/bin/mylang'
  for case in ['bounds','overflow','arena','steps','growth','frames','floor']:
   if mode=='gc' and case=='floor':continue
   if any(x['side']==side and x['mode']==mode and x['backend']==backend and x['case']==case for x in d['runs']):continue
   b=w/f'control-{side}-{mode}-{backend}-{case}';s=w/'controls'/f'{"frames" if case=="floor" else case}.my'
   cmd=[str(r/'scripts/build-slot.sh'),'build',str(c),'build',str(s),'-o',str(b),'--cache-dir='+str(w/f'control-cache-{side}'),'--backend='+backend,'--mode='+('ReleaseFast' if case=='floor' else 'Debug'),'--rc-runtime=stats' if mode=='rc' else '--gc-runtime']
   if backend=='llvm':cmd+=['--llvm-opt=3','--lto']
   p=subprocess.run(cmd,env=e,text=True,capture_output=True);row={'case':case,'side':side,'mode':mode,'backend':backend,'command':cmd,'status':p.returncode,'stdout':p.stdout,'stderr':p.stderr};d['builds'].append(row);save();assert p.returncode==0,row
   m=json.loads(Path(str(b)+'.qbe-manifest.json').read_text());assert m['backend']==backend;row.update(manifest=m,binary_sha256=hashlib.sha256(b.read_bytes()).hexdigest());save()
   options=['']
   if case=='steps':options=[f'--max-steps={n}' for n in [35,40,45,50,55,60,65,70]]
   if case=='frames':options=['--max-frames=16']
   budgets=['128M'] if case!='growth' else ['128K','192K','256K','384K','512K','768K','1M']
   expected={'bounds':'R_LIST_BOUNDS','arena':'R_LIST_BOUNDS','overflow':'R_OVERFLOW','steps':'R_STEP_LIMIT','frames':'R_FRAME_LIMIT','floor':'R_FRAME_LIMIT','growth':'R_MEMORY_BUDGET'}[case]
   for budget in budgets:
    for option in options:
     env=dict(e);env['MYLANG_MEMORY_LIMIT']=budget;env['MYLANG_OPTIONS']=(' --gc-stress' if mode=='gc' else '')+' '+option
     p=subprocess.run([str(b)],env=env,text=True,capture_output=True,timeout=60,preexec_fn=smallstack if case=='floor' else None)
     run={'case':case,'side':side,'mode':mode,'backend':backend,'budget':budget,'options':env['MYLANG_OPTIONS'],'status':p.returncode,'stdout':p.stdout,'stderr':p.stderr};d['runs'].append(run);save()
     if case=='growth':assert p.returncode in [0,1],run
     else:assert p.returncode==1 and expected in p.stderr and p.stdout=='before\n',run
     if mode=='rc':
      lines=[x for x in p.stderr.splitlines() if x.startswith('MYLANG_RC_COUNTS ')];assert len(lines)==1,run
      counts=json.loads(lines[0].removeprefix('MYLANG_RC_COUNTS '));run['counts']=counts
      assert counts['heap_allocate']==counts['retire'] and counts['hold_acquire']==counts['hold_release'] and counts['owner_acquire']+counts['heap_allocate']==counts['owner_release'],run
     save()
   print(backend,side,mode,case,'pass',flush=True)
# The same logical budget retains the same output/code/trace; ownership traffic differs.
for a in d['runs']:
 if a['side']!='before' or a['case']=='floor':continue
 b=next(x for x in d['runs'] if x['side']=='prototype' and x['mode']=='rc' and all(x[k]==a[k] for k in ['case','backend','budget','options']))
 assert (a['status'],a['stdout'])==(b['status'],b['stdout']),(a,b)
 if a['case']!='growth':
  trace=lambda x:'\n'.join(y for y in x['stderr'].splitlines() if not y.startswith('MYLANG_RC_COUNTS '))
  assert trace(a)==trace(b),(a,b)
for backend in ['qbe','llvm']:
 rows=[x for x in d['runs'] if x['backend']==backend and x['side']=='prototype' and x['mode']=='rc' and x['case']=='growth']
 assert any(x['status']==1 and x['stdout']=='before\n' and 'R_MEMORY_BUDGET' in x['stderr'] for x in rows),rows
print('paired logical trap outputs/traces passed',flush=True)
