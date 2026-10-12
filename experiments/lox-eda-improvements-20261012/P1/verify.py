#!/usr/bin/env python3
"""Bounded P1 VM correctness and separately labelled allocation probes."""
import argparse, hashlib, json, os, subprocess
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('candidate',type=Path);p.add_argument('baseline',type=Path);p.add_argument('work',type=Path);p.add_argument('--correctness-only',action='store_true');a=p.parse_args()
a.work.mkdir(parents=True,exist_ok=True)
cases=[
 ('recursion','fun fib(n) { if (n < 2) return n; return fib(n-1)+fib(n-2); } print fib(8);',0,'21\n',None),
 ('upvalues','fun outer(){ var x=1; fun mid(){ fun get(){ x=x+1; return x; } return get; } return mid; } var mid=outer(); var get=mid(); print get(); print get();',0,'2\n3\n',None),
 ('open-shared','fun outer(){ var x=1; fun inc(){ x=x+1; } fun get(){ return x; } inc(); print get(); return get; } var get=outer(); print get();',0,'2\n2\n',None),
 ('class-gc','class A { init(x){ this.x=x; } value(){ return this.x; } } class B < A { value(){ return super.value()+1; } } fun wrap(x){ fun get(){ return x; } return get; } var get=wrap(B(41)); print get().value();',0,'42\n',None),
 ('trace','fun f() {\n print -"x";\n}\nf();',70,'','Operand must be a number.\n[line 2] in f()\n[line 4] in script\n'),
 ('arity','fun f(a) {}\nf();',70,'','Expected 1 arguments but got 0.\n[line 2] in script\n'),
 ('overflow','fun f(){ f(); } f();',70,'',None),
 ('cleanup','fun f(){ { var x=1; fun get(){ return x; } return get; } } var get=f(); print get(); print 2;',0,'1\n2\n',None),
]
probe=a.candidate.parent/'scalar-frame'
probe_receipt={'status':'not_requested_in_correctness_only_mode'}
if not a.correctness_only:
 probe_result=subprocess.run([str(probe.resolve())],capture_output=True,timeout=30)
 assert probe_result.returncode==0,(probe_result.returncode,probe_result.stderr)
 probe_receipt={'path':str(probe.resolve()),'sha256':hashlib.sha256(probe.read_bytes()).hexdigest(),'status':'passed'}
receipt={'scalar_frame_probe':probe_receipt,'binaries':{},'correctness':[],'allocation':[],'timings':'not measured; reduced inputs only'}
for name,binary in [('candidate',a.candidate),('baseline',a.baseline)]:
 binary=binary.resolve();receipt['binaries'][name]={'path':str(binary),'sha256':hashlib.sha256(binary.read_bytes()).hexdigest()}
 for label,source,status,out,err in cases:
  path=a.work/(label+'.lox');path.write_text(source)
  for stress in [False,True]:
   cmd=[str(binary),'--engine=vm']+(['--gc-stress'] if stress else [])+[str(path)]
   result=subprocess.run(cmd,capture_output=True,timeout=30,env={k:v for k,v in os.environ.items() if k!='MYLANG_COUNTERS'})
   assert result.returncode==status,(name,label,result.returncode,result.stderr)
   assert result.stdout.decode()==out,(name,label,result.stdout)
   if err is not None: assert result.stderr.decode()==err,(name,label,result.stderr)
   if label=='overflow':
    assert result.stderr.startswith(b'Stack overflow.\n')
    assert result.stderr.count(b'[line ')==64,(name,result.stderr)
   receipt['correctness'].append({'arm':name,'case':label,'gc_stress':stress,'status':'passed'})
 if a.correctness_only: continue
 for kind in ['arithmetic','calls']:
  for n in [10,100]:
   body='x=x+1;' if kind=='arithmetic' else 'x=f(x);'
   source=('fun f(x){ return x+1; } ' if kind=='calls' else '')+f'var x=0; for(var i=0;i<{n:03d};i=i+1){{ {body} }} print x;'
   path=a.work/f'{kind}-{n}.lox';path.write_text(source)
   counter=a.work/f'{name}-{kind}-{n}.counters.json'
   cmd=[str(binary),'--engine=vm',str(path)]
   result=subprocess.run(cmd,capture_output=True,timeout=30,env=dict(os.environ,MYLANG_COUNTERS=str(counter),MYL_CORE_LEAKCHECK='1'))
   assert result.returncode==0 and result.stdout==f'{n}\n'.encode(),(name,kind,n,result.stderr)
   data=json.loads(counter.read_text());t=data['totals']
   assert t['live_bytes_at_exit']==0
   receipt['allocation'].append({'arm':name,'kind':kind,'n':n,'cumulative_bytes':t['alloc_bytes']+t['realloc_added_bytes'],'peak_live_bytes':t['peak_live_bytes'],'live_bytes_at_exit':t['live_bytes_at_exit'],'raw_counter':str(counter.resolve()),'raw_counter_sha256':hashlib.sha256(counter.read_bytes()).hexdigest()})
if a.correctness_only:
 (a.work/'verification.json').write_text(json.dumps(receipt,indent=2)+'\n')
 print('passed',len(receipt['correctness']),'explicit VM CLI regression checks')
 raise SystemExit(0)
receipt['slopes_bytes_per_added_iteration']={}
for name in ['candidate','baseline']:
 if a.correctness_only: continue
 for kind in ['arithmetic','calls']:
  points=[r for r in receipt['allocation'] if r['arm']==name and r['kind']==kind]
  receipt['slopes_bytes_per_added_iteration'][name+'-'+kind]=(points[1]['cumulative_bytes']-points[0]['cumulative_bytes'])/90
receipt['arithmetic_bytes_per_added_opcode']={name:receipt['slopes_bytes_per_added_iteration'][name+'-arithmetic']/18 for name in ['candidate','baseline']}
receipt['equal_width_input_note']='Counter loop bounds use three decimal characters (010/100), preserving source byte width.'
receipt['opcode_count_note']='Arithmetic loop executes 18 instructions per successful iteration: six condition/jump, six body/loop, six increment/loop; fixed setup/exit excluded by slope.'
receipt['call_slope_note']='Calls slope is bytes per added single-call loop iteration, including dispatch/global work, not isolated call allocation.'
(a.work/'verification.json').write_text(json.dumps(receipt,indent=2)+'\n')
print(json.dumps(receipt['slopes_bytes_per_added_iteration'],indent=2))
