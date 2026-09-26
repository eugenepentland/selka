import hashlib,json,os,statistics,subprocess
from pathlib import Path
root=Path.cwd(); work=root/'.tmp-schematic/inline-take'
env=dict(os.environ,TMPDIR=str(root/'.tmp-schematic/tmp'),ZIG_LOCAL_CACHE_DIR=str(root/'.zig-cache-schematic'))
fixture=work/'binary_trees.my';fixture.write_text((root/'bench/parity/suite/binary_trees.my').read_text().replace('max_depth = 16','max_depth = 12'))
expected='stretch tree of depth 13\t check: 16383\n'+''.join(f'{1<<(16-d)}\t trees of depth {d}\t check: {(1<<(16-d))*((1<<(d+1))-1)}\n' for d in range(4,13,2))+'long lived tree of depth 12\t check: 8191\n'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
result={'kind':'private n12 diagnostic, not full corpus acceptance','source':fixture.read_text(),'expected':expected,'before_commit':subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),'after_patch':subprocess.check_output(['git','diff','--','src/'],text=True),'builds':{},'counts':{},'instructions':{}}
for side,compiler in [('before',root/'.tmp-schematic/install-before-inline-take/bin/mylang'),('after',root/'zig-out/bin/mylang')]:
 for backend in ('qbe','llvm'):
  for stats in (False,True):
   key=f'{side}-{backend}'+('-stats' if stats else '');binary=work/key
   cmd=[str(root/'scripts/build-slot.sh'),'build',str(compiler),'build',str(fixture),'--rc-runtime'+('=stats' if stats else ''),'-o',str(binary),'--cache-dir='+str(work/'cache')]
   if backend=='llvm':cmd+=['--backend=llvm','--llvm-opt=3','--lto']
   build=subprocess.run(cmd,env=env,capture_output=True,text=True);assert build.returncode==0,(cmd,build.stderr)
   run=subprocess.run([str(binary)],capture_output=True,text=True);assert run.returncode==0 and run.stdout==expected,(key,run.returncode,run.stdout,run.stderr)
   result['builds'][key]={'command':cmd,'compiler_sha256':sha(compiler),'binary_sha256':sha(binary)}
   if stats:
    rows=[json.loads(l.split(' ',1)[1]) for l in run.stderr.splitlines() if l.startswith('MYLANG_RC_COUNTS ')];assert len(rows)==1,run.stderr
    c=rows[0];assert not c['saturated'] and c['heap_allocate']==c['retire'] and c['heap_allocate']+c['owner_acquire']==c['owner_release'],c
    result['counts'][key]=c
   else:result['instructions'][key]=[]
   (work/'results.json').write_text(json.dumps(result,indent=2)+'\n');print('built',key,flush=True)
for rep in range(3):
 for backend in ('qbe','llvm'):
  for side in (('before','after') if rep%2==0 else ('after','before')):
   key=f'{side}-{backend}';cmd=['taskset','-c','2','perf','stat','-x,','-e','instructions:u','--',str(work/key)]
   run=subprocess.run(cmd,capture_output=True,text=True);assert run.returncode==0 and run.stdout==expected,(key,run.returncode,run.stderr)
   lines=[l.split(',') for l in run.stderr.splitlines() if 'instructions' in l and l.split(',')[0].strip().isdigit()];assert len(lines)==1,run.stderr
   result['instructions'][key].append(int(lines[0][0]));(work/'results.json').write_text(json.dumps(result,indent=2)+'\n')
result['ratios']={b:statistics.median(result['instructions']['after-'+b])/statistics.median(result['instructions']['before-'+b]) for b in ('qbe','llvm')}
(work/'results.json').write_text(json.dumps(result,indent=2)+'\n');print(result['ratios'],flush=True)
