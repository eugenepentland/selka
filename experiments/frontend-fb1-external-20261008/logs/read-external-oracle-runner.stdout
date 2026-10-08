#!/usr/bin/env python3
"""Freeze external corpus runtime answers with the unchanged acceptance rules."""
from __future__ import annotations

import argparse
import concurrent.futures
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import time

from frontend_oracle import command, digest


def lox(args):
    path = args.source / 'benchmarks/lox/harness/lox_bench.py'
    spec = importlib.util.spec_from_file_location('frontend_lox_rules', path)
    rules = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = rules
    spec.loader.exec_module(rules)
    selected = []
    for engine in ('vm', 'tree'):
        for stress in (False, True):
            for path in sorted(rules.CORPUS.rglob('*.lox')):
                relative = path.relative_to(rules.CORPUS).as_posix()
                if rules.skipped(relative, engine):
                    continue
                expected = rules.parse_expectations(path, 'c' if engine == 'vm' else 'java')
                if expected is not None:
                    selected.append((engine, stress, relative, path, expected))

    def one(item):
        engine, stress, relative, path, expected = item
        key = f'{engine}/{"gc-stress" if stress else "normal"}/{relative}'
        argv = [str(args.binary), '--engine=' + engine]
        if stress:
            argv.append('--gc-stress')
        argv.append(str(path))
        result = command(argv, args.source, args.output / 'commands' / key, 'run', timeout=60)
        process = subprocess.CompletedProcess(argv, result['exit_code'], result['stdout'], result['stderr'])
        problems = rules.validate(expected, process)
        return key, {'source_sha256': digest(path.read_bytes()),
                     'tests': [[key, 'failed' if problems else 'passed', '']],
                     'exit_code': result['exit_code'],
                     'stdout_sha256': result['stdout_sha256'],
                     'stderr_sha256': result['stderr_sha256'],
                     'problems': problems}

    with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as workers:
        answers = dict(workers.map(one, selected))
    assert len(answers) == 974, f'conformance coverage changed: {len(answers)} != 974'
    return answers


def eda(args):
    golden = args.source / 'golden'
    manifest = json.loads((golden / 'manifest.json').read_text())
    answers = {}
    for case in manifest['cases']:
        key = case['id']
        model = golden / 'cases' / key / 'model.sexp'
        project = golden / 'projects' / case['project']
        output = args.output / 'outputs' / key
        argv = [str(args.binary), '--model', str(model), '--project-dir', str(project),
                '--out-dir', str(output), *case['flags']]
        result = command(argv, args.source, args.output / 'commands' / key, 'run')
        files = {p.relative_to(output).as_posix(): digest(p.read_bytes())
                 for p in output.rglob('*') if p.is_file()}
        expected = {name: digest((golden / 'cases' / key / 'expected' / name).read_bytes())
                    for name in case['outputs']}
        problems = []
        if result['exit_code'] != 0:
            problems.append('process exit ' + str(result['exit_code']))
        if files != expected:
            problems.append('output file set or bytes differ from unchanged goldens')
        answers[key] = {'source_sha256': digest(model.read_bytes()),
                        'project_inputs': {p.relative_to(project).as_posix(): digest(p.read_bytes())
                                           for p in project.rglob('*') if p.is_file()},
                        'tests': [[key, 'failed' if problems else 'passed', '']],
                        'exit_code': result['exit_code'],
                        'stdout_sha256': result['stdout_sha256'],
                        'stderr_sha256': result['stderr_sha256'],
                        'outputs': files, 'problems': problems}
    assert len(answers) == 34, f'golden coverage changed: {len(answers)} != 34'
    return answers


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('corpus', choices=('lox', 'eda'))
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--binary', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--jobs', type=int, default=3)
    parser.add_argument('--against', type=Path)
    args = parser.parse_args()
    args.source, args.binary, args.output = (p.resolve() for p in (args.source, args.binary, args.output))
    if args.output.exists():
        parser.error('output must be fresh; frozen answers are never overwritten')
    args.output.mkdir(parents=True)
    started = time.monotonic()
    binary_hash = digest(args.binary.read_bytes())
    files = lox(args) if args.corpus == 'lox' else eda(args)
    mismatches = []
    if args.against:
        expected = json.loads(args.against.read_text())['files']
        mismatches = compare_answers(files, expected)
    summary = {'cases': len(files), 'failed': [key for key, value in files.items() if value['problems']],
               'mismatches': mismatches, 'elapsed_seconds': time.monotonic() - started,
               'binary_unchanged': digest(args.binary.read_bytes()) == binary_hash}
    document = {'version': 'frontend-external-oracle-v1', 'corpus': args.corpus,
                'binary_sha256': binary_hash, 'source_root': str(args.source),
                'files': files, 'summary': summary}
    (args.output / 'answers.json').write_text(json.dumps(document, indent=2) + '\n')
    print(json.dumps(summary, indent=2))
    return int(bool(summary['failed'] or mismatches or not summary['binary_unchanged']))


def compare_answers(actual, expected):
    """Compare membership as well as every recorded verdict and output byte hash."""
    return sorted(set(actual) ^ set(expected)) + sorted(
        key for key in actual.keys() & expected.keys() if actual[key] != expected[key])


if __name__ == '__main__':
    raise SystemExit(main())
