#!/usr/bin/env python3
"""Hold S4-V's final test-core and strict full-conformance gates; rebuild is separate."""
import argparse,hashlib,importlib.util,json,os,re,shlex,subprocess,time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
RETAIN='"$@"; result=$?; exit "$result"'
spec=importlib.util.spec_from_file_location('old_gate_tools',ROOT/'experiments/new-core-s2-20261005/wave-b/integration/full_old_gate.py')
gate_tools=importlib.util.module_from_spec(spec); spec.loader.exec_module(gate_tools)

def main():
 p=argparse.ArgumentParser(description=__doc__)
 p.add_argument('--evidence',type=Path,required=True)
 p.add_argument('--shards',type=int,default=32)
 p.add_argument('--old',type=Path,default=ROOT/'zig-out/bin/mylang')
 p.add_argument('--old-sha256',default='29a8662e86f113341f5f71c9c4fce5686481b4aa8fea223be47788f027797dbe')
 a=p.parse_args(); out=a.evidence.resolve()
 if not out.is_relative_to(ROOT/'experiments') or out.exists(): p.error('evidence must be a fresh directory inside experiments')
 out.mkdir(parents=True)
 commit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip()
 old=a.old.resolve(); core=ROOT/'zig-out/bin/mylang-core'
 digest=hashlib.sha256(old.read_bytes()).hexdigest()
 if digest!=a.old_sha256: raise RuntimeError('unqualified fresh shared-checker oracle')
 env=os.environ.copy(); temporary=ROOT/'.mylang-cache/s4-v/qualification'/out.name/'tmp'; temporary.mkdir(parents=True)
 env.update(TMPDIR=str(temporary),ZIG_GLOBAL_CACHE_DIR='/home/epentland/ai/canopy/.zig-global-cache')
 results=[]; summary={'source_commit':commit,'old_sha256':digest,'core_shards':a.shards,'results':results,'qualified':False}
 def run(name,command,exclusive=False):
  timer=out/(name+'.seconds'); timed=['/usr/bin/time','-f','%e','-o',str(timer),*command]
  if exclusive: timed=['python3','experiments/new-core-s3-20261006/wave-a/exclusive_core.py','--',*timed]
  wrapped=['scripts/build-slot.sh','gate','--','bash','-c',RETAIN,'--','scripts/build-slot.sh','build','--',*timed]
  started=time.monotonic(); log=out/(name+'.log'); print(name+': '+str(log),flush=True)
  with log.open('x') as f:
   f.write('source_commit='+commit+'\n$ '+shlex.join(wrapped)+'\n'); f.flush()
   status=subprocess.run(wrapped,cwd=ROOT,env=env,stdout=f,stderr=subprocess.STDOUT).returncode
  report=log.read_text(); seconds=float(timer.read_text().splitlines()[-1]) if timer.exists() else None
  item={'command':wrapped,'log':str(log.relative_to(ROOT)),'status':status,'seconds':seconds,'wall_including_admission':time.monotonic()-started}
  results.append(item); (out/'summary.json').write_text(json.dumps(summary,indent=2)+'\n')
  if status or seconds is None: raise RuntimeError(name+' failed; retained '+str(log))
  return report,item
 try:
  summary['core_sha256']=hashlib.sha256(core.read_bytes()).hexdigest()
  report,test=run('test-core',['zig','build','test-core',f'-Dcore-shards={a.shards}','--summary','all'])
  test['build_inspection']=gate_tools.inspect(report)
  if test['build_inspection']['errors']: raise RuntimeError('test-core summary/RSS failed: '+ '; '.join(test['build_inspection']['errors']))
  walls=[float(x) for x in re.findall(r'guardian/test: test wall ([0-9.]+)s',report)]
  test['longest_shard_seconds']=max(walls) if walls else None
  verdicts=[json.loads(x) for x in re.findall(r'guardian/test: RESULT (\{[^\n]+\})',report)]
  test['tests']={k:sum(x[k] for x in verdicts) for k in ('passed','failed','skipped')}
  if len(verdicts)!=a.shards or test['tests']['failed']: raise RuntimeError('test-core shard verdicts are missing or failed')
  if test['seconds']>300 or not walls or max(walls)>90: raise RuntimeError('test-core time requires resharding')
  run('full-conformance',['python3','experiments/new-core-s2-20261005/wave-b/integration/conformance_checked.py','--set','all','--mylang',str(old),'--core',str(core),'--cache-dir',str(temporary.parent/'conformance'),'--jobs','4','--why','--leakcheck','--verify'])
  summary['qualified']=True
 except Exception as e:
  summary['error']=str(e); raise
 finally:
  (out/'summary.json').write_text(json.dumps(summary,indent=2)+'\n')
 print(json.dumps(summary,indent=2),flush=True)
if __name__=='__main__': main()
