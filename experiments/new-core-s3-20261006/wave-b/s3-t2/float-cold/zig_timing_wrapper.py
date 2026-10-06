#!/usr/bin/env python3
import json, os, subprocess, sys, time
argv = sys.argv[1:]
if argv == ['version']:
    print(os.environ['S3_ACTUAL_ZIG_VERSION'] + os.environ.get('S3_SIMULATED_ZIG_SUFFIX', ''))
    raise SystemExit(0)
env = os.environ.copy()
if argv[:1] == ['build-obj']:
    env['ZIG_GLOBAL_CACHE_DIR'] = env['S3_FLOAT_ZIG_CACHE']
start = time.monotonic()
child = subprocess.run([os.environ['S3_ACTUAL_ZIG'], *argv], env=env)
with open(env['S3_FLOAT_TOOL_TIMINGS'], 'a') as log:
    log.write(json.dumps({'phase': env['S3_FLOAT_PHASE'], 'args': argv, 'seconds': time.monotonic()-start, 'status': child.returncode})+'\n')
raise SystemExit(child.returncode)
