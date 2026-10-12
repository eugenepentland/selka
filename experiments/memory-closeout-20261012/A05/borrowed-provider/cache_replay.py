#!/usr/bin/env python3
"""Cold/warm, physical-record discovery, refusal and source-relocation replay."""
import argparse,hashlib,json,os,subprocess
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--compiler',type=Path,required=True);p.add_argument('--zig',required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args();a.output=a.output.resolve();a.output.mkdir(parents=True,exist_ok=True);a.compiler=a.compiler.resolve()
source=(Path(__file__).resolve().parent.parent/'samples/borrowed_context.my').read_text();project=a.output/'project';project.mkdir(exist_ok=True);(project/'main.my').write_text(source)
sha=lambda x:hashlib.sha256(x.read_bytes()).hexdigest()
report={'compiler':str(a.compiler),'compiler_sha256':sha(a.compiler),'harness_sha256':sha(Path(__file__)),'cases':{}}
env=dict(os.environ);env.pop('MYLANG_OPTIONS',None);env.pop('MYLANG_COUNTERS',None)
extra=source.replace('record Context:', 'record Earlier:\n    value: int\n\nfunc earlier(value: Earlier) -> int:\n    return value.value\n\nrecord Context:').replace('func main() -> int:\n', 'func main() -> int:\n    assert earlier(Earlier(value=23)) == 23\n')
for name,text,refused in [('cold',source,False),('warm',source,False),('earlier-record',extra,False),('earlier-record-warm',extra,False),('invalid-borrow',source.replace('    return ctx.offset','    const escape = ctx\n    return escape.offset'),True),('restored',source,False),('relocated',source,False)]:
 if name=='relocated':project=a.output/'relocated';project.mkdir(exist_ok=True)
 main=project/'main.my';main.write_text(text);binary=a.output/(name+'.bin');llvm=a.output/(name+'.ll')
 argv=[str(a.compiler),'build',str(main),'--experimental-zero-rc','--release','--cache-dir',str(a.output/'cache'),'--zig',a.zig,'--report','--emit-llvm',str(llvm),'-o',str(binary)]
 r=subprocess.run(argv,capture_output=True,text=True,timeout=600,env=env)
 row={'source_sha256':sha(main),'argv':argv,'status':r.returncode,'stdout':r.stdout,'stderr':r.stderr,'expected_refusal':refused}
 row['reports']=[json.loads(line) for line in (r.stdout+'\n'+r.stderr).splitlines() if line.startswith('{"version":"cache-report-v1"')]
 if refused:row['passed']=r.returncode==1 and 'E_SINGLE_OWNER_BORROW' in r.stderr
 else:
  row['passed']=r.returncode==0 and 'error(' not in r.stderr and 'W_NOALLOC_ALLOCATES' not in r.stderr
  if r.returncode==0:
   executed=subprocess.run([str(binary)],env=dict(env,MYL_CORE_LEAKCHECK='1'),capture_output=True,text=True,timeout=120)
   row['run']={'status':executed.returncode,'stdout':executed.stdout,'stderr':executed.stderr};row['passed'] &=executed.returncode==0 and not executed.stderr
   row['binary_sha256']=sha(binary);row['llvm_sha256']=sha(llvm)
 report['cases'][name]=row;print(name,row['passed'],flush=True)
report['passed']=all(row['passed'] for row in report['cases'].values());(a.output/'results.json').write_text(json.dumps(report,indent=2)+'\n');raise SystemExit(0 if report['passed'] else 1)
