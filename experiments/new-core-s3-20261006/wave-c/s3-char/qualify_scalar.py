#!/usr/bin/env python3
"""Compare complete located scalar-fusion outcomes with explicit qualified oracles.

Run through a build slot (Core gates separately hold gate/build slots). Evidence
must be fresh. Every compiler
and native status/stdout/stderr is retained, including failures. No marker, index,
length, source location or guest frame is normalized for comparison.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time

ROOT = Path(__file__).resolve().parents[4]
ORDER_SOURCE = '''module scalar_order

def select(text: str, out: Stream) -> str:
    out.print("before")
    ch = text[0]
    out.print("after")
    selected = ""
    if ch == "é":
        selected += ch
    elif ch != "x":
        selected += ch
    return selected

def main(args: list[str], out: Stream) -> int:
    text = "\\0" if args[0] == "nul" else args[0]
    out.print(select(text, out))
    return 0
'''


def inside(path):
    result = Path(path).resolve()
    if not result.is_relative_to(ROOT):
        raise ValueError(f'writable path must stay inside {ROOT}: {result}')
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--old', type=Path, required=True)
    parser.add_argument('--new', type=Path, required=True)
    parser.add_argument('--evidence', type=Path, required=True)
    parser.add_argument('--cache-root', type=Path, required=True)
    args = parser.parse_args()
    evidence, cache = inside(args.evidence), inside(args.cache_root)
    if evidence.exists() or cache.exists():
        raise SystemExit('use fresh evidence/cache directories; no outcomes are overwritten')
    evidence.mkdir(parents=True)
    cache.mkdir(parents=True)
    journal = evidence / 'commands.jsonl'
    summary = {'qualified': False, 'error': None, 'reports': {}, 'order_runs': [],
               'source_head': subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip(),
               'oracles': {role: {'path': str(path.resolve()), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}
                           for role, path in (('old', args.old), ('new', args.new))}}
    sequence = 0

    def run(command, leak=False):
        nonlocal sequence
        start = time.monotonic()
        done = subprocess.run(list(map(str, command)), capture_output=True,
                              env={**os.environ, 'MYL_CORE_LEAKCHECK': '1' if leak else '0'})
        sequence += 1
        record = {'sequence': sequence, 'command': list(map(str, command)), 'status': done.returncode,
                  'seconds': time.monotonic() - start, 'stdout': done.stdout.decode(),
                  'stderr': done.stderr.decode(), 'leakcheck': leak}
        with journal.open('a') as output:
            output.write(json.dumps(record, ensure_ascii=True) + '\n')
        return record

    def report(role, compiler, mode):
        command = [compiler, 'test', ROOT / 'test/core/t_scalar_fusion.my', '--json', '--cache-dir', cache / role]
        command.extend(mode)
        record = run(command, role != 'old')
        (evidence / f'{role}-report.json').write_text(record['stdout'])
        if record['status'] != 1 or record['stderr']:
            raise ValueError(f'{role}: compiler status/stderr differs from the intended native-trap report: {record}')
        parsed = json.loads(record['stdout'])
        if parsed.get('version') != 'native-tests-v1' or (parsed['passed'], parsed['failed'], parsed.get('unsupported', 0)) != (8, 9, 0):
            raise ValueError(f'{role}: unexpected native verdict counts: {parsed}')
        names = [test['name'] for test in parsed['tests']]
        if len(names) != 17 or len(set(names)) != 17:
            raise ValueError(f'{role}: tests missing or duplicated')
        if role == 'old' and any(test['expected'] is not True or
                                 test['actual'] is not (True if test['status'] == 'passed' else None)
                                 for test in parsed['tests']):
            raise ValueError('old: fixture does not have the intended true predicates and native traps')
        # The established Core zero-argument report omits old-only actual/expected
        # fields. A passing bool verdict implies true; these failing cases trap.
        # Compare every shared observable field and the complete located reasons.
        summary['reports'][role] = {test['name']: {key: test.get(key, '') for key in
                                   ('name', 'status', 'reason', 'output')}
                                   for test in parsed['tests']}

    try:
        report('old', args.old, [])
        for role, mode in (('debug', []), ('release', ['--release']), ('verify', ['--release', '--verify-facts'])):
            report(role, args.new, mode)
            if summary['reports'][role] != summary['reports']['old']:
                different = [name for name, value in summary['reports']['old'].items()
                             if summary['reports'][role].get(name) != value]
                raise ValueError(f'{role}: complete observable native verdicts differ: {different}')
        source = evidence / 'scalar_order.my'
        source.write_text(ORDER_SOURCE)
        expected = {}
        for role, compiler, mode in (('old', args.old, ['--release']), ('debug', args.new, []),
                                    ('release', args.new, ['--release']), ('verify', args.new, ['--release', '--verify-facts'])):
            executable = cache / f'order-{role}'
            built = run([compiler, 'build', source, '-o', executable, '--cache-dir', cache / role, *mode])
            if built['status'] or built['stderr'] or built['stdout'] or not executable.is_file():
                raise ValueError(f'{role}: output-order build failed: {built}')
            for text in ('', 'é', 'a', 'x', 'nul', '🙂'):
                record = run([executable, text], role != 'old')
                summary['order_runs'].append(record)
                observed = (record['status'], record['stdout'], record['stderr'])
                if role == 'old':
                    expected[text] = observed
                    value = '\x00' if text == 'nul' else '' if text == 'x' else text
                    expected_stdout = 'before\n' if not text else f'before\nafter\n{value}\n'
                    if observed[0] != int(not text) or observed[1] != expected_stdout:
                        raise ValueError(f'old: output-order assumption failed: {record}')
                elif observed != expected[text]:
                    raise ValueError(f'{role}: native status/stdout/complete located trap differs: {record}')
        summary['qualified'] = True
        print('17 complete shared native verdicts agree in debug/release/verify; 24 exact native output-order runs agree')
        return 0
    except (ValueError, OSError) as error:
        summary['error'] = str(error)
        print(f'scalar qualification FAILED: {error}', flush=True)
        return 1
    finally:
        summary['commands'] = sequence
        (evidence / 'summary.json').write_text(json.dumps(summary, indent=2, ensure_ascii=True) + '\n')


if __name__ == '__main__':
    raise SystemExit(main())
