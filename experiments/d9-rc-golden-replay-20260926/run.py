#!/usr/bin/env python3
"""Replay the authoritative native goldens on actual RC QBE and LLVM guests.

Uses the source/fixture selection in test/golden_parity.zig, preserving all
expected results. Explicit legacy-sharing cases inherit the documented GC
fallback. This does not replace any required gate command.
"""
import argparse
import base64
import concurrent.futures
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
SHA = lambda p: hashlib.sha256(Path(p).read_bytes()).hexdigest()


def cases():
    harness = (ROOT / 'test/golden_parity.zig').read_text()
    fixtures = dict(re.findall(r'\.name = "([^"]+)", \.relative_path = "([^"]+)"', harness))
    assert len(fixtures) >= 10
    selected, skipped, inputs = [], {'docs': 0, 'unmatched': 0, 'data': 0}, {}
    for path in sorted((ROOT / 'tests/goldens').glob('qbe_*.json')):
        inputs[str(path.relative_to(ROOT))] = SHA(path)
        document = json.loads(path.read_text())
        assert document['version'] == 'golden-outcomes-v1'
        for key, entry in document['entries'].items():
            case = entry.get('case', []) if isinstance(entry, dict) else []
            label = case[0] if case and isinstance(case[0], str) else None
            if label is None:
                skipped['data'] += 1
                continue
            if '\n' in label:
                source = label
            elif label in fixtures:
                relative = fixtures[label]
                source = (ROOT / relative).read_text()
                inputs[relative] = SHA(ROOT / relative)
            else:
                kind = 'data' if 'returncode' not in entry else 'docs' if path.stem == 'qbe_docs' or label.startswith('docs/') else 'unmatched'
                skipped[kind] += 1
                continue
            options = [v for part in case[1:] if isinstance(part, list) for v in part if isinstance(v, str)]
            selected.append({'id': path.stem + '/' + key, 'source': source, 'options': options, 'expected': entry})
    assert len(selected) == 231 and skipped == {'docs': 27, 'unmatched': 345, 'data': 1}, (len(selected), skipped)
    inputs['test/golden_parity.zig'] = SHA(ROOT / 'test/golden_parity.zig')
    return selected, skipped, inputs


def signature(status, stdout, stderr):
    # Admission diagnostics belong to the wrapper, not the compiler outcome.
    # Keep every other line, including the compiler's leading refusal prefix.
    stderr = b'\n'.join(line for line in stderr.splitlines() if not line.startswith(b'build-slot: '))
    code = re.search(rb'R_[A-Z_]+', stderr)
    failed = any(token in stderr for token in (b'error[', b'host failure:', b'QBE runtime failure')) or stderr.startswith((b'mylang:', b'usage:'))
    return {'status': status, 'stdout_b64': base64.b64encode(stdout).decode(), 'code': code.group().decode() if code else '', 'failed': failed}


def execute(compiler, work, backend, case):
    key = case['id'] + '|' + backend
    folder = work / 'cases' / backend / case['id']
    source_dir, cwd = folder / 'source', folder / 'work'
    source_dir.mkdir(parents=True, exist_ok=True)
    cwd.mkdir(exist_ok=True)
    source = source_dir / 'case.my'
    source.write_text(case['source'])
    (cwd / 'greeting.txt').write_text('hello from a granted directory\n')
    (cwd / 'lines.txt').write_text('one\ntwo\nthree\n')
    command = [str(ROOT / 'scripts/build-slot.sh'), 'build', str(compiler), 'run', str(source), '--print-result', '--cache-dir=' + str(work / ('cache-' + backend)), *case['options']]
    # run's --release selects actual LLVM at O3/full LTO; unlike build,
    # run does not accept --backend/--llvm-opt/--lto options.
    if backend == 'llvm':
        command += ['--release']
    environment = dict(os.environ, MYLANG_RUNTIME='rc-v2-counting', TMPDIR=str(work / 'tmp'), ZIG_LOCAL_CACHE_DIR=str(ROOT / '.zig-cache-golden-guests'))
    result = subprocess.run(command, cwd=cwd, env=environment, capture_output=True, timeout=600)
    expected = case['expected']
    reference = signature(expected['returncode'], base64.b64decode(expected['stdout']), base64.b64decode(expected['stderr']))
    actual = signature(result.returncode, result.stdout, result.stderr)
    comparable = 'code' if reference['failed'] or actual['failed'] else 'stdout_b64'
    matched = reference['status'] == actual['status'] and reference['failed'] == actual['failed'] and reference[comparable] == actual[comparable]
    counters = [json.loads(line.split(b' ', 1)[1]) for line in result.stderr.splitlines() if line.startswith(b'MYLANG_RC_COUNTS ')]
    legacy = '--legacy-sharing' in case['options']
    balanced = all(not row['saturated'] and row['heap_allocate'] == row['retire'] and row['heap_allocate'] + row['owner_acquire'] == row['owner_release'] and row['hold_acquire'] == row['hold_release'] for row in counters)
    observed = 'gc-legacy' if legacy else 'rc-v2-counting' if counters else 'no-RC-counter-record'
    # CLI refusals happen before a guest is started. Every other ordinary case,
    # including a successful main returning a nonzero integer, needs counters.
    missing_counters = not legacy and not counters and (not actual['failed'] or bool(actual['code']))
    return key, {'command': command, 'source_sha256': SHA(source), 'expected': reference, 'actual': actual, 'matched': matched, 'runtime_observed': observed, 'balanced': balanced, 'missing_required_counters': missing_counters, 'counters': counters, 'stderr': result.stderr.decode(errors='replace')}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', required=True)
    parser.add_argument('--compiler-commit', required=True)
    parser.add_argument('--work', required=True)
    parser.add_argument('--jobs', type=int, default=3)
    args = parser.parse_args()
    compiler, work = Path(args.compiler).resolve(), Path(args.work).resolve()
    work.mkdir(parents=True, exist_ok=True)
    (work / 'tmp').mkdir(exist_ok=True)
    selected, skipped, inputs = cases()
    result = {'driver_sha256': SHA(__file__), 'compiler': str(compiler), 'compiler_sha256': SHA(compiler), 'compiler_commit': args.compiler_commit, 'source_commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(), 'inputs': inputs, 'skipped_per_backend': skipped, 'cases_per_backend': len(selected), 'runs': {}}
    output = work / 'results.json'
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as pool:
        pending = [pool.submit(execute, compiler, work, backend, case) for backend in ('qbe', 'llvm') for case in selected]
        for future in concurrent.futures.as_completed(pending):
            key, row = future.result()
            result['runs'][key] = row
            output.write_text(json.dumps(result, indent=2) + '\n')
            print(key, 'PASS' if row['matched'] else 'FAIL', row['runtime_observed'], 'balanced=' + str(row['balanced']), flush=True)
    assert SHA(compiler) == result['compiler_sha256'] and cases()[2] == inputs
    result['mismatches'] = [key for key, row in result['runs'].items() if not row['matched']]
    result['imbalanced'] = [key for key, row in result['runs'].items() if not row['balanced']]
    result['no_counter_record'] = [key for key, row in result['runs'].items() if row['runtime_observed'] == 'no-RC-counter-record']
    result['missing_required_counters'] = [key for key, row in result['runs'].items() if row['missing_required_counters']]
    output.write_text(json.dumps(result, indent=2) + '\n')
    assert len(result['runs']) == 462 and not result['mismatches'] and not result['imbalanced'] and not result['missing_required_counters'], result['mismatches'] + result['imbalanced'] + result['missing_required_counters']


if __name__ == '__main__':
    main()
