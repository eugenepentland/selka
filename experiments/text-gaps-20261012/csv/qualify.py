"""CSV checksum and owned-counter probes on immutable migrated source."""
import hashlib, importlib.util, json, os, pathlib, subprocess, sys
root=pathlib.Path(__file__).resolve().parents[3]
out=pathlib.Path(__file__).resolve().parent
candidate=pathlib.Path(sys.argv[1]).resolve()
baseline=root.parent/'mylang-memory-20261012/.tmp/micro-gaps/coordinator/bin/expanded-text-counted'
spec=importlib.util.spec_from_file_location('oracle',root/'benchmarks/runtime/expanded/text/oracle.py')
oracle=importlib.util.module_from_spec(spec); spec.loader.exec_module(oracle)
rows=[]
for size,seed,iterations in [(16,42,17),(256,42,17),(16,1,1),(256,999983,3)]:
 expected=oracle.checksum('csv_aggregate',size,iterations,seed)
 for arm,binary in [('C0',baseline),('csv',candidate)]:
  path=out/f'csv.{size}.{seed}.{iterations}.{arm}.counters.json'
  env=dict(os.environ,MYLANG_COUNTERS=str(path),MYL_CORE_LEAKCHECK='1')
  run=subprocess.run([str(binary),'csv_aggregate',str(size),str(iterations),str(seed)],env=env,text=True,capture_output=True)
  c=json.loads(path.read_text())
  assert run.returncode==0 and run.stderr=='' and int(run.stdout.split()[0])==expected,(arm,run.stdout,run.stderr)
  assert c['totals']['live_bytes_at_exit']==0
  assert all(c['kinds'][kind]['count']==0 for kind in ['retain','release','unique_test'])
  rows.append(dict(size=size,seed=seed,iterations=iterations,arm=arm,checksum=expected,binary=str(binary),binary_sha256=hashlib.sha256(binary.read_bytes()).hexdigest(),totals=c['totals'],functions=c['functions']))
source=root/'experiments/micro-ownership-20261012/expanded/migrated/text.my'
compiler=candidate.parent/'install/bin/mylang'
(out/'qualification.json').write_text(json.dumps(dict(source=str(source),source_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),compiler_sha256=hashlib.sha256(compiler.read_bytes()).hexdigest(),runs=rows),indent=2)+'\n')
print(f'{len(rows)} oracle/counter probes passed')
for a,b in zip(rows[::2],rows[1::2]):
 print(a['size'],a['seed'],a['iterations'],'allocs',a['totals']['allocs'],'->',b['totals']['allocs'],'bytes',a['totals']['alloc_bytes'],'->',b['totals']['alloc_bytes'])
