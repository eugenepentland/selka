#!/usr/bin/env python3
"""Compile/run migrated library fixtures, optionally using editable project mirrors."""
import argparse, hashlib, json, os, re, subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent

def main():
 p=argparse.ArgumentParser()
 p.add_argument('--compiler',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
 p.add_argument('--zig',type=Path,required=True);p.add_argument('--overlay',action='store_true');p.add_argument('--cases',nargs='*')
 a=p.parse_args();a.compiler=a.compiler.resolve();a.output=a.output.resolve();a.zig=a.zig.resolve()
 env=dict(os.environ,ZIG=str(a.zig),MYLANG_ZIG=str(a.zig),MYL_CORE_LEAKCHECK='1')
 env.pop('MYLANG_COUNTERS',None)
 result={}
 for original in sorted((ROOT/'src/stdlib/fixtures').glob('*.my')):
  name=original.stem
  if name=='time_random_provider' or (a.cases and name not in a.cases):continue
  directory=a.output/name;directory.mkdir(parents=True,exist_ok=True)
  migrated=HERE/'samples'/original.name
  source=migrated.read_text() if migrated.exists() else original.read_text()
  mirrors={'strings','path','sort','pool','json','base64','hex','byte_builder'}
  def rename(text):return re.sub(r'^import (\w+)$',lambda m:'import own_'+m[1]+' as '+m[1] if m[1] in mirrors else m[0],text,flags=re.M)
  if a.overlay:
   for lib in (ROOT/'src/stdlib').glob('*.my'):
    if lib.stem in mirrors:(directory/('own_'+lib.name)).write_text(rename(lib.read_text()))
   source=rename(source)
  path=directory/'main.my';path.write_text(source);binary=directory/'program'
  argv=list(map(str,[a.compiler,'build',path,'--experimental-zero-rc','--unoptimized','--counters','--zig',a.zig,'--cache-dir',a.output/'cache','-o',binary,'--emit-llvm',directory/'program.ll']))
  built=subprocess.run(argv,cwd=ROOT,env=env,capture_output=True,text=True,timeout=300)
  (directory/'build.stderr').write_text(built.stderr)
  record={'build_status':built.returncode,'stderr':built.stderr,'source_sha256':hashlib.sha256(path.read_bytes()).hexdigest()}
  if built.returncode==0:
   ran=subprocess.run([str(binary)],env=dict(env,MYLANG_COUNTERS=str(directory/'counts.json')),capture_output=True,text=True,timeout=120)
   record.update(status=ran.returncode,stdout=ran.stdout,run_stderr=ran.stderr)
   print(name,'run',ran.returncode,ran.stderr[:700],flush=True)
  else:print(name,built.stderr[:1200],flush=True)
  result[name]=record
 (a.output/'results.json').write_text(json.dumps(result,indent=2)+'\n')
if __name__=='__main__':main()
