from pathlib import Path
import tempfile
import unittest
from experiments.application_comparison import session, tool_metrics
from experiments.application_comparison.participant_gateway import Gateway
from experiments.application_comparison.storage import read_json, write_json


class ToolMetricsTests(unittest.TestCase):
    def test_only_direct_declared_language_tools_are_counted(self):
        tools = {'compiler': {}, 'navigate': {}}
        self.assertEqual(tool_metrics.language_tool(['/usr/bin/python3', '-S', '-B', '/tools/navigate', '--query', 'x'], tools), 'navigation-client')
        self.assertEqual(tool_metrics.language_tool(['/tools/compiler', 'index-project', '/work/main.my'], tools), 'compiler-index')
        self.assertEqual(tool_metrics.language_tool(['/tools/compiler', 'discover-project-duplicates', '/work/main.my'], tools), 'compiler-duplicates')
        for argv in (['/bin/sh', '-c', '/tools/compiler index-project /work/main.my'],
                     ['/usr/bin/python3', '-c', '/tools/navigate'], ['/work/navigate'],
                     ['/tools/compiler', 'run-project', '/work/main.my']):
            self.assertIsNone(tool_metrics.language_tool(argv, tools))
        self.assertIsNone(tool_metrics.language_tool(['/tools/compiler', 'index-project', '/work/main.my'], {}))

    def test_interval_union_does_not_sum_overlaps(self):
        self.assertEqual(tool_metrics.interval_seconds([(0, 2000000000), (1000000000, 3000000000), (4000000000, 5000000000)]), 4)
        with self.assertRaises(ValueError):
            tool_metrics.interval_seconds([(2, 1)])

    def test_real_gateway_commands_and_unchanged_checks(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            baseline = root / 'baseline'
            baseline.mkdir()
            (baseline / 'main.py').write_text('print(1)')
            active = root / 'session'
            session.prepare(active, baseline, language='python', block='fixture', cohort='fixture', participant='fixture', model='fixture')
            navigation_fixture = root / 'navigate.py'
            navigation_fixture.write_text('raise SystemExit(1)')
            gateway = Gateway(active, {'navigate': navigation_fixture})
            session.start_preparation(active)
            gateway.dispatch('command', {'argv': ['/usr/bin/python3', '-c', 'print("practice")']})
            session.start_task(active, 'passed')
            gateway.dispatch('command', {'argv': ['/usr/bin/python3', '-c', 'raise SystemExit(1)']})
            gateway.dispatch('command', {'argv': ['/usr/bin/python3', '-S', '-B', '/tools/navigate']})
            for index in range(2):
                row = session.submit(active)
                session.record_check(active, index, {'source_sha256': row['source']['sha256'], 'passed': True})
            result = tool_metrics.summarize(active)
            self.assertEqual(result['phases']['preparing']['command_count'], 1)
            self.assertEqual(result['phases']['preparing']['captured_output_bytes'], 9)
            self.assertEqual(result['phases']['working']['failed_commands'], 2)
            self.assertEqual(result['phases']['working']['language_tool_commands'], {'navigation-client': 1})
            self.assertEqual(result['phases']['working']['failed_language_tool_commands'], {'navigation-client': 1})
            self.assertEqual(result['phases']['preparing']['language_tool_commands'], {})
            self.assertEqual(result['adjacent_unchanged_task_checks'], 1)
            self.assertEqual(len(result['submission_to_check_seconds']), 2)
            self.assertIsNone(result['cache_hits'])
            orphan = active / 'gateway/999999'
            orphan.mkdir()
            write_json(orphan / 'request.json', {'unfinished': True})
            self.assertEqual(tool_metrics.summarize(active)['uncommitted_command_records'], ['999999'])
            path = next((active / 'gateway').glob('*/result.json'))
            changed = read_json(path)
            changed['returncode'] = 22
            write_json(path, changed)
            with self.assertRaisesRegex(ValueError, 'identity mismatch'):
                tool_metrics.summarize(active)


if __name__ == '__main__':
    unittest.main()
