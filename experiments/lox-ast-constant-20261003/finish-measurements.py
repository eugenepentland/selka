#!/usr/bin/env python3
"""Continue only after the exact wall command completes successfully."""
import datetime
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time

work = Path(__file__).resolve().parent
repo = work.parent
measurements = work / 'measurements'
record_path = work / 'sequence.json'
if record_path.exists():
    raise ValueError('refusing to overwrite sequence receipt')


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


helpers = [Path(__file__).resolve(), repo / 'experiments/lox-parity-20261003/run.py',
           repo / 'experiments/lox-performance-audit-20261002/audit.py',
           repo / 'experiments/lox-ast-constant-20261003/analyze.py',
           repo / 'experiments/lox-perf-improvements-20261002/analyze.py']
manifest_path = work / 'binaries.json'
manifest_hash = sha(manifest_path)
manifest = json.loads(manifest_path.read_text())
helper_hashes = {str(path): sha(path) for path in helpers}
record = {'pid': os.getpid(), 'started_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
          'manifest_sha256': manifest_hash, 'helpers_sha256': helper_hashes,
          'stage': 'waiting_wall', 'commands': []}


def save():
    record_path.write_text(json.dumps(record, indent=2) + '\n')


def verify_inputs():
    assert sha(manifest_path) == manifest_hash
    assert {str(path): sha(path) for path in helpers} == helper_hashes
    for source in manifest['candidate_sources'].values():
        root = Path(source['path'])
        current = {str(path.relative_to(root)): sha(path)
                   for path in sorted(root.rglob('*')) if path.is_file()}
        assert current == source['all_files']
    for name, path in manifest['binaries'].items():
        assert sha(Path(path)) == manifest['binary_sha256'][name]
    assert sha(Path(manifest['compiler'])) == manifest['compiler_sha256']
    assert sha(Path(manifest['qbe'])) == manifest['qbe_sha256']


def run(argv, label):
    verify_inputs()
    log = work / (label + '.log')
    if log.exists():
        raise ValueError('refusing to overwrite sequence log')
    command = {'argv': argv, 'cwd': str(repo), 'log': str(log)}
    record['commands'].append(command)
    save()
    with log.open('w') as output:
        result = subprocess.run(argv, cwd=repo, stdout=output, stderr=subprocess.STDOUT)
    command.update(status=result.returncode, log_sha256=sha(log))
    save()
    if result.returncode:
        raise RuntimeError(f'{label} failed: {result.returncode}')
    verify_inputs()


save()
try:
    deadline = time.monotonic() + 7200
    command_path = measurements / 'source-timing.command.json'
    while True:
        command = json.loads(command_path.read_text())
        if 'status' in command:
            if command['status'] != 0 or not command.get('sources_verified_after'):
                raise RuntimeError('wall command failed or lacks final source check')
            break
        if time.monotonic() > deadline:
            raise TimeoutError('wall completion deadline')
        time.sleep(5)
    verify_inputs()
    record['stage'] = 'wall_analysis'
    run(['python3', 'experiments/lox-ast-constant-20261003/analyze.py',
         str(measurements / 'source-timing.json'), '--metric', 'wall_s', '--out',
         str(measurements / 'source-wall-analysis.json')], 'sequence-wall-analysis')
    record['stage'] = 'counters'
    run(['python3', 'experiments/lox-parity-20261003/run.py', 'counters', '--work', str(work),
         '--out', str(measurements / 'source-counters.json'), '--arms',
         'baseline-llvm,baseline-qbe,ast-llvm,ast-qbe,constant-llvm,constant-qbe,combined-llvm,combined-qbe,rust,go',
         '--tier', 'tree', '--rounds', '3', '--cpu', '10'], 'sequence-counters')
    record['stage'] = 'counter_analysis'
    run(['python3', 'experiments/lox-ast-constant-20261003/analyze.py',
         str(measurements / 'source-counters.json'), '--metric', 'instructions', '--out',
         str(measurements / 'source-counter-analysis.json')], 'sequence-counter-analysis')
    record.update(stage='complete', status=0, frozen_inputs_verified_after=True,
                  finished_utc=datetime.datetime.now(datetime.timezone.utc).isoformat())
    save()
    print(json.dumps({'complete': True, 'sequence': str(record_path)}), flush=True)
except Exception as error:
    record.update(stage='failed', status=1, error=str(error))
    save()
    raise
