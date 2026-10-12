#!/usr/bin/env python3
"""Archive ordinary retained requests and their exact coordinator reports."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time

root = Path(sys.argv[1]).resolve()
output = Path(sys.argv[2]).resolve()
output.mkdir(parents=True, exist_ok=True)
zig = '/home/epentland/zig-toolchains/0.17.0-dev.1683+5ceec001b/zig'
with (output/'stderr.log').open('wb') as errors:
    child = subprocess.Popen([sys.executable,'scripts/cache_session.py'], cwd=root,
                             env=os.environ.copy(), stdin=subprocess.PIPE,
                             stdout=subprocess.PIPE,stderr=errors,text=True)
    responses=[]
    try:
        force_first = '--force-first' in sys.argv[3:]
        for index in range(3 if force_first else 2):
            request={'id':'retained-%d'%index,'command':'verify','args':['--zig',zig]}
            if force_first and index == 0:
                request['args'].append('--force')
            start=time.monotonic()
            child.stdin.write(json.dumps(request)+'\n');child.stdin.flush()
            line=child.stdout.readline()
            if not line:
                raise RuntimeError('retained process ended without response')
            response=json.loads(line)
            responses.append({'request':request,'response':response,'elapsed_seconds_including_queue':time.monotonic()-start})
            (output/'responses.json').write_text(json.dumps(responses,indent=2)+'\n')
            source=root/'.mylang-cache/verification-v1/last-run.json'
            if source.exists():
                label = 'report-%d.json'%index if response.get('status') == 0 else 'report-%d-observed-failure.json'%index
                shutil.copyfile(source,output/label)
            inventory = root/'zig-out/verification/inventory.json'
            if inventory.exists():shutil.copyfile(inventory,output/('inventory-%d.json'%index))
            if response.get('status') != 0:
                break
        child.stdin.write(json.dumps({'id':'stop','command':'stop'})+'\n');child.stdin.flush()
        stop=child.stdout.readline()
        (output/'stop.json').write_text(stop)
        child.stdin.close()
        status=child.wait()
        if any(item['response'].get('status') != 0 or item['response'].get('ok') is not True for item in responses):
            status = status or 1
    finally:
        if child.poll() is None:
            child.terminate();child.wait()
print(json.dumps({'status':status,'requests':len(responses)}))
raise SystemExit(status)
