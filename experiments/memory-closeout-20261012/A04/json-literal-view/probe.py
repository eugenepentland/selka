#!/usr/bin/env python3
"""Isolated same-compiler JSON literal comparison; production stays unchanged."""
import difflib, hashlib, json, os
from pathlib import Path
import subprocess, sys
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[3]
sys.path.insert(0,str(ROOT/'scripts'))
from build_admission import admission
compiler=ROOT.parent/'mylang-memory-20261012/.tmp/memory-closeout/coordinator/support7-install/bin/mylang'
sha='540283317dab8009ba38f7bc13a521b1b5048cff99701498acd56da7902259ef'
assert hashlib.sha256(compiler.read_bytes()).hexdigest()==sha
original=(ROOT/'src/stdlib/json.my').read_text()
needle='    if scanner.data[start:start + len(word)] != word:'
assert original.count(needle)==1
candidates={'original':original,'borrow':original.replace(needle,'    if scanner.data.borrow(start, start + len(word)) != word:'),
 'invalidated':original.replace(needle,'    const borrowed = scanner.data.borrow(start, start + len(word))\n    scanner.position = start + len(word)\n    if borrowed != word:')}
fixture=(ROOT/'src/stdlib/fixtures/json.my').read_text().replace('import json\n','import a04_json as json\n',1)
report={'compiler':str(compiler),'compiler_sha256':sha,'source_commit':'bed11cf3bf3102ffec44487e431a1573fdf02ad5','rows':{},'production_changed':False}
with admission('build'):
 for name,content in candidates.items():
  d=ROOT/'.tmp/memory-closeout/A04/json-literal-view'/name
  d.mkdir(parents=True,exist_ok=True)
  (d/'a04_json.my').write_text(content);(d/'main.my').write_text(fixture)
  for mode,flags in [('checked',['--experimental-zero-rc']),('ordinary',[])]:
   command=[str(compiler),'check',str(d/'main.my'),*flags]
   result=subprocess.run(command,capture_output=True,text=True,cwd=ROOT,timeout=120)
   report['rows'][name+'/'+mode]={'command':command,'source_sha256':hashlib.sha256(content.encode()).hexdigest(),'status':result.returncode,'stdout':result.stdout,'stderr':result.stderr}
   print(name,mode,result.returncode,result.stderr[:240],flush=True)
   (HERE/'source-checks.json').write_text(json.dumps(report,indent=2)+'\n')
(HERE/'proposed-json.patch').write_text(''.join(difflib.unified_diff(original.splitlines(True),candidates['borrow'].splitlines(True),fromfile='a/src/stdlib/json.my',tofile='b/src/stdlib/json.my')))
