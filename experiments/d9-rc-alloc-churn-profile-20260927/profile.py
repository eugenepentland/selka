import hashlib,json,os,subprocess
from pathlib import Path
root=Path.cwd(); work=root/'.tmp-mut-argument/allocator-audit'; parent=root.parent/'d9-rc-performance/.tmp-rc-performance/diagnostic-7d68202d'
data=json.loads((parent/'results.json').read_text()); result={'source':'7d68202d','cpu':2,'backends':{}}
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def run(cmd):return subprocess.run(cmd,text=True,capture_output=True,check=True,env=dict(os.environ,TMPDIR=str(work)))
for backend in ('qbe','llvm'):
 original=parent/'bin'/f'parity-micro-alloc_churn.{backend}'; twin=work/f'alloc-churn-{backend}-symbols'
 command=data['builds'][original.name]['cmd'].copy(); command[command.index('-o')+1]=str(twin); command[command.index('--cache-dir')+1]=str(work/'cache'); command.append('--keep-symbols')
 built=run(command)
 for name,path in [('original',original),('twin',twin)]:
  run(['objcopy','--dump-section','.text='+str(work/f'{backend}-{name}.text'),str(path)])
 original_text=work/f'{backend}-original.text'; twin_text=work/f'{backend}-twin.text'
 assert original_text.read_bytes()==twin_text.read_bytes(),backend
 row={'build':command,'original_sha256':sha(original),'twin_sha256':sha(twin),'text_sha256':sha(twin_text)}
 result['backends'][backend]=row; (work/'results.json').write_text(json.dumps(result,indent=2)+'\n')
 print('byte-identical text',backend,row['text_sha256'],flush=True)
 command=['perf','record','-q','-e','cpu_core/instructions/u','-F','199','-o',str(work/f'{backend}.data'),'--','taskset','-c','2',str(twin)]
 done=run(command); row.update(profile_command=command,stdout=done.stdout,stderr=done.stderr)
 for suffix,args in [('samples.txt',['script','-F','ip,sym,dso,period']),('report.txt',['report','--stdio','--no-children','--sort','symbol,dso','--percent-limit','0.3']),('stats.txt',['report','--stdio','--stats'])]:
  done=run(['perf']+args+['-i',str(work/f'{backend}.data')]); (work/f'{backend}.{suffix}').write_text(done.stdout+done.stderr)
 manifest=json.loads(Path(str(twin)+'.qbe-manifest.json').read_text()); row['manifest']=manifest
 stats=work/f'alloc-churn-{backend}-stats';command=command=data['builds'][original.name]['cmd'].copy();command[command.index('-o')+1]=str(stats); command[command.index('--cache-dir')+1]=str(work/'cache');command[command.index('--rc-runtime')]='--rc-runtime=stats'
 run(command); done=run(['taskset','-c','2',str(stats)]); row['counts_command']=command;row['counts']=json.loads(done.stderr.removeprefix('MYLANG_RC_COUNTS '));assert done.stdout==row['stdout']
 (work/'results.json').write_text(json.dumps(result,indent=2)+'\n');print('profile complete',backend,row['counts'],flush=True)
