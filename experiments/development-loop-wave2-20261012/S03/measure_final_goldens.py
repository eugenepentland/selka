#!/usr/bin/env python3
"""Compare old/new golden preparation using one authenticated repaired compiler."""
import argparse
import json
import os
from pathlib import Path
import signal
import time

import measure_boundaries as boundary

OUT = Path(__file__).resolve().parent
PREFIX = Path('/home/epentland/ai/canopy/mylang-dl-wave2-20261012-integration/.tmp/frozen-final-candidate')
EXPECTED = 'cc827c4e79243f299dc92327fa86049669307d1f0edfa816a5b641dc443176b0'

def authenticate_repair():
    manifest = json.loads((PREFIX / 'manifest.json').read_text())
    assert manifest['sha256'] == EXPECTED
    assert manifest['source_commit'] == '9d1b51f310477e4ceccffd8ad41ecf6fc2156e13'
    assert boundary.digest(PREFIX / 'manifest.json') == 'f11fb105af095c1c919ea41ad8db77e0eb328b8425f3f6892ba6f4dfb01ff467'
    for path, expected in manifest['files'].items():
        assert boundary.digest(PREFIX / path) == expected, path
    boundary.COMPILERS = {label:{'path':str(PREFIX / 'bin/mylang'),'sha256':EXPECTED,'source':manifest['source_commit'],
                              'scope':'same final Debug compiler; final qualified fixed-seed components; exact final prefix manifest'} for label in ('C0','B0')}
    authority = boundary.authenticate()
    authority.update({str(PREFIX / path):boundary.stamp(PREFIX / path) for path in manifest['files']})
    for label in ('C0','B0'):
        artifact = boundary.SCRATCH / f'golden-{label}-final/install/bin/s03-replayed-tests'
        assert artifact.is_file(), artifact
        authority[str(artifact)] = boundary.stamp(artifact)
    return authority, manifest

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('mode', choices=('operational','timing'))
parser.add_argument('--label', choices=('C0','B0'), required=True)
parser.add_argument('--sample', type=int, required=True)
parser.add_argument('--tier', choices=('cold','warm'), default='warm')
parser.add_argument('--timeout', type=float, default=240)
args = parser.parse_args()
def interrupted(signum, frame):
    raise TimeoutError('golden window interrupted')
signal.signal(signal.SIGTERM, interrupted)
authority, manifest = authenticate_repair()
label = args.label
artifact = boundary.SCRATCH / f'golden-{label}-final/install/bin/s03-replayed-tests'
store = boundary.SCRATCH / (f'golden-final-cold-{args.sample:02d}-{label}' if args.tier=='cold' else f'golden-final-{args.mode}-warm-{args.sample:02d}-{label}')
assert not store.exists(), store
store.mkdir(exist_ok=True)
env = boundary.environment()
env.update(ZIG_LOCAL_CACHE_DIR=str(store/'local'),MYLANG_CORE_RUNTIME_CACHE=str(store/'runtime'),TMPDIR=str(boundary.ROOT/'.tmp/work'),
           ZIG_GLOBAL_CACHE_DIR=str(store/'global') if args.tier=='cold' else '/home/epentland/ai/canopy/.zig-global-cache')
name = f'golden-final-{args.mode}-{args.tier}-{args.sample:02d}-{label}'
row, text = boundary.measure([artifact],boundary.SCRATCH/label,env,name,args.timeout)
match = boundary.GOLDEN.search(text)
assert match and tuple(map(int,match.groups()))==(222,167,55,382,0), text[-2000:]
if label=='B0':
    prep = boundary.PREPARED.search(text)
    assert prep and tuple(map(int,prep.groups()))==(222,165,66752,222), text[-2000:]
assert row['selected']==[1] and row['verdicts'][0]['passed']==1
for path, expected in authority.items():
    assert boundary.stamp(path)==expected, path
report = {'schema':'s03-repaired-golden-measurement-v1','mode':args.mode,'label':label,'sample':args.sample,'tier':args.tier,
          'compiler':boundary.COMPILERS[label],'compiler_manifest_sha256':boundary.digest(PREFIX/'manifest.json'),
          'compiler_component_scope':manifest['components_scope'],'artifact_sha256':boundary.digest(artifact),'artifact_bytes':artifact.stat().st_size,
          'checked_cases':222,'actual_compiler_executions':222,'fresh_mutable_work_dirs':222,'mismatches':0,
          'source_writes':222 if label=='C0' else 165,'source_bytes':90182 if label=='C0' else 66752,
          'warmth':'shared Zig global warm; fresh private runtime per sample, program/cache/source preparation fresh each process' if args.tier=='warm' else 'fresh private Zig global/runtime; compiler/component generation excluded; program/cache fresh',
          'cpu_affinity':sorted(os.sched_getaffinity(0)),'harness_sha256':boundary.digest(__file__),
          'measurement_helper_sha256':boundary.digest(boundary.__file__),'scope':'controlled fixture comparison; not old-vs-new compiler speed or seed/bootstrap acceptance','row':row}
out = OUT / (name+'.json')
assert not out.exists(), out
out.write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps({'mode':args.mode,'label':label,'sample':args.sample,'tier':args.tier,'wall_s':row['wall_s'],'checked_cases':222,'mismatches':0}))
