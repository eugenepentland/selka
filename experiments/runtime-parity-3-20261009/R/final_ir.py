#!/usr/bin/env python3
"""Archive final compiler IR for exact array and ordinary-sret copy attribution."""
import argparse,gzip,json,os,pathlib,subprocess,sys
ROOT=pathlib.Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/'experiments/runtime-parity-3-20261009/tools'))
import ce
p=argparse.ArgumentParser();p.add_argument('--compiler',type=pathlib.Path,required=True);a=p.parse_args()
assert pathlib.Path(os.readlink('/proc/self/fd/9')).name.startswith('build')
lane=ce.Lane(a.compiler,'r-final-ir');lane.cache.mkdir(parents=True,exist_ok=True)
area=ROOT/'experiments/runtime-parity-3-20261009/R';rows=[]
for label,source,links in [('parity-fannkuch_redux_array',ROOT/'bench/parity/suite/fannkuch_redux_array.my',[]),('parity-fannkuch_redux_tuned',ROOT/'bench/parity/suite/fannkuch_redux_tuned.my',[]),('row-record_pass',ce.row_sources()['record_pass'],['--link',str(ROOT/'benchmarks/runtime/ports/native_clock.c')])]:
 for kind in ['plain','count']:
  llvm=lane.cache/(label+'-'+kind+'.ll');binary=lane.cache/(label+'-'+kind)
  command=[str(lane.compiler),'build',str(source),'--release','--cache-dir',str(lane.cache/'objects'),'-o',str(binary),'--emit-llvm',str(llvm),*links,*(['--counters'] if kind=='count' else [])]
  result=subprocess.run(command,cwd=ROOT,env=dict(os.environ,MYLANG_CORE_RUNTIME_CACHE=str(lane.runtime_cache)),capture_output=True)
  row={'label':label,'kind':kind,'command':command,'status':result.returncode,'stderr':result.stderr.decode()};rows.append(row)
  assert result.returncode==0,row
  archive=area/'llvm'/('final-'+llvm.name+'.gz')
  with gzip.open(archive,'wb',compresslevel=9) as output:output.write(llvm.read_bytes())
  row.update(llvm_sha256=ce.digest(llvm),binary_sha256=ce.digest(binary),archive=str(archive.relative_to(ROOT)))
  print(label,kind,flush=True)
(area/'final-llvm.json').write_text(json.dumps({'compiler_sha256':ce.digest(lane.compiler),'rows':rows},indent=1)+'\n')
