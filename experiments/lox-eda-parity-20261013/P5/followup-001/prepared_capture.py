#!/usr/bin/env python3
"""Prepared CPU capture only. Invoke under coordinator-approved admission."""
import hashlib
import json
import os
from pathlib import Path
import signal
import shutil
import subprocess
import sys

HERE = Path(__file__).resolve().parent
SPEC = HERE / 'prepared-common001-profile.json'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    spec = json.loads(SPEC.read_text())
    assert digest(Path(spec['binary'])) == spec['binary_sha256']
    if len(sys.argv) > 1 and sys.argv[1] == 'workload':
        output = Path(spec['argv'][spec['argv'].index('--out-dir') + 1])
        assert output.is_relative_to(Path(__file__).resolve().parents[4] / '.tmp/lox-eda-parity/P5/followup-001')
        runs = []
        for _ in range(spec['repeats']):
            shutil.rmtree(output, ignore_errors=True)
            guest = subprocess.Popen(spec['argv'], cwd=spec['cwd'], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            try:
                stdout, stderr = guest.communicate(timeout=spec['guest_timeout_seconds'])
            except subprocess.TimeoutExpired:
                guest.kill()
                guest.communicate()
                raise
            assert guest.returncode == 0
            row = {'stdout': hashlib.sha256(stdout).hexdigest(),
                         'stderr': hashlib.sha256(stderr).hexdigest(),
                         'files': {str(p.relative_to(output)): digest(p)
                                   for p in sorted(output.rglob('*')) if p.is_file()}}
            assert row == spec['expected_output'], row
            runs.append(dict(row, guest_pid=guest.pid))
        (HERE / 'current-common001-profile-outputs.json').write_text(json.dumps(runs, indent=2) + '\n')
        return
    inputs = json.loads((HERE / 'prepared-project-inputs.json').read_text())
    for name, expected in inputs['files'].items():
        assert digest(Path(inputs['project_dir']) / name) == expected, name
    for name, expected in spec['input_file_digests'].items():
        assert digest(Path(name)) == expected, name
    assert sorted(os.sched_getaffinity(0)) == [spec['cpu']]
    command = ['perf', 'record', '-q', '-e', spec['event'], '-F', str(spec['frequency']),
               '--call-graph', spec['call_graph'], '-o', spec['record_file'], '--',
               sys.executable, str(__file__), 'workload']
    with (HERE / 'current-common001-perf.log').open('w') as stream:
        process = subprocess.Popen(command, stdout=stream, stderr=subprocess.STDOUT,
                                   env=dict(os.environ, **spec['environment']), start_new_session=True)
        try:
            status = process.wait(timeout=spec['record_timeout_seconds'])
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGTERM)
            try:
                process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
            status = 124
    (HERE / 'current-common001-profile-result.json').write_text(json.dumps({
        'returncode': status, 'command': command, 'spec_sha256': digest(SPEC),
        'driver_sha256': digest(Path(__file__)), 'cpu_affinity': sorted(os.sched_getaffinity(0)),
        'raw_sha256': digest(Path(spec['record_file'])) if Path(spec['record_file']).exists() else None,
        'label': 'CPU attribution only; no runtime comparison'}, indent=2) + '\n')
    raise SystemExit(status)


if __name__ == '__main__':
    main()
