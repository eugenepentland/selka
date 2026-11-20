"""Behavior checks for latency accounting over local DSH session logs."""
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


SPEC = importlib.util.spec_from_file_location('audit', Path(__file__).parents[1] / 'scripts/audit_deepseek_tools.py')
audit = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(audit)


def header(session='root', **fields):
    return {'type': 'session', 'id': session, 'version': 0, 'createdAt': 0,
            'cwd': '/project', 'delegationDepth': 0, **fields}


def call(seq, start, command='true', name='bash', call_id='c', **args):
    return {'type': 'tool/call', 'seq': seq, 'time': start,
            'data': {'callId': call_id, 'name': name, 'arguments': json.dumps({'command': command, **args})}}


def result(seq, end, call_id='c', text='', is_error=False):
    return {'type': 'tool/result', 'seq': seq, 'time': end, 'data': {'message': {
        'source': {'kind': 'tool', 'callId': call_id}, 'content': [
            {'type': 'tool-result', 'toolCallId': call_id, 'isError': is_error,
             'content': [{'type': 'text', 'text': text}]}]}}}


def inbox(seq, when, job_id, status='completed', exit_code=0, command='zig build test'):
    text = (f'background job {job_id} (bash: {command}) finished '
            f'[status: {status}, exit code: {exit_code}]. Read its output with job_output.')
    return {'type': 'agent/inbox/spliced', 'seq': seq, 'time': when,
            'data': {'target': 'next-step', 'start': 0, 'inserted': [
                {'content': [{'type': 'text', 'text': text}],
                 'source': {'kind': 'plugin', 'plugin': 'tool-jobs', 'form': 'notice'}}]}}


def delivered(seq, when, job_id, status='completed', exit_code=0, command='zig build test'):
    text = (f'background job {job_id} (bash: {command}) finished '
            f'[status: {status}, exit code: {exit_code}]. Read its output with job_output.')
    return {'type': 'user/message', 'seq': seq, 'time': when,
            'data': {'content': [{'type': 'text', 'text': text}],
                     'source': {'kind': 'plugin', 'plugin': 'tool-jobs', 'form': 'notice'}}}


class AuditTests(unittest.TestCase):
    def test_versioned_logs_are_discovered_without_lock_or_backup_files(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            valid = ['session.jsonl', 'session.jsonl.zstd', 'session.v3.jsonl.zstd']
            for name in valid + ['session.lock', 'session.v3.jsonl.zstd.bak']:
                (root / name).touch()
            self.assertEqual({p.name for p in audit.session_files(root)}, set(valid))

    def test_managed_timeout_is_distinct_from_persistent_shell_reset(self):
        session = audit.parse_events([header(version=3), call(1, 0),
                                      result(2, 60000, text='[timed out after 60000ms]\n[killed by signal: SIGTERM]')], 'root')
        report = audit.make_report([session], Path('/project'))
        self.assertEqual(report['flags']['managed_timeout']['calls'], 1)
        self.assertEqual(report['flags']['persistent_timeout']['calls'], 0)

    def test_multiline_job_command_preserves_completion_notice(self):
        events = [header(version=3), call(1, 0, run_in_background=True),
                  result(2, 100, text='started background job bash-7'),
                  inbox(3, 5000, 'bash-7', command='cat > /tmp/probe.sh <<\'EOF\'\ntrue\nEOF\nsh /tmp/probe.sh')]
        report = audit.make_report([audit.parse_events(events, 'root')], Path('/project'))
        self.assertEqual(report['background_jobs'][0]['execution_seconds'], 5)
        self.assertEqual(report['background_jobs'][0]['completion_source'], 'settlement-notice')

    def test_overlaps_do_not_count_twice(self):
        self.assertEqual(audit.seconds([(0, 2000), (500, 1000), (1500, 3000), (4000, 5000)]), 4)
        with self.assertRaises(ValueError):
            audit.seconds([(5, 3)])

    def test_ids_pair_out_of_order_and_remain_session_local(self):
        first = audit.parse_events([header(), call(1, 0, call_id='a'), call(2, 1000, call_id='b'),
                                    result(3, 2000, 'b'), result(4, 3000, 'a')], 'first')
        child = audit.parse_events([header('child', parentSession='root', delegationDepth=1, cwd='/worktree'),
                                    call(1, 0, call_id='a'), result(2, 1000, 'a')], 'child')
        report = audit.make_report([first, child], Path('/project'))
        self.assertEqual(report['completed_calls'], 3)
        self.assertEqual(report['included']['call_seconds'], 5)
        self.assertEqual(report['tool_blocked_agent_seconds'], 4)
        self.assertEqual(report['elapsed_union_tool_seconds'], 3)

    def test_seed_replay_does_not_inflate_work(self):
        session = audit.parse_events([header(), call(1, 0), result(2, 1000),
                                      {'type': 'session/end-seed', 'seq': 3, 'time': 1500, 'data': {}},
                                      call(4, 2000), result(5, 3000)], 'seeded')
        self.assertEqual(len(session['calls']), 1)
        self.assertEqual(session['calls'][0]['seq'], 4)
        self.assertEqual(session['inherited_calls_skipped'], 1)

    def test_selka_directory_name_does_not_turn_search_into_compiler_work(self):
        session = audit.parse_events([header(), call(1, 0, 'cd /project/selka && grep -R needle src'),
                                      result(2, 1000)], 'root')
        report = audit.make_report([session], Path('/project'))
        self.assertIn('recursive_grep', report['categories'])

    def test_coordinator_sleeps_are_excluded_worker_polls_are_visible(self):
        root = audit.parse_events([header(), call(1, 0, 'sleep 60; git status'), result(2, 60000)], 'root')
        child = audit.parse_events([header('child', parentSession='root', delegationDepth=1),
                                    call(1, 0, 'sleep 20; tail /tmp/build.log'), result(2, 20000)], 'child')
        report = audit.make_report([root, child], Path('/project'))
        self.assertEqual(report['excluded']['call_seconds'], 60)
        self.assertEqual(report['included']['call_seconds'], 20)
        report = audit.make_report([root, child], Path('/project'), exclusions=['child:1'])
        self.assertEqual(report['included']['calls'], 0)

    def test_parent_worker_sleep_is_also_excluded(self):
        parent = audit.parse_events([header('worker', delegationDepth=1), call(1, 0, 'sleep 30'), result(2, 30000)], 'worker')
        grandchild = audit.parse_events([header('grandchild', parentSession='worker', delegationDepth=2)], 'grandchild')
        report = audit.make_report([parent, grandchild], Path('/project'))
        self.assertEqual(report['excluded']['call_seconds'], 30)

    def test_model_phase_excludes_time_between_user_turns(self):
        events = [header(), {'type': 'step/start', 'time': 1000, 'data': {'turn': 1, 'step': 1}},
                  {'type': 'assistant/message', 'time': 3000, 'data': {'turn': 1, 'step': 1}},
                  {'type': 'step/start', 'time': 100000, 'data': {'turn': 2, 'step': 1}},
                  {'type': 'assistant/message', 'time': 101000, 'data': {'turn': 2, 'step': 1}}]
        report = audit.make_report([audit.parse_events(events, 'root')], Path('/project'))
        self.assertEqual(report['pre_tool_phase_agent_seconds'], 3)

    def test_timeout_recognized_even_when_tool_is_error_false(self):
        session = audit.parse_events([header(), call(1, 0, 'zig build test'),
                                      result(2, 303000, text='Your command timed out after 300 seconds or experienced an OOM error.\n')], 'root')
        report = audit.make_report([session], Path('/project'))
        self.assertEqual(report['flags']['persistent_timeout']['calls'], 1)
        self.assertEqual(report['included']['tool_error_flags'], 0)

    def test_incomplete_and_negative_calls_are_not_timed(self):
        session = audit.parse_events([header(), call(1, 1000), result(2, 500), call(3, 2000),
                                      result(4, 3000, call_id='unknown')], 'root')
        self.assertEqual(len(session['calls']), 0)
        self.assertEqual(session['unfinished_calls'], 1)
        self.assertEqual(session['orphan_results'], 1)
        self.assertEqual(len(session['issues']), 1)

    def test_commands_are_private_by_default(self):
        session = audit.parse_events([header(), call(1, 0, 'echo private-example'), result(2, 1000)], 'root')
        report = audit.make_report([session], Path('/project'))
        self.assertNotIn('private-example', json.dumps(report))
        report = audit.make_report([session], Path('/project'), include_commands=True)
        self.assertEqual(report['top_calls'][0]['command'], 'echo private-example')

    def test_schema_distinguishes_persistent_from_background_bash(self):
        schema = {'type': 'request/header', 'data': {'header': {'tools': [
            {'name': 'bash', 'parameters': {'properties': {'command': {}}}}]}}}
        session = audit.parse_events([header(), schema, call(1, 0, timeoutMs=900000), result(2, 1000)], 'root')
        report = audit.make_report([session], Path('/project'))
        self.assertEqual(report['unsupported_bash_arguments'], 1)
        self.assertEqual(report['bash_calls_with_background_schema'], 0)

    def test_invalid_json_is_reported_without_dropping_completed_prefix(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'session.jsonl'
            path.write_text('\n'.join(json.dumps(e) for e in [header(), call(1, 0), result(2, 1000)]) + '\n{"partial":')
            session = audit.read_session(path)
        self.assertEqual(len(session['calls']), 1)
        self.assertIn('invalid/incomplete JSON at line 4', session['issues'])

    @unittest.skipUnless(shutil.which('zstd'), 'zstd is not installed')
    def test_concatenated_zstd_frames_and_truncated_tail(self):
        prefix = '\n'.join(json.dumps(e) for e in [header(), call(1, 0), result(2, 1000)]) + '\n'
        first = subprocess.run(['zstd', '-qc'], input=prefix.encode(), capture_output=True, check=True).stdout
        second = subprocess.run(['zstd', '-qc'], input=(json.dumps(call(3, 2000)) + '\n').encode(), capture_output=True, check=True).stdout
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'session.jsonl.zstd'
            path.write_bytes(first + second)
            complete = audit.read_session(path)
            path.write_bytes(first + second[:5])
            partial = audit.read_session(path)
        self.assertEqual(len(complete['calls']), 1)
        self.assertEqual(complete['unfinished_calls'], 1)
        self.assertEqual(complete['issues'], [])
        self.assertEqual(len(partial['calls']), 1)
        self.assertTrue(any('zstd exited' in issue for issue in partial['issues']))

    def test_background_job_separates_execution_delivery_and_reads(self):
        events = [
            header(),
            call(1, 0, command='zig build test-qbe', call_id='bg', run_in_background=True),
            result(2, 100, 'bg', text='started background job bash-7'),
            inbox(3, 5000, 'bash-7'),
            delivered(4, 8000, 'bash-7'),
            call(5, 9000, command='', name='job_output', call_id='r1', job_id='bash-7', wait=True),
            result(6, 9200, 'r1', text='ok\n[status: completed]'),
            call(7, 10000, command='', name='job_output', call_id='r2', job_id='bash-7'),
            result(8, 10050, 'r2', text='ok'),
        ]
        report = audit.make_report([audit.parse_events(events, 'root')], Path('/project'))
        self.assertEqual(len(report['background_jobs']), 1)
        job = report['background_jobs'][0]
        self.assertEqual(job['completion_source'], 'settlement-notice')
        self.assertEqual(job['execution_seconds'], 5.0)
        self.assertEqual(job['notification_delay_seconds'], 3.0)
        self.assertEqual(job['completion_to_consumption_seconds'], 4.0)
        self.assertEqual(job['start_blocked_seconds'], 0.1)
        self.assertEqual(job['read_count'], 2)
        self.assertEqual(job['read_blocked_seconds'], 0.25)
        self.assertEqual(job['wait_calls'], 1)
        self.assertEqual(job['wait_blocked_seconds'], 0.2)
        self.assertEqual(job['outcome'], 'completed')
        summary = report['background_job_summary']
        self.assertEqual(summary['jobs'], 1)
        self.assertEqual(summary['execution_seconds'], 5.0)
        self.assertEqual(summary['notification_delay_seconds'], 3.0)
        self.assertEqual(summary['read_calls'], 2)
        self.assertEqual(summary['wait_calls'], 1)
        self.assertEqual(len(report['job_waits']), 2)

    def test_unmatched_job_wait_is_still_counted(self):
        events = [
            header(),
            call(1, 0, command='', name='job_output', call_id='r', job_id='bash-9', wait=True),
            result(2, 4000, 'r', text='done\n[status: completed]'),
        ]
        report = audit.make_report([audit.parse_events(events, 'root')], Path('/project'))
        self.assertEqual(report['background_job_summary']['read_calls'], 1)
        self.assertEqual(report['background_job_summary']['unmatched_read_calls'], 1)
        self.assertEqual(report['background_job_summary']['unmatched_read_seconds'], 4.0)
        self.assertEqual(len(report['unmatched_job_waits']), 1)
        self.assertEqual(len(report['job_waits']), 1)

    def test_completion_falls_back_to_a_terminal_read_without_a_notice(self):
        events = [
            header(),
            call(1, 0, command='zig build', call_id='bg', run_in_background=True),
            result(2, 100, 'bg', text='started background job bash-3'),
            call(3, 2000, command='', name='job_output', call_id='r', job_id='bash-3', wait=True),
            result(4, 7000, 'r', text='ok\n[status: completed]'),
        ]
        report = audit.make_report([audit.parse_events(events, 'root')], Path('/project'))
        job = report['background_jobs'][0]
        self.assertEqual(job['completion_source'], 'terminal-read')
        self.assertEqual(job['execution_seconds'], 7.0)
        self.assertEqual(job['outcome'], 'completed')

    def test_timeout_without_wait_is_reported_as_misuse(self):
        events = [
            header(),
            call(1, 0, command='', name='job_output', call_id='m', job_id='bash-1', timeout_ms=30000),
            result(2, 10, 'm', text='no new output'),
            call(3, 20, command='', name='job_output', call_id='n', job_id='bash-1', wait=True, timeout_ms=30000),
            result(4, 30, 'n', text='done'),
        ]
        report = audit.make_report([audit.parse_events(events, 'root')], Path('/project'))
        self.assertEqual(report['job_output_timeout_without_wait'], 1)
        self.assertEqual(report['job_output_misuse_calls'][0]['seq'], 1)

    def test_build_dimensions_extracts_the_comparability_key(self):
        self.assertEqual(
            audit.build_dimensions('zig build test-units -Dtest-filter=arena -Doptimize=ReleaseFast --cache-dir=/tmp/c'),
            ('test-units', 'arena', 'ReleaseFast', '/tmp/c'))
        self.assertEqual(audit.build_dimensions('zig build'), ('install', None, 'default', 'default'))
        self.assertEqual(audit.build_dimensions('zig build --help | head'), ('install', None, 'default', 'default'))
        self.assertEqual(audit.build_dimensions('zig build test-qbe --summary all 2>&1 | tail -5'),
                         ('test-qbe', None, 'default', 'default'))

    def test_comparable_build_groups_keep_different_filters_apart(self):
        events = [
            header(),
            call(1, 0, command='zig build test-units -Dtest-filter=arena', call_id='a'), result(2, 1000, 'a'),
            call(3, 2000, command='zig build test-units -Dtest-filter=arena', call_id='b'), result(4, 4000, 'b'),
            call(5, 5000, command='zig build test-units -Dtest-filter=other', call_id='c'), result(6, 9000, 'c'),
        ]
        report = audit.make_report([audit.parse_events(events, 'root')], Path('/project'))
        groups = report['comparable_build_groups']
        self.assertEqual(len(groups), 2)
        by_filter = {row['test_filter']: row for row in groups}
        self.assertEqual(by_filter['arena']['calls'], 2)
        self.assertEqual(by_filter['other']['calls'], 1)
        self.assertIn('not a speedup ratio', ' '.join(report['limitations']))


if __name__ == '__main__':
    unittest.main()
