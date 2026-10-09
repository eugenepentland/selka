#!/usr/bin/env python3
"""Replay the 2026-09-20 friction session and pin the harvest contract.

The fixture `velocity/friction/session-2026-09-20.jsonl` is a hand-built
`friction-log-v1` log: same field names and types the compiler writes, under
`src/friction_log.zig`'s pinned record shape, with synthetic compiler identity
and the real SHA-256 of each documented probe snapshot. This driver asserts the
four repair rounds the M1 acceptance names, the two codes that must earn none,
and the `--window`, `--top`, `--json` and unclassified behaviour of
`velocity/friction/harvest.py`.

Run it directly or through unittest:

    python3 tests/test_friction_harvest.py
    python3 -m unittest discover -s tests -p 'test_friction_harvest.py'
"""

import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
HARVEST = ROOT / 'velocity/friction/harvest.py'
FIXTURE = ROOT / 'velocity/friction/session-2026-09-20.jsonl'
RECORD_FIELDS = {'version', 'invocation', 'compiler', 'snapshot', 'diagnostics', 'status', 'wall_ns'}
COMPILER_FIELDS = {'compiler_sha256', 'zig_version', 'architecture', 'os', 'abi', 'optimize'}
FINDING_FIELDS = {'code', 'severity', 'start', 'end'}
FOUR_ROUNDS = {'E_ARITY': 1, 'E_SYNTAX': 1, 'E_MODULE_HEADER': 1, 'E_TYPE': 1}
FREE_CODES = ('E_LAMBDA_CAPTURE', 'W_UNUSED_BINDING')


def harvest(*arguments):
    """Run the harvest script and return its stdout, requiring a clean exit."""
    result = subprocess.run([sys.executable, str(HARVEST), *arguments],
                            capture_output=True, text=True, timeout=60)
    assert result.returncode == 0, result.stderr
    return result.stdout


def harvested(*arguments):
    """Run the harvest script with --json and return the parsed document."""
    return json.loads(harvest('--json', *arguments))


def record(path, status, codes=(), command='check', snapshot='0' * 64):
    """Build one record in the shape `src/friction_log.zig` pins."""
    return {
        'version': 'friction-log-v1',
        'invocation': {'command': command, 'path': path},
        'compiler': {'compiler_sha256': '1' * 64, 'zig_version': 'test', 'architecture': 'x86_64',
                     'os': 'linux', 'abi': 'gnu', 'optimize': 'Debug'},
        'snapshot': snapshot,
        'diagnostics': [{'code': code, 'severity': 'error', 'start': 1, 'end': 2} for code in codes],
        'status': status,
        'wall_ns': 1000,
    }


def write_log(directory, records):
    """Write records as one JSON line each and return the path."""
    path = Path(directory) / 'friction.jsonl'
    path.write_text(''.join(json.dumps(item, separators=(',', ':')) + '\n' for item in records))
    return path


class FixtureShapeTests(unittest.TestCase):
    def test_fixture_carries_exactly_the_pinned_record_shape(self):
        records = [json.loads(line) for line in FIXTURE.read_text().splitlines()]
        self.assertEqual(10, len(records))
        for item in records:
            self.assertEqual(RECORD_FIELDS, set(item))
            self.assertEqual('friction-log-v1', item['version'])
            self.assertEqual({'command', 'path'}, set(item['invocation']))
            self.assertEqual(COMPILER_FIELDS, set(item['compiler']))
            self.assertEqual(64, len(item['snapshot']))
            self.assertIsInstance(item['status'], int)
            self.assertIsInstance(item['wall_ns'], int)
            for finding in item['diagnostics']:
                self.assertEqual(FINDING_FIELDS, set(finding))
                self.assertIn(finding['severity'], ('error', 'warning'))
        self.assertEqual('probe4.selka', records[0]['invocation']['path'])


class SessionReplayTests(unittest.TestCase):
    def test_replay_yields_the_four_named_repair_rounds(self):
        document = harvested(str(FIXTURE))
        self.assertEqual('friction-harvest-v1', document['version'])
        self.assertEqual(10, document['records'])
        self.assertEqual(3, document['files'])
        self.assertEqual(4, document['rounds'])
        self.assertEqual(FOUR_ROUNDS, {row['code']: row['rounds'] for row in document['by_code']
                                       if row['rounds'] > 0})

    def test_the_two_free_diagnostics_attribute_zero_rounds(self):
        rows = {row['code']: row for row in harvested(str(FIXTURE))['by_code']}
        self.assertEqual(0, rows['E_LAMBDA_CAPTURE']['rounds'])
        self.assertEqual(0, rows['W_UNUSED_BINDING']['rounds'])
        self.assertEqual(1, rows['E_LAMBDA_CAPTURE']['records'])
        self.assertEqual(3, rows['W_UNUSED_BINDING']['records'])

    def test_union_comma_syntax_stays_unclassified_instead_of_guessing(self):
        rows = {row['code']: row for row in harvested(str(FIXTURE))['by_code']}
        self.assertEqual(('unclassified', 'unclassified'),
                         (rows['E_SYNTAX']['idiom'], rows['E_SYNTAX']['idiom_source']))
        self.assertEqual(('call-arity', 'code-only'), (rows['E_ARITY']['idiom'], rows['E_ARITY']['idiom_source']))
        self.assertEqual(('module-header', 'code-only'),
                         (rows['E_MODULE_HEADER']['idiom'], rows['E_MODULE_HEADER']['idiom_source']))
        self.assertEqual(('type-mismatch', 'code-only'), (rows['E_TYPE']['idiom'], rows['E_TYPE']['idiom_source']))

    def test_idiom_table_totals_the_code_table(self):
        document = harvested(str(FIXTURE))
        self.assertEqual(4, sum(row['rounds'] for row in document['by_idiom']))
        self.assertEqual({'call-arity': 1, 'module-header': 1, 'type-mismatch': 1, 'unclassified': 1},
                         {row['idiom']: row['rounds'] for row in document['by_idiom'] if row['rounds'] > 0})

    def test_classifier_rows_that_need_no_source_text_still_name_codes(self):
        harness = ('import json,sys;'
                   'sys.path.insert(0, %r);'
                   'import harvest;'
                   'print(json.dumps(harvest.source_free_idioms(%r)))'
                   % (str(HARVEST.parent), str(HARVEST.parent / 'classifier.json')))
        named = json.loads(subprocess.run([sys.executable, '-B', '-c', harness], capture_output=True,
                                          text=True, timeout=60, check=True).stdout)
        self.assertEqual('module-header', named['E_MODULE_NAME'])
        self.assertNotIn('E_SYNTAX', named)


class WindowAndOptionTests(unittest.TestCase):
    def test_window_parameter_decides_whether_a_late_pass_counts(self):
        with tempfile.TemporaryDirectory(prefix='friction-window-') as directory:
            log = write_log(directory, [record('a.selka', 1, ['E_TYPE']),
                                        record('a.selka', 1, ['E_UNBOUND']),
                                        record('a.selka', 1, ['E_ARITY']),
                                        record('a.selka', 0)])
            near = {row['code']: row['rounds'] for row in harvested(str(log), '--window', '1')['by_code']}
            far = {row['code']: row['rounds'] for row in harvested(str(log), '--window', '3')['by_code']}
            # Only the failing record one command before the passing check is
            # credited at window 1; widening the window credits all three.
            self.assertEqual(0, near['E_TYPE'])
            self.assertEqual(0, near['E_UNBOUND'])
            self.assertEqual(1, near['E_ARITY'])
            self.assertEqual(1, far['E_TYPE'])
            self.assertEqual(1, far['E_UNBOUND'])
            self.assertEqual(1, far['E_ARITY'])

    def test_only_the_next_pass_is_needed_per_failing_record(self):
        with tempfile.TemporaryDirectory(prefix='friction-repeat-') as directory:
            log = write_log(directory, [record('a.selka', 1, ['E_TYPE']),
                                        record('a.selka', 0),
                                        record('a.selka', 0)])
            self.assertEqual(1, {row['code']: row['rounds']
                                 for row in harvested(str(log))['by_code']}['E_TYPE'])

    def test_warning_severity_never_seeds_a_round(self):
        with tempfile.TemporaryDirectory(prefix='friction-warning-') as directory:
            item = record('a.selka', 1)
            item['diagnostics'] = [{'code': 'W_UNUSED_BINDING', 'severity': 'warning', 'start': 1, 'end': 2}]
            log = write_log(directory, [item, record('a.selka', 0)])
            self.assertEqual(0, {row['code']: row['rounds']
                                 for row in harvested(str(log))['by_code']}['W_UNUSED_BINDING'])

    def test_top_limits_each_table_and_json_is_one_document(self):
        document = harvested(str(FIXTURE), '--top', '1')
        self.assertEqual(1, len(document['by_code']))
        self.assertEqual(1, len(document['by_idiom']))
        self.assertEqual(4, document['rounds'])

    def test_truncated_line_is_skipped_rather_than_fatal(self):
        with tempfile.TemporaryDirectory(prefix='friction-truncated-') as directory:
            log = write_log(directory, [record('a.selka', 1, ['E_TYPE']), record('a.selka', 0)])
            log.write_text(log.read_text() + '{"version":"friction-log-v1","invo')
            document = harvested(str(log))
            self.assertEqual(1, document['skipped'])
            self.assertEqual(1, document['rounds'])


if __name__ == '__main__':
    unittest.main(verbosity=2)
