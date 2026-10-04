from pathlib import Path
import json,sys,datetime,hashlib
root=Path.cwd();work=root/'.mylang-cache/goal110-dict-word-debug';manifest=work/'runner/manifest.json';output=work/'qualification.json'
sys.path.insert(0,str(root/'benchmarks/runtime/expanded'));import run as expanded
sys.path.insert(0,str(root/'benchmarks/runtime/diagnostics'));import holdouts
h=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
saved=json.loads(manifest.read_text());bound=h(manifest);holdouts.check_manifest(manifest,bound,saved)
helpers={str(p):h(p) for p in [Path(__file__).resolve(),root/'benchmarks/runtime/expanded/run.py',root/'benchmarks/runtime/expanded/registry.py',root/'benchmarks/runtime/runner.py',root/'benchmarks/runtime/build_compiler.py',root/'benchmarks/runtime/diagnostics/holdouts.py']}
report={'schema':'mylang-runtime-qualification-v1','status':'correctness_in_progress','timing':False,'purpose':'720 edge checksum qualifications; all elapsed values discarded','started_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'manifest_path':str(manifest),'manifest_sha256':bound,'source_revision':saved['identity']['source_revision'],'binary_hashes':saved['binary_hashes'],'helper_hashes':helpers,'cpu':0,'arms':list(expanded.ARMS),'probes':list(expanded.EDGE_PROBES),'checks':[]}
seen=set()
for case in expanded.inventory():
 print('Qualifying '+case,flush=True)
 for size,seed,count in expanded.EDGE_PROBES:
  for arm in expanded.ARMS:
   key=(case,size,seed,count,arm);assert key not in seen;seen.add(key)
   binary=Path(saved['identity']['binary_paths'][expanded.inventory()[case]['group']+'/'+arm]);expected=expanded.checksum(case,size,count,seed)
   result=expanded.common.invoke(binary,case,size,count,seed,0,expected);result.pop('kernel_ns');result.pop('process_wall_ns')
   report['checks'].append({'case':case,'size':size,'seed':seed,'iterations':count,'arm':arm,**result,'expected_checksum':expected,'clock_protocol_validated':True,'command':['taskset','-c','0',str(binary),case,str(size),str(count),str(seed)]})
assert len(report['checks'])==720 and len(seen)==720
holdouts.check_manifest(manifest,bound,saved)
for path,value in helpers.items():assert h(path)==value
report.update(status='correctness_complete',finished_utc=datetime.datetime.now(datetime.timezone.utc).isoformat());output.write_text(json.dumps(report,indent=2)+'\n');print('PASS720 edge qualifications; no performance evidence',flush=True)
