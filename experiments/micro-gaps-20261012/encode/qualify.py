"""Checksum and managed-counter qualification; elapsed output is not timing evidence."""
import hashlib, importlib.util, json, os, pathlib, subprocess, sys
root=pathlib.Path(__file__).resolve().parents[3]
out=pathlib.Path(__file__).resolve().parent
candidate=pathlib.Path(sys.argv[1]).resolve()
baseline=pathlib.Path('/home/epentland/ai/canopy/mylang-micro-expanded-20261012/.tmp/micro-ownership/expanded/bin/text-mylang-zero-rc-counted')
spec=importlib.util.spec_from_file_location('oracle',root/'benchmarks/runtime/expanded/text/oracle.py')
oracle=importlib.util.module_from_spec(spec); spec.loader.exec_module(oracle)
rows=[]
for case,sizes in [('int_format',[64,4096]),('string_split',[64,4096]),('word_count',[16,256])]:
 for size in sizes:
  iterations=1000 if case=='int_format' else 17
  seed=42
  expected=oracle.checksum(case,size,iterations,seed)
  for arm,binary in [('C0',baseline),('encode',candidate)]:
   counters=out/f'{case}.{size}.{arm}.counters.json'
   env=dict(os.environ,MYLANG_COUNTERS=str(counters),MYL_CORE_LEAKCHECK='1')
   run=subprocess.run([str(binary),case,str(size),str(iterations),str(seed)],env=env,text=True,capture_output=True)
   c=json.loads(counters.read_text())
   assert run.returncode==0 and run.stderr=='' and int(run.stdout.split()[0])==expected,(case,size,arm,run.stdout,run.stderr)
   assert c['totals']['live_bytes_at_exit']==0
   assert all(c['kinds'][kind]['count']==0 for kind in ['retain','release','unique_test'])
   rows.append(dict(case=case,size=size,iterations=iterations,seed=seed,arm=arm,checksum=expected,binary=str(binary),binary_sha256=hashlib.sha256(binary.read_bytes()).hexdigest(),totals=c['totals'],kinds=c['kinds']))
source=root/'experiments/micro-ownership-20261012/expanded/migrated/text.my'
compiler=candidate.parent/'install/bin/mylang'
llvm=(candidate.parent/'text.ll').read_text()
score=llvm.split('define internal fastcc i64 @"my.text::score"',1)[1].split('\n}',1)[0]
assert 'call ptr @myl_core_text_encode(' not in score
assert 'insertvalue { ptr, i64 }' in score and 'extractvalue { ptr, i64 }' in score
assert any('%vd' in line and 'extractvalue { ptr, i64 }' in line for line in score.splitlines())
(out/'score.ll.txt').write_text('define internal fastcc i64 @"my.text::score"'+score+'\n}\n')
(out/'qualification.json').write_text(json.dumps(dict(source=str(source),source_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),compiler=str(compiler),compiler_sha256=hashlib.sha256(compiler.read_bytes()).hexdigest(),llvm_sha256=hashlib.sha256(llvm.encode()).hexdigest(),structural=dict(score_encode_calls=0,score_borrows=True,score_vector_span_base=True),runs=rows),indent=2)+'\n')
print(f'{len(rows)} checksum/counter probes passed')
