import hashlib,json,os,re,subprocess
from pathlib import Path
root=Path.cwd();work=root/'.tmp-schematic/history-guests';compiler=root/'zig-out/bin/mylang'
source=(root/'tests/lang/rc_semantic_history.my').read_text();names=re.findall(r'^public def (test_\w+)\(',source,re.M)
text=source+'\n\ndef main(out: Stream) -> int:\n'+''.join('    out.print(f"'+n+': {'+n+'()}")\n' for n in names)+'    return 0\n'
p=work/'rc_semantic_history.my';p.write_text(text);rows={};env=dict(os.environ,TMPDIR=str(root/'.tmp-schematic/tmp'))
for backend in ('qbe','llvm'):
 for mode in ('gc','rc'):
  key=f'{backend}-{mode}';command=[str(root/'scripts/build-slot.sh'),'build',str(compiler),'run',str(p),'--gc-runtime' if mode=='gc' else '--rc-runtime=stats']
  if mode=='gc':command+=['--gc-stress']
  if backend=='llvm':command+=['--release']
  run=subprocess.run(command,capture_output=True,text=True,env=env);assert run.returncode==0,(key,run.stderr)
  counters=[json.loads(line.split(' ',1)[1]) for line in run.stderr.splitlines() if line.startswith('MYLANG_RC_COUNTS ')]
  if mode=='rc':
   assert len(counters)==1
   c=counters[0];assert c['runtime']=='rc-v3-counting' and not c['saturated'] and c['heap_allocate']==c['retire'] and c['heap_allocate']+c['owner_acquire']==c['owner_release'] and c['hold_acquire']==c['hold_release'],c
  else:assert not counters
  rows[key]={'command':command,'stdout':run.stdout,'stderr':run.stderr,'counters':counters}
  (work/'counts.json').write_text(json.dumps({'compiler_sha256':hashlib.sha256(compiler.read_bytes()).hexdigest(),'source':text,'runs':rows},indent=2)+'\n')
  print(key,'balanced',len(counters),'records',flush=True)
