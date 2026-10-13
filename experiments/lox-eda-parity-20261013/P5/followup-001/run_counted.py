#!/usr/bin/env python3
"""Frozen common001 source with two overlays; full-input counters, no timing."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[4]
HERE = Path(__file__).resolve().parent
WORK = ROOT / '.tmp/lox-eda-parity/P5/followup-001'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    identity = json.loads((HERE / 'inputs.json').read_text())
    compiler = identity['compiler']
    assert digest(Path(compiler)) == identity['compiler_sha256']
    spec = json.loads((ROOT / 'experiments/lox-eda-zero-rc-20261012/bench/frozen-specs/eda-rds3+flat.json').read_text())
    output = WORK / 'output-rds3-flat'
    env = dict(os.environ, MYL_CORE_LEAKCHECK='1')
    results = []
    for phase in ('baseline', 'candidate'):
        directory = WORK / phase
        manifest = {str(p.relative_to(directory)): digest(p)
                    for p in sorted(directory.rglob('*.my'))}
        argv = [str(ROOT / 'scripts/build-slot.sh'), 'build', compiler, 'build',
                str(directory / 'main.my'), '--release', '--experimental-zero-rc',
                '--counters', '--cache-dir', str(directory / 'cache'),
                '-o', str(directory / 'eda'), '--emit-llvm', str(directory / 'eda.ll')]
        with (HERE / f'{phase}-build.log').open('w') as stream:
            status = subprocess.run(argv, cwd=ROOT, env=env, stdout=stream,
                                    stderr=subprocess.STDOUT).returncode
        row = {'phase': phase, 'source_manifest': manifest, 'build_command': argv,
               'build_returncode': status, 'compiler_sha256': identity['compiler_sha256']}
        (HERE / f'{phase}-receipt.json').write_text(json.dumps(row, indent=2) + '\n')
        assert status == 0, phase
        row['binary_sha256'] = digest(directory / 'eda')
        row['llvm_sha256'] = digest(directory / 'eda.ll')
        assert output.is_relative_to(WORK)
        shutil.rmtree(output, ignore_errors=True)
        args = spec['arms']['zig-safe'][1:].copy()
        args[args.index('--out-dir') + 1] = str(output)
        command = [str(ROOT / 'scripts/build-slot.sh'), 'build', 'timeout', '30',
                   str(directory / 'eda'), *args]
        run_env = dict(env, MYLANG_COUNTERS=str(HERE / f'{phase}-counters.json'))
        result = subprocess.run(command, cwd=spec['cwd'], env=run_env, capture_output=True)
        (HERE / f'{phase}-stdout.txt').write_bytes(result.stdout)
        (HERE / f'{phase}-stderr.txt').write_bytes(result.stderr)
        row['run_command'] = command
        row['run_returncode'] = result.returncode
        row['stdout_sha256'] = hashlib.sha256(result.stdout).hexdigest()
        row['stderr_sha256'] = hashlib.sha256(result.stderr).hexdigest()
        row['output_files'] = {str(p.relative_to(output)): digest(p)
                               for p in sorted(output.rglob('*')) if p.is_file()}
        (HERE / f'{phase}-receipt.json').write_text(json.dumps(row, indent=2) + '\n')
        assert result.returncode == 0 and row['output_files'], phase
        counts = json.loads((HERE / f'{phase}-counters.json').read_text())
        assert counts['totals']['live_bytes_at_exit'] == 0
        assert all(counts['totals'][k] == 0 for k in ('runtime_retains', 'runtime_releases', 'shared_retains', 'shared_releases'))
        assert counts['kinds']['unique_test']['count'] == 0
        row['totals'] = counts['totals']
        row['counters_sha256'] = digest(HERE / f'{phase}-counters.json')
        (HERE / f'{phase}-receipt.json').write_text(json.dumps(row, indent=2) + '\n')
        results.append(row)
    b, c = results
    assert b['stdout_sha256'] == c['stdout_sha256']
    # Admission messages vary; guest diagnostics are compared after those lines.
    def guest_stderr(phase):
        return b'\n'.join(line for line in (HERE / f'{phase}-stderr.txt').read_bytes().splitlines()
                          if not line.startswith(b'build-slot:'))
    assert guest_stderr('baseline') == guest_stderr('candidate')
    assert b['output_files'] == c['output_files']
    assert [k for k in b['source_manifest'] if b['source_manifest'][k] != c['source_manifest'][k]] == ['kicad_sch_compose.my', 'kicad_sch_textbox.my']
    (HERE / 'comparison.json').write_text(json.dumps({'same_stdout': True, 'same_guest_stderr': True,
        'same_output_files': True, 'label': 'single full-input allocation counters; no timing/RSS/parity claim',
        'baseline': b['totals'], 'candidate': c['totals']}, indent=2) + '\n')


if __name__ == '__main__':
    main()
