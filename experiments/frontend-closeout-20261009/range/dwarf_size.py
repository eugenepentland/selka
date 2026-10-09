#!/usr/bin/env python3
"""Corroborate the size probe against the qualified binary's debug record."""
from collections import deque
import subprocess

binary='experiments/frontend-followthrough-20261009/external/artifacts/mylang-successor'
process=subprocess.Popen(['readelf','--debug-dump=info',binary],stdout=subprocess.PIPE,text=True)
prior=deque(maxlen=6)
for line in process.stdout:
    if 'DW_AT_name' in line and line.strip().endswith(': Statement') and any('0x27a' in old and 'DW_AT_decl_line' in old for old in prior):
        print('qualified typed.Statement record at prior source line634:')
        print(''.join(prior)+line,end='')
        for _ in range(4):print(next(process.stdout),end='')
        process.terminate()
        break
    prior.append(line)
process.wait()
