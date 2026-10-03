#!/usr/bin/env python3
"""Capture a new outer command and retain its raw streams/status."""
import json, os, pathlib, subprocess, sys, time

name, argv = sys.argv[1], sys.argv[2:]
base = pathlib.Path(__file__).resolve().parents[2] / '.tmp-lox-native-policy-20261003'
env = dict(os.environ, TMPDIR=str(base / 'tmp'), ZIG_GLOBAL_CACHE_DIR=str(base / 'global-cache'),
           MYLANG_TIMING_CPUS='2,3,10,11')
receipt = dict(argv=argv, cwd=os.getcwd(), environment={k: env[k] for k in
               ['TMPDIR', 'ZIG_GLOBAL_CACHE_DIR', 'MYLANG_TIMING_CPUS']}, started=time.time(), status=None)
destination = base / (name + '.command.json')
assert not destination.exists()
destination.write_text(json.dumps(receipt, indent=2) + '\n')
with (base / (name + '.stdout')).open('xb') as out, (base / (name + '.stderr')).open('xb') as err:
    result = subprocess.run(argv, env=env, stdout=out, stderr=err)
receipt.update(status=result.returncode, finished=time.time())
destination.write_text(json.dumps(receipt, indent=2) + '\n')
print(json.dumps(receipt))
sys.exit(result.returncode)
