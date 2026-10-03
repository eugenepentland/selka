from pathlib import Path
import argparse,subprocess,os,json,hashlib
parser=argparse.ArgumentParser()
parser.add_argument('--work',type=Path,required=True)
w=parser.parse_args().work.resolve()
base=Path('/home/epentland/ai/canopy/mylang-worktrees/codex-lox-perf-stack-20261002/.tmp-lox-stack/joined-qualification/bin')
rows=[]
for backend in ['llvm','qbe']:
 for engine in ['vm','tree']:
  for native_stress in [False,True]:
   for lox_stress in [False,True]:
    for probe,expected_status,expected_stdout in [('probe-upvalues',0,b'12\n15\n'),('probe-return-error',70,b'')]:
     runs=[]
     for arm,binary in [('baseline',base/('joined-gc-'+backend)),('candidate',w/'bin'/('final-gc-'+backend))]:
      env={k:v for k,v in os.environ.items() if not k.startswith('MYLANG_') and k!='LD_PRELOAD'}
      env['TMPDIR']=str(w/'tmp')
      if native_stress:env['MYLANG_OPTIONS']='--gc-stress'
      args=['taskset','-c','14',str(binary),'--engine='+engine,'--stats']
      if lox_stress:args+=['--gc-stress']
      args+=[str(w/(probe+'.lox'))]
      p=subprocess.run(args,capture_output=True,env=env,timeout=120)
      row={'backend':backend,'engine':engine,'native_gc_stress':native_stress,'lox_gc_stress':lox_stress,'probe':probe,'arm':arm,'argv':args,'env':{'TMPDIR':env['TMPDIR'],'MYLANG_OPTIONS':env.get('MYLANG_OPTIONS')},'binary_sha256':hashlib.sha256(binary.read_bytes()).hexdigest(),'status':p.returncode,'stdout':p.stdout.decode(),'stderr':p.stderr.decode()}
      rows.append(row);runs.append((p.returncode,p.stdout,p.stderr))
      (w/'gc-probes-corrected.json').write_text(json.dumps(rows,indent=2)+'\n')
     assert runs[0]==runs[1],rows[-2:]
     assert runs[1][0]==expected_status and runs[1][1]==expected_stdout,rows[-1]
print('all',len(rows),'baseline/candidate native-GC guest probes matched status/stdout/stderr/collector stats',flush=True)
