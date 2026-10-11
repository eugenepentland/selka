#!/usr/bin/env python3
"""Preserve resource refusals and reject borrowed results or mutable map callbacks."""
import argparse,importlib.util,json,os,subprocess,sys
from pathlib import Path
sys.dont_write_bytecode=True
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[1]
spec=importlib.util.spec_from_file_location('previous',HERE.parent/'zero-rc-final-20261011/boundaries.py')
previous=importlib.util.module_from_spec(spec);spec.loader.exec_module(previous)

def main():
 p=argparse.ArgumentParser(description=__doc__)
 for key in ('compiler','zig','output'):p.add_argument('--'+key,type=Path,required=True)
 a=p.parse_args()
 for key in ('compiler','zig','output'):setattr(a,key,getattr(a,key).resolve())
 a.output.mkdir(parents=True,exist_ok=True)
 cases=dict(previous.CASES)
 cases['map-borrowed-result']=('E_SINGLE_OWNER_BORROW','''import parallel
func alias(value: str) -> str:
    return value
func main() -> int:
    const result = parallel.map(["item-" + str(1)], alias)
    return len(result)
''')
 cases['map-mut-callback']=('E_TYPE','''import parallel
func change(mut value: int[]) -> int:
    value.clear()
    return 0
func main() -> int:
    const result = parallel.map([[1, 2]], change)
    return len(result)
''')
 result={'compiler_sha256':previous.digest(a.compiler),'refusals':{}}
 env=dict(os.environ,ZIG=str(a.zig),MYLANG_ZIG=str(a.zig))
 for name,(code,source) in cases.items():
  d=a.output/name;d.mkdir(parents=True,exist_ok=True);path=d/'main.my';path.write_text(source);binary=d/'program'
  ran=subprocess.run([str(a.compiler),'build',str(path),'--experimental-zero-rc','--cache-dir',str(a.output/'cache'),'-o',str(binary)],cwd=ROOT,env=env,capture_output=True,text=True,timeout=120)
  (d/'stderr').write_text(ran.stderr)
  assert ran.returncode!=0 and f'error[{code}]' in ran.stderr,(name,ran.returncode,ran.stderr)
  assert not binary.exists()
  result['refusals'][name]={'status':ran.returncode,'stderr':ran.stderr,'source_sha256':previous.digest(path)}
 (a.output/'results.json').write_text(json.dumps(result,indent=2)+'\n');(HERE/'boundaries.json').write_text(json.dumps(result,indent=2)+'\n')
 print(len(cases),'refusals passed')
if __name__=='__main__':main()
