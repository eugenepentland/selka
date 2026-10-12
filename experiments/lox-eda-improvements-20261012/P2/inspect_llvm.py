#!/usr/bin/env python3
"""Record direct interpreter LLVM copy/cleanup calls without conflating callees."""
import hashlib
import json
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
s = path.read_text()
result = {'path':str(path.resolve()), 'sha256':hashlib.sha256(path.read_bytes()).hexdigest(), 'functions':{}}
for name in ('evaluate','execute','run_block','run_body','call_expr','class_declaration','interpret'):
    match = re.search(r'^define [^\n]*@"my.interpreter::' + name + r'"\([^\n]*\n.*?^}', s, re.M | re.S)
    assert match is not None, name
    calls = re.findall(r'(?:call|invoke)[^\n]*?@(?:"([^"]+)"|([^ (]+))', match.group())
    targets = sorted(set(a or b for a,b in calls))
    result['functions'][name] = {'memory_calls':[n for n in targets if any(k in n.lower() for k in ('copy','alloc','drop','destroy','retain','release','slice'))],
                                'copy_call_sites':sum('copy' in (a or b).lower() for a,b in calls),
                                'rc_calls':[n for n in targets if any(k in n.lower() for k in ('retain','release','unique_test'))]}
    assert not result['functions'][name]['rc_calls'], name
# These pure traversal functions must not copy an AST payload/list.
for name in (() if '--baseline' in sys.argv else ('evaluate','run_block','run_body','call_expr')):
    assert result['functions'][name]['copy_call_sites'] == 0, (name,result['functions'][name])
print(json.dumps(result,indent=2))
