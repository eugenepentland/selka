#!/usr/bin/env python3
"""Retain source-pinned RF evidence without changing compiler inputs."""
import gzip
import hashlib
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / '.mylang-cache/goal110-integrated-rf-20261004'
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / 'benchmarks/runtime/diagnostics'))
import holdouts


def sha(data):
    return hashlib.sha256(data).hexdigest()


manifest_path = WORK / 'runner/manifest.json'
manifest = json.loads(manifest_path.read_text())
holdouts.check_manifest(manifest_path, sha(manifest_path.read_bytes()), manifest)
assert holdouts.verify(json.loads((WORK / 'holdouts.json').read_text())) == 516
reports = [json.loads((WORK / ('confirmation-' + session + '.json')).read_text())
           for session in ('a', 'b')]
assert reports[0]['measurement_session_id'] != reports[1]['measurement_session_id']
for report in reports:
    assert report['identity'] == report['identity_after'] == manifest['identity']
    assert report['binary_hashes'] == report['binary_hashes_after'] == manifest['binary_hashes']
    assert len(report['samples']) == len(report['qualification']) == 720

reference = Path('/home/epentland/ai/canopy/mylang-worktrees/runtime-parity-harness-20261003/'
                 '.mylang-cache/runtime-candidate-730a86e6-releasefast/runner/manifest.json')
inputs = [(WORK / name, name) for name in (
    'compiler-receipt.json', 'compiler-build.log',
    'guests-build-driver.log', 'text-guest-checks.json', 'holdouts.json', 'holdouts.log',
    'confirmation-a.json', 'confirmation-a.log', 'confirmation-b.json', 'confirmation-b.log',
    'validation.log')]
inputs += [(manifest_path, 'manifest.json'), (reference, 'reference-manifest.json')]
retained = []
for source, name in inputs:
    raw = source.read_bytes()
    target = HERE / (name + '.gz')
    target.write_bytes(gzip.compress(raw, mtime=0))
    retained.append({'raw': str(source), 'raw_sha256': sha(raw),
                     'archive': str(target.relative_to(ROOT)),
                     'archive_sha256': sha(target.read_bytes())})
commands = json.loads((HERE / 'commands.json').read_text())
record = {'source_revision': '957f97c6d9906ef11cf344ce055dada8be8446ea',
          'candidate_id': 'goal110-integrated-957f97c6-releasefast',
          'compiler_policy': 'ReleaseFast host; ReleaseFast guests; LLVM O3/full LTO; unchanged references',
          'status': 'two RF sessions complete; coordinator acceptance review is separate',
          'sessions': [{key: report[key] for key in ('measurement_session_id', 'started_utc', 'finished_utc')}
                       for report in reports],
          'commands': commands, 'retained': retained,
          'provenance_limit': 'Local source and live artifact checks; no independent reproducibility attestation.'}
(HERE / 'evidence.json').write_text(json.dumps(record, indent=2) + '\n')
print('PASS live source/assets/all24 identity, two unique sessions, 516 holdout replay; archives bound')
