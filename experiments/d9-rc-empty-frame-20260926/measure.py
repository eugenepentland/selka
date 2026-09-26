import json,os,subprocess,hashlib,statistics
from pathlib import Path
root=Path.cwd();work=root/'.tmp-schematic/empty-frame-perf';work.mkdir(exist_ok=True)
env=dict(os.environ,TMPDIR=str(root/'.tmp-schematic/tmp'),ZIG_LOCAL_CACHE_DIR=str(root/'.zig-cache-schematic'))
source=(root/'bench/parity/suite/binary_trees.my').read_text().replace('max_depth = 16','max_depth = 12');fixture=work/'binary_trees.my';fixture.write_text(source)
expected='stretch tree of depth 13\t check: 16383\n'+''.join(f'{1<<(16-d)}\t trees of depth {d}\t check: {(1<<(16-d))*((1<<(d+1))-1)}\n' for d in range(4,13,2))+'long lived tree of depth 12\t check: 8191\n'
result={'source':source,'expected':expected,'source_base':'a49441c1','compilers':{},'builds':{},'counts':{}}
for side,compiler in [('before',root/'.tmp-schematic/install-before-frame/bin/mylang'),('after',root/'zig-out/bin/mylang')]:
 result['compilers'][side]=hashlib.sha256(compiler.read_bytes()).hexdigest()
 for backend in ['qbe','llvm']:
  binary=work/f'{side}-{backend}';key=f'{side}-{backend}'
  cmd=[str(root/'scripts/build-slot.sh'),'build',str(compiler),'build',str(fixture),'--rc-runtime','-o',str(binary),'--cache-dir='+str(work/'cache')]
  if backend=='llvm':cmd+=['--backend=llvm','--llvm-opt=3','--lto']
  subprocess.run(cmd,env=env,check=True,capture_output=True)
  actual=subprocess.run([str(binary)],capture_output=True,text=True,check=True);assert actual.stdout==expected,(key,actual.stdout,expected)
  result['builds'][key]={'command':cmd,'binary_sha256':hashlib.sha256(binary.read_bytes()).hexdigest()};result['counts'][key]=[]
for rep in range(3):
 for backend in ['qbe','llvm']:
  for side in (['before','after'] if rep%2==0 else ['after','before']):
   key=f'{side}-{backend}';binary=work/key
   p=subprocess.run(['taskset','-c','2','perf','stat','-x,','-e','instructions:u','--',str(binary)],capture_output=True,text=True,check=True)
   assert p.stdout==expected
   lines=[l.split(',') for l in p.stderr.splitlines() if 'instructions' in l and l.split(',')[0].strip().isdigit()];assert len(lines)==1,p.stderr
   result['counts'][key].append(int(lines[0][0]))
result['ratios']={backend:statistics.median(result['counts']['after-'+backend])/statistics.median(result['counts']['before-'+backend]) for backend in ['qbe','llvm']}
(work/'results.json').write_text(json.dumps(result,indent=2)+'\n');print(result['ratios'],flush=True)
