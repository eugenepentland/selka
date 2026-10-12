#!/usr/bin/env python3
"""Run unchanged canonical full-corpus aggregation after all132 receipts exist."""
import argparse,hashlib,json,pathlib,re,subprocess,sys
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--root',type=pathlib.Path,default=pathlib.Path('/home/epentland/ai/canopy/mylang-memory-20261012'));p.add_argument('--output',type=pathlib.Path,required=True);a=p.parse_args();bench=a.root/'experiments/lox-eda-zero-rc-20261012/bench'
pattern=re.compile(r'.+\.r\d+-\d+\.w\d+\.rss\d+\.json$');receipts=[]
for directory,count in [('initial-fib',2),('lox-remaining',96),('eda-final',34)]:
 paths=sorted(p for p in (bench/'results'/directory).glob('*.json') if pattern.fullmatch(p.name));assert len(paths)==count,(directory,len(paths),count);receipts+=paths
assert len(receipts)==132
a.output.mkdir(parents=True,exist_ok=True);destination=a.output/'full-runtime-summary.json';temporary=a.output/'full-runtime-summary.pending.json'
with temporary.open('w') as f:subprocess.run([sys.executable,str(bench/'summarize.py'),'--spec-dir',str(bench/'frozen-specs'),*map(str,receipts)],stdout=f,check=True)
d=json.loads(temporary.read_text());assert len(d['cells'])==60;temporary.replace(destination)
subprocess.run([sys.executable,str(pathlib.Path(__file__).with_name('compare.py')),str(destination),'--root',str(a.root),'--output',str(a.output)],check=True)
(a.output/'aggregation-provenance.json').write_text(json.dumps({'expected_receipts':132,'expected_cells':60,'canonical_aggregator':str(bench/'summarize.py'),'canonical_aggregator_sha256':hashlib.sha256((bench/'summarize.py').read_bytes()).hexdigest(),'benchmark_compiler_sha256':'6e7938a14ad4abc46b76c149ef12551b170f6c7e6f462beec2f81db18d40a83d','later_integrated_gate_compiler_sha256':'8e58720cd72de8632aa48df373d18fc8238d46ec27010f8b182820a0eaaf10fa','guests_rebuilt_after_gate':False},indent=2)+'\n')
