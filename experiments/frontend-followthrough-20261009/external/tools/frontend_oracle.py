#!/usr/bin/env python3
"""Freeze S5 corpus answers once, or compare a migrated corpus to those answers.

Tests retain S5's ``files -> tests [name,status,trap]`` representation. Source
hashes and raw IR are additional evidence, not guesses about uncovered programs.
Every subprocess has its own timing receipt. Run this driver through build-slot
and take bench-compile.lock when test suites are selected.
"""
from __future__ import annotations

import argparse
import concurrent.futures
import gzip
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import time


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def command(argv: list[str], cwd: Path, area: Path, name: str, timeout: int = 600) -> dict:
    start = time.monotonic()
    try:
        done = subprocess.run(argv, cwd=cwd, capture_output=True, timeout=timeout)
        status, stdout, stderr = done.returncode, done.stdout, done.stderr
    except subprocess.TimeoutExpired as error:
        status, stdout, stderr = 124, error.stdout or b'', error.stderr or b''
    record = {'argv': argv, 'cwd': str(cwd), 'exit_code': status,
              'elapsed_seconds': time.monotonic() - start, 'timeout_seconds': timeout,
              'affinity': sorted(os.sched_getaffinity(0)),
              'stdout_sha256': digest(stdout), 'stderr_sha256': digest(stderr)}
    area.mkdir(parents=True, exist_ok=True)
    (area / (name + '.stdout.gz')).write_bytes(gzip.compress(stdout, mtime=0))
    (area / (name + '.stderr.gz')).write_bytes(gzip.compress(stderr, mtime=0))
    (area / (name + '.json')).write_text(json.dumps(record, indent=2) + '\n')
    return {**record, 'stdout': stdout, 'stderr': stderr}


def test_table(result: dict) -> dict:
    for stream in ('stdout', 'stderr'):
        for line in result[stream].decode(errors='replace').splitlines():
            if not line.startswith('{"version"'):
                continue
            try:
                report = json.loads(line)
            except ValueError:
                continue
            tests = []
            for item in report['tests']:
                trap = re.match(r'(R_[A-Z_]+)', item.get('reason', ''))
                tests.append([item['name'], item['status'], trap.group(1) if trap else ''])
            if result['exit_code'] and all(item[1] == 'passed' for item in tests):
                return {'problem': 'failed command with passing test report',
                        'exit_code': result['exit_code'], 'tests': sorted(tests)}
            return {'tests': sorted(tests)}
    return {'problem': 'no test report', 'exit_code': result['exit_code'],
            'diagnostic_codes': re.findall(rb'error\[(E_[A-Z_0-9]+)\]', result['stderr'])}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--corpus', required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--evidence', type=Path, required=True)
    parser.add_argument('--existing', type=Path)
    parser.add_argument('--paths', type=Path, help='JSON list of paths or {path:...} entries')
    parser.add_argument('--jobs', type=int, default=2)
    parser.add_argument('--tests', action='store_true')
    parser.add_argument('--ir', action='store_true')
    parser.add_argument('--against', type=Path)
    parser.add_argument('--reuse-ir', type=Path, help='Reuse successful frozen IR answers; retry only refusals')
    parser.add_argument('--library-main', action='store_true', help='Append a recorded private main for an E_MAIN library IR dump')
    args = parser.parse_args()
    if not args.tests and not args.ir:
        parser.error('select --tests and/or --ir')
    if args.output.exists():
        parser.error('--output exists; frozen answers are never overwritten')
    compiler, root = args.compiler.resolve(), args.root.resolve()
    binary_hash = digest(compiler.read_bytes())
    existing = json.loads(args.existing.read_text())['files'] if args.existing else {}
    if args.paths:
        entries = json.loads(args.paths.read_text())
        paths = [root / (entry if isinstance(entry, str) else entry['path']) for entry in entries]
    else:
        paths = sorted(root.rglob('*.my'))
    target = json.loads(args.against.read_text())['files'] if args.against else None
    prior_ir = json.loads(args.reuse_ir.read_text())['files'] if args.reuse_ir else {}

    def one(path: Path) -> tuple[str, dict]:
        relative = path.relative_to(root).as_posix()
        key = args.corpus + '/' + relative
        area = args.evidence / relative
        data = path.read_bytes()
        entry = {'source_sha256': digest(data)}
        if args.tests:
            short = relative.removeprefix('tests/lang/').removesuffix('.my')
            if target is None and existing.get(short, {}).get('source_sha256') == entry['source_sha256']:
                entry.update(existing[short])
                entry['answer_source'] = 'S5-0 conformance-v1'
            else:
                done = command([str(compiler), 'test', str(path), '--json', '--cache-dir',
                                str(args.evidence.resolve() / 'guest-cache')], root, area, 'tests')
                answer = test_table(done)
                if 'diagnostic_codes' in answer:
                    answer['diagnostic_codes'] = [x.decode() for x in answer['diagnostic_codes']]
                entry.update(answer)
                entry['answer_source'] = 'S5 pin' if target is None else 'candidate'
        if args.ir:
            prior_entry = prior_ir.get(key, {})
            previous = prior_entry.get('ir', {}) if prior_entry.get('source_sha256') == entry['source_sha256'] else {}
            if previous.get('exit_code') == 0:
                entry['ir'] = previous
                entry['ir_answer_source'] = str(args.reuse_ir)
            else:
                done = command([str(compiler), 'dump-ir', str(path)], root, area, 'ir')
                if args.library_main and b'error[E_MAIN]' in done['stderr'] and not re.search(rb'^\s*(?:public |private )?def main\(', data, re.MULTILINE):
                    scratch = args.evidence.resolve() / 'library-inputs' / relative
                    scratch.parent.mkdir(parents=True, exist_ok=True)
                    stub = b'\n\ndef main() -> int:\n    return 0\n'
                    scratch.write_bytes(data + stub)
                    entry['ir_stub'] = stub.decode()
                    entry['ir_input_sha256'] = digest(data + stub)
                    done = command([str(compiler), 'dump-ir', str(scratch)], root, area, 'ir-library')
                entry['ir'] = {k: done[k] for k in ('exit_code', 'stdout_sha256')}
                if done['exit_code']:
                    entry['ir']['diagnostic_codes'] = [x.decode() for x in re.findall(rb'error\[(E_[A-Z_0-9]+)\]', done['stderr'])]
        if target is not None:
            expected = target.get(key)
            if expected is None:
                entry['mismatches'] = ['missing frozen answer']
            else:
                entry['mismatches'] = [field for field in ('tests', 'problem', 'ir')
                                       if entry.get(field) != expected.get(field)]
        return key, entry

    start = time.monotonic()
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as pool:
        files = dict(pool.map(one, paths))
    stable = digest(compiler.read_bytes()) == binary_hash
    summary = {'files': len(files), 'tests': sum(len(x.get('tests', [])) for x in files.values()),
               'problems': [k for k, v in files.items() if 'problem' in v],
               'ir_refusals': [k for k, v in files.items() if v.get('ir', {}).get('exit_code')],
               'mismatches': [k for k, v in files.items() if v.get('mismatches')],
               'elapsed_seconds': time.monotonic() - start, 'binary_unchanged': stable}
    document = {'version': 's5-conformance-references-v1',
                'oracle': {'path': str(compiler), 'sha256': binary_hash},
                'corpus': args.corpus, 'files': files, 'summary': summary}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(document, indent=2, sort_keys=True) + '\n')
    print(json.dumps(summary, indent=2))
    return int(not stable or bool(summary['mismatches']))


if __name__ == '__main__':
    raise SystemExit(main())
