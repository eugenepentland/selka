#!/usr/bin/env python3
"""Retain actual native descendants separately from full Core helper reads."""
import ast
import hashlib
import json
import re
from pathlib import Path

ROOT=Path('/home/epentland/ai/canopy/mylang-worktrees/codex-new-core-s4-frontend')
HERE=ROOT/'experiments/new-core-s4-frontend-20261006/c-prep-full-closure-audit-01'
WORK=ROOT/'.mylang-cache/s4-frontend/c-prep-full-closure-audit-01'
EARLIER=ROOT/'experiments/new-core-s4-frontend-20261006/c-prep-action-closure-01'
namespace={'__file__':str(EARLIER/'analyze.py')}
exec((EARLIER/'analyze.py').read_text().split('\nnames = ')[0],namespace)
text=(WORK/'full.strace').read_text()
edges={}
roots=[]
# The raw trace gives clone ownership; unfinished returns are joined below.
lines=text.splitlines()
for number,line in namespace['joined'](text):
    pid=lines[number-1].split()[0]
    match=re.match(r'^(clone|clone3|fork|vfork)\(.*\)\s+=\s+(\d+)',line)
    if match:edges.setdefault(pid,set()).add(match.group(2))
    if line.startswith('execve(') and '/zig",' in line and '"cc",' in line:
        quoted=re.search(r'\[([^\]]+)\]',line)
        if quoted:
            argv=[ast.literal_eval(x) for x in re.findall(r'"(?:[^"\\]|\\.)*"',quoted.group(1))]
            if argv[0]==str(namespace['TOOL']):roots.append({'pid':pid,'argv':argv,'line':number})
for raw in lines:
    match=re.match(r'^(\d+) \+\+\+ superseded by execve in pid (\d+) \+\+\+$',raw)
    if match:edges.setdefault(match.group(2),set()).add(match.group(1))
assert len(roots)==2,roots
for root in roots:
    family={root['pid']};changed=True
    while changed:
        before=len(family)
        for pid in list(family):family.update(edges.get(pid,()))
        changed=len(family)!=before
    label='runtime-c' if '-c' in root['argv'] else 'program-link'
    trace='\n'.join(line for line in lines if line.split()[0] in family)+'\n'
    (HERE/(label+'.strace')).write_text(trace)
    (HERE/(label+'.json')).write_text(json.dumps({'command':root['argv'],'cwd':str(WORK),'status':0,
        'pids':sorted(family),'object':None,'scope':'Native subtree from the successful actual immutable Core build.'},indent=2)+'\n')
    namespace['HERE']=HERE
    result=namespace['summary'](label)
    (HERE/(label+'-summary.json')).write_text(json.dumps(result,indent=2)+'\n')
    print(label,'pids',len(family),'bytes',len(trace),'paths',result['path_count'],
          'outside reads',result['external_content_reads_not_in_inventory'])
