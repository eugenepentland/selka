#!/usr/bin/env python3
"""Compare exact unoptimized/release Core and release LLVM; run native probes."""
import hashlib,json,pathlib,subprocess,time,sys
root=pathlib.Path(__file__).resolve().parents[3]
base=pathlib.Path(__file__).resolve().parent
trial=sys.argv[1]
compilers={'old5e':root/'experiments/frontend-followthrough-20261009/external/artifacts/mylang-successor','candidate':pathlib.Path(sys.argv[2]).resolve()}
paths=[root/'tests/lang'/p for p in ['loop_rebinding.my','bounded_loop_ranges.my','array_negative_index.my','rc_scalar_loops.my']]+[base/'fixtures/python_expressions_driver.my',base/'fixtures/range_semantics_v2.my']
if len(sys.argv)>3: paths=[pathlib.Path(p).resolve() for p in sys.argv[3:]]
rows=[]
for path in paths:
 for label,compiler in compilers.items():
  out=base/trial/label/path.stem;out.mkdir(parents=True,exist_ok=True)
  for mode,args in [('raw',['dump-ir',str(path)]),('facts',['dump-ir',str(path),'--facts']),('build',['build',str(path),'-o',str(out/'program'),'--release','--no-cache','--emit-llvm',str(out/'module.ll')])]:
   before=time.monotonic();argv=[str(compiler),*args];result=subprocess.run(argv,cwd=root,capture_output=True)
   (out/f'{mode}.stdout').write_bytes(result.stdout);(out/f'{mode}.stderr').write_bytes(result.stderr)
   row={'source':str(path.relative_to(root)),'source_sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'compiler':label,'compiler_sha256':hashlib.sha256(compiler.read_bytes()).hexdigest(),'mode':mode,'argv':argv,'exit':result.returncode,'wall_seconds':time.monotonic()-before}
   rows.append(row)
   if mode=='build' and result.returncode==0:
    run=subprocess.run([str(out/'program')],cwd=root,capture_output=True);(out/'run.stdout').write_bytes(run.stdout);(out/'run.stderr').write_bytes(run.stderr);row['native_exit']=run.returncode
 (base/(trial+'-manifest.json')).write_text(json.dumps(rows,indent=2)+'\n')
results=[]
for path in paths:
 a=base/trial/'old5e'/path.stem;b=base/trial/'candidate'/path.stem
 results.append({'source':str(path.relative_to(root)),**{k:a.joinpath(k).exists() and b.joinpath(k).exists() and a.joinpath(k).read_bytes()==b.joinpath(k).read_bytes() for k in ['raw.stdout','facts.stdout','module.ll','run.stdout','run.stderr']}})
(base/(trial+'-comparison.json')).write_text(json.dumps(results,indent=2)+'\n');print(json.dumps(results,indent=2))
