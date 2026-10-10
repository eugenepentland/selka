#!/usr/bin/env python3
"""Preserve the completed build gate summary and its admission measurements."""
import argparse
import hashlib
import json
from pathlib import Path
import re


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--admission', type=Path, required=True)
    parser.add_argument('--output-prefix', type=Path, default=Path(__file__).with_name('full-gate-summary'))
    args = parser.parse_args()
    directory = args.admission.resolve()
    evidence_path = directory / 'results.json'
    evidence = json.loads(evidence_path.read_text())
    assert evidence['wrapper_exit'] == 0 and evidence['completion']['exit'] == 0
    log_path = directory / 'command.stderr.log'
    raw = log_path.read_bytes()
    log = raw.decode()
    summaries = list(re.finditer(r'^Build Summary:.*$', log, re.MULTILINE))
    assert summaries, 'completed gate has no Build Summary'
    final = summaries[-1]
    text = log[final.start():].rstrip() + '\n'
    counts = re.search(r'(\d+)/(\d+) steps succeeded; (\d+)/(\d+) tests passed', final.group())
    assert counts, final.group()
    steps_passed, steps_total, tests_passed, tests_total = map(int, counts.groups())
    skipped_match = re.search(r'\((\d+) skipped\)', final.group())
    tests_skipped = int(skipped_match[1]) if skipped_match else 0
    assert steps_passed == steps_total and tests_passed + tests_skipped == tests_total
    guardian = [line for line in log.splitlines() if line.startswith('guardian: run-all:')]
    assert guardian and all('check(s) passed' in line for line in guardian)
    scope_lines = [line for line in log.splitlines() if line.startswith('guardian: diff-scoped vs ')]
    scoped = re.search(r'^guardian: diff-scoped vs (\S+): (\d+)/(\d+) source file\(s\) in scope for the '
                       r'(\d+) per-file check\(s\); (\d+) whole-tree check\(s\)', log, re.MULTILINE)
    scope_counts = None if scoped is None else {
        'base': scoped[1], 'source_files_in_scope': int(scoped[2]), 'source_files_total': int(scoped[3]),
        'per_file_checks': int(scoped[4]), 'whole_tree_checks': int(scoped[5]), 'whole_tree_verification': False}
    guardian_tests = [json.loads(match) for match in re.findall(r'^guardian/test: RESULT (\{.*\})$', log, re.MULTILINE)]
    assert all(not row['failed'] for row in guardian_tests)
    assert 'fmt-check' in evidence['command'] and re.search(r'^fmt-check(?:\s|$)', text, re.MULTILINE)
    fmt_lines = [line for line in text.splitlines() if re.search(r'fmt|formatting', line)]
    summary = {
        'evidence': str(evidence_path), 'evidence_sha256': hashlib.sha256(evidence_path.read_bytes()).hexdigest(),
        'log': str(log_path), 'log_sha256': hashlib.sha256(raw).hexdigest(),
        'command': evidence['command'], 'cwd': evidence['cwd'], 'started_utc': evidence['started_utc'],
        'exit': evidence['wrapper_exit'], 'build_summary': final.group(),
        'steps': {'passed': steps_passed, 'total': steps_total},
        'tests': {'executed': tests_passed, 'passed': tests_passed,
                  'reported_total': tests_total, 'skipped': tests_skipped,
                  'method': 'Executed counts are passing tests in the successful final Zig Build Summary. '
                            'Reported total includes skipped test instances, such as tests assigned to another shard.'},
        'guardian': {'checks_passed': True, 'run_all_lines': guardian,
                     'scope': 'Exact run-all lines retain whether checks were diff scoped or whole tree.',
                     'scope_lines': scope_lines, 'scope_counts': scope_counts,
                     'test_runs': guardian_tests,
                     'test_totals': {key: sum(row[key] for row in guardian_tests) for key in ['passed', 'failed', 'skipped']}},
        'fmt': {'passed': True, 'method': 'Explicit fmt-check target in the successful command and final build graph.',
                'summary_lines': fmt_lines},
        'admission': {**{key: evidence[key] for key in ['kind', 'queue_s', 'held_s', 'command_wall_s']},
                      'command_metrics': evidence['completion']['metrics'], 'method': evidence['method']},
        'full_build_summary_file': str(args.output_prefix.with_suffix('.txt')),
    }
    args.output_prefix.with_suffix('.txt').write_text(text)
    args.output_prefix.with_suffix('.json').write_text(json.dumps(summary, indent=2) + '\n')
    print(json.dumps({'summary': final.group(), 'output_prefix': str(args.output_prefix),
                      'queue_s': evidence['queue_s'], 'held_s': evidence['held_s']}))


if __name__ == '__main__':
    main()
