#!/usr/bin/env python3
"""Command and shared-receipt checks for selected allocation/coverage lowering."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess

p=argparse.ArgumentParser()
p.add_argument('--compiler',type=Path,required=True)
p.add_argument('--scratch',type=Path,required=True)
p.add_argument('--output',type=Path,required=True)
p.add_argument('--start',type=int,default=0)
p.add_argument('--limit',type=int,default=10)
p.add_argument('--default',action='store_true')
a=p.parse_args()
compiler=a.compiler.resolve();compiler_hash=hashlib.sha256(compiler.read_bytes()).hexdigest();scratch=a.scratch.resolve();scratch.mkdir(parents=True,exist_ok=True)
source='''func prefix_length(text: str) -> int noalloc:
    const part = text.borrow(0, 2)
    return len(part)
public func test_view() -> bool:
    const text = "abcd" + str(7)
    return prefix_length(text) == 2
func main(out: Stream) -> int:
    out.print(prefix_length("abcd"))
    return 0
'''
bad='''\nfunc unused_bad() -> int noalloc:
    const data = [1]
    const moved = data
    return len(data)
'''
for name in ('one','two'):
 root=scratch/name;root.mkdir(exist_ok=True);(root/'mylang.json').write_text('{"version":2}\n');(root/'app.my').write_text(source)
cache=scratch/'cache';shared=scratch/'shared';first=scratch/'one/app.my';second=scratch/'two/app.my'
mode=[] if a.default else ['--experimental-zero-rc']
rows=[]
def row(name,args,status=0,needle=None,forbidden=None,before=None): rows.append(dict(name=name,args=args,status=status,needle=needle,forbidden=forbidden,before=before))
base=['--cache-dir',str(cache)]
relocated=['--cache-dir',str(scratch/'cache-two')]
row('coverage-owned',['coverage',str(first),*mode],needle='ok prefix_length',forbidden='refused')
row('coverage-negative',['coverage',str(first),*mode],1,'E_SINGLE_OWNER_MOVED',before='negative')
row('check-stats',['check',str(first),'--stats',*base,*mode],forbidden='W_NOALLOC_ALLOCATES',before='restore')
row('check-stats-warm',['check',str(first),'--stats',*base,*mode],forbidden='W_NOALLOC_ALLOCATES')
row('dump-ir',['dump-ir',str(first),*mode],needle='myl_core_view_slice',forbidden='W_NOALLOC_ALLOCATES')
row('build-owned',['build',str(first),'-o',str(scratch/'app'),'--emit-llvm',str(scratch/'app.ll'),*base,*mode],forbidden='W_NOALLOC_ALLOCATES')
row('run-owned',['run',str(first),*base,*mode],needle='2\n',forbidden='W_NOALLOC_ALLOCATES')
row('test-shared-first',['test',str(first),'--json','--shared-cache-dir',str(shared),*base,*mode],needle='test_view',forbidden='W_NOALLOC_ALLOCATES')
row('test-shared-relocated',['test',str(second),'--json','--shared-cache-dir',str(shared),*relocated,*mode],needle='test_view',forbidden='W_NOALLOC_ALLOCATES')
row('test-shared-unreachable-invalid',['test',str(second),'--json','--shared-cache-dir',str(shared),*relocated,*mode],1,'E_SINGLE_OWNER_MOVED',before='negative-second')
row('lint-owned',['lint',str(first),*base,*mode],forbidden='W_NOALLOC_ALLOCATES',before='restore')
row('noalloc-invalid-check',['check',str(first),'--stats',*base,*mode],1,'E_SINGLE_OWNER_MOVED',before='negative')
row('noalloc-invalid-build',['build',str(first),'-o',str(scratch/'bad'),*base,*mode],1,'E_SINGLE_OWNER_MOVED')
row('noalloc-invalid-lint',['lint',str(first),*base,*mode],1,'E_SINGLE_OWNER_MOVED')
if not a.default: row('coverage-ordinary-control',['coverage',str(first)],needle='refused borrowed views require --experimental-zero-rc',before='restore')
results=[]
for item in rows[a.start:a.start+a.limit]:
 if item['before']=='negative': first.write_text(source+bad)
 elif item['before']=='negative-second': second.write_text(source+bad)
 elif item['before']=='restore': first.write_text(source)
 argv=[str(compiler),*item['args']]
 r=subprocess.run(argv,text=True,capture_output=True,timeout=90,env=dict(os.environ,MYL_CORE_LEAKCHECK='0',MYLANG_CACHE_PLAN_MODE='component'))
 if hashlib.sha256(compiler.read_bytes()).hexdigest()!=compiler_hash: raise RuntimeError('compiler changed during qualification')
 text=r.stdout+r.stderr;passed=r.returncode==item['status'] and (item['needle'] is None or item['needle'] in text) and (item['forbidden'] is None or item['forbidden'] not in text)
 checks={}
 if item['name']=='build-owned' and r.returncode==0:
  llvm=(scratch/'app.ll').read_text();checks={'owned_marker':'; mylang-zero-rc-v2' in llvm,'no_retain': '@myl_core_retain(' not in llvm,'no_count_release': '@myl_core_release(' not in llvm};passed=passed and all(checks.values())
 if item['name'] in ('test-shared-first','test-shared-relocated') and r.returncode==0:
  report=json.loads(r.stdout);tests=report['tests'];checks.update(one_test=len(tests)==1,no_unsupported=report['unsupported']==0,no_failed=report['failed']==0)
  if item['name']=='test-shared-relocated': checks.update(shared_reuse=report['cached']==1,portable_key=tests[0]['cache']['key_method']=='portable-reachable-ir',shared_receipt=tests[0]['cache']['reason']=='shared-receipt-hit')
  passed=passed and all(checks.values())
 results.append(dict(name=item['name'],argv=argv,status=r.returncode,expected=item['status'],stdout=r.stdout,stderr=r.stderr,structural=checks,passed=passed))
 print(item['name'],r.returncode,'PASS' if passed else 'FAIL',flush=True)
report=dict(compiler=str(compiler),compiler_sha256=compiler_hash,leakcheck='0 for receipt eligibility; counted qualification is separate',default=a.default,source_sha256=hashlib.sha256(source.encode()).hexdigest(),negative_source_sha256=hashlib.sha256((source+bad).encode()).hexdigest(),results=results,success=all(x['passed'] for x in results))
a.output.write_text(json.dumps(report,indent=2)+'\n')
raise SystemExit(0 if report['success'] else 1)
