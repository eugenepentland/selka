#!/usr/bin/env python3
"""Exercise cache reuse and invalidation in private copies of PCB and small fixtures.

Usage: verify_pcb_latency.py COMPILER PCB_PROJECT OUTPUT_DIRECTORY
The output directory must not exist. The compiler installation is used read-only.
No production project files or journals are changed. Nonzero exit means a cache
correctness/reuse assertion failed; JSON evidence is written even on failure.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import time


def reports(text):
    result = []
    for line in text.splitlines():
        if not line.startswith('{'):
            continue
        try:
            result.append(json.loads(line))
        except ValueError:
            continue
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('compiler', type=Path)
    parser.add_argument('project', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    compiler, project, output = (path.resolve() for path in (args.compiler, args.project, args.output))
    output.mkdir(parents=True, exist_ok=False)
    guest = output / 'guest'
    guest.mkdir()
    for source in (project / 'guest').glob('*.my'):
        shutil.copy2(source, guest / source.name)
    env = dict(os.environ)
    env['PATH'] = str(compiler.parent) + os.pathsep + env['PATH']
    env['PWD'] = str(output)
    env['MYLANG_JOBS'] = '2'
    observations, failures = [], []
    manifest = {'compiler': str(compiler), 'compiler_sha256': hashlib.sha256(compiler.read_bytes()).hexdigest(),
                'source_hashes': {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in guest.glob('*.my')}}
    (output / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')

    def run(label, args, expected=0, environment=None):
        start = time.monotonic()
        argv = [str(compiler), *map(str, args)]
        process = subprocess.Popen(argv, cwd=output, env=env if environment is None else environment,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True)
        try:
            stdout, stderr = process.communicate(timeout=600)
            code = process.returncode
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            stdout, stderr = process.communicate()
            code = 'timeout'
        duration = time.monotonic() - start
        text = stderr.decode(errors='replace')
        row = {'label': label, 'argv': argv, 'seconds': duration, 'exit_code': code,
               'reports': reports(text), 'stdout': stdout.decode(errors='replace')}
        observations.append(row)
        (output / (label + '.stdout')).write_bytes(stdout)
        (output / (label + '.stderr')).write_bytes(stderr)
        if code != expected:
            failures.append(f'{label}: exit {code}, expected {expected}')
        (output / 'observations.json').write_text(json.dumps(observations, indent=2) + '\n')
        print(f'{label}: {duration:.3f}s, exit {code}', flush=True)
        return row

    def work(row, command):
        found = [r for r in row['reports'] if r.get('version') == 'work-report-v1' and r.get('command') == command]
        if not found:
            failures.append(f"{row['label']}: missing {command} work report")
            return {}
        return found[-1]

    def no_work(row, command, stages):
        report = work(row, command)
        for stage in stages:
            value = report.get(stage, {}).get('performed')
            if value != 0:
                failures.append(f"{row['label']}: {stage} performed={value}, expected 0")

    cache = output / 'test-cache'
    test_args = ['test', guest / 'geom.my', f'--cache-dir={cache}', '--max-steps=4294967295', '--report', '--json']
    run('geom-cold', test_args)
    run('geom-warm', test_args)
    warm = run('geom-warm-repeat', test_args)
    no_work(warm, 'test', ['checked_bodies', 'lowered_functions', 'emitted_fragments', 'executed_tests'])
    unrelated_env = dict(env, PCB_AUDIT_IRRELEVANT='changed')
    changed_env = run('geom-unused-env', test_args, environment=unrelated_env)
    no_work(changed_env, 'test', ['checked_bodies', 'lowered_functions', 'emitted_fragments', 'executed_tests'])
    unrelated = guest / 'png.my'
    original = unrelated.read_bytes()
    unrelated.write_bytes(original + b'\n# An unreachable source change in an audit copy.\n')
    changed_source = run('geom-unrelated-source', test_args)
    no_work(changed_source, 'test', ['checked_bodies', 'lowered_functions', 'emitted_fragments', 'executed_tests'])
    unrelated.write_bytes(original)

    fixture = output / 'fixture'
    fixture.mkdir()
    (fixture / 'main.my').write_text('''module main
import calc
public def test_value() -> bool:
    return calc.value() == 3

def main(out: Stream) -> int:
    out.print(calc.value())
    return 0
''')
    dependency = fixture / 'calc.my'
    dependency.write_text('module calc\npublic def value() -> int:\n    return 3\n')
    test = ['test', fixture / 'main.my', f'--cache-dir={output / "fixture-test-cache"}', '--report', '--json']
    execute = ['run', fixture / 'main.my', f'--cache-dir={output / "fixture-run-cache"}',
               f'--qbe={compiler.parent / "qbe"}', '--timings=json']
    run('fixture-test-cold', test)
    first = run('fixture-run-cold', execute)
    second = run('fixture-run-warm', execute)
    for row in [first, second]:
        if row['stdout'].strip() != '3':
            failures.append(f"{row['label']}: wrong guest output")
    no_work(second, 'run', ['lowered_functions', 'emitted_fragments'])
    dependency.write_text('module calc\npublic def value() -> int:\n    return 4\n')
    run('fixture-test-changed', test, expected=1)
    changed = run('fixture-run-changed', execute)
    if changed['stdout'].strip() != '4':
        failures.append('fixture-run-changed: stale executable result')
    report = work(changed, 'run')
    if report.get('emitted_fragments', {}).get('performed', 0) == 0:
        failures.append('fixture-run-changed: dependency changed without fresh emission')
    summary = {'passed': not failures, 'failures': failures, 'observations': len(observations)}
    (output / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
    print(json.dumps(summary), flush=True)
    return 0 if summary['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
