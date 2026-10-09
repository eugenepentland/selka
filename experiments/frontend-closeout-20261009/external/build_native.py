#!/usr/bin/env python3
"""Build the frozen migrated guest applications with one immutable compiler."""
import hashlib,json,pathlib,subprocess,sys,time
root=pathlib.Path(__file__).resolve().parents[3]
base=pathlib.Path(__file__).resolve().parent
compiler=pathlib.Path(sys.argv[1]).resolve()
source=root/'experiments/frontend-followthrough-20261009/external/sources'
rows=[]
for corpus,relative in [('lox','benchmarks/lox/ports/mylang/main.my'),('eda','mylang/src/main.my')]:
 output=base/'artifacts'/f'{corpus}-release';output.parent.mkdir(parents=True,exist_ok=True)
 argv=[str(compiler),'build',str(source/corpus/relative),'-o',str(output),'--release','--cache-dir',str(base/'native-build-cache')]
 started=time.monotonic();result=subprocess.run(argv,cwd=source/corpus,capture_output=True)
 (base/f'{corpus}-build.stdout').write_bytes(result.stdout);(base/f'{corpus}-build.stderr').write_bytes(result.stderr)
 rows.append({'corpus':corpus,'argv':argv,'cwd':str(source/corpus),'compiler_sha256':hashlib.sha256(compiler.read_bytes()).hexdigest(),'source':str(source/corpus/relative),'source_sha256':hashlib.sha256((source/corpus/relative).read_bytes()).hexdigest(),'exit':result.returncode,'wall_seconds':time.monotonic()-started,'binary_sha256':hashlib.sha256(output.read_bytes()).hexdigest() if output.exists() else None})
 (base/'native-builds.json').write_text(json.dumps(rows,indent=2)+'\n')
 print(corpus,result.returncode,flush=True)
 if result.returncode:sys.exit(result.returncode)
