"""Declaration-store gateway: verb dispatch, retention, checks through the branch rendering.

Runs the real compiler, the real byte host and the real store; no model participant.
"""
import json
from pathlib import Path
import shutil
import tempfile
import unittest

from experiments.application_comparison import practice_cases, session
from experiments.application_comparison.execution import freeze_adapter
from experiments.application_comparison.storage import digest, inventory, read_json, source_files
from experiments.development_velocity import runner, telemetry

REPO = Path(__file__).resolve().parents[2]
PRACTICE = REPO / 'experiments/application_comparison/practice/my'
COMPILER = REPO / 'zig-out/bin/mylang'
HOST = REPO / 'zig-out/bin/mylang-io'
MARKER = 'def store_gateway_marker(value: i64) -> i64:\n    return value\n'


def available():
    return COMPILER.is_file() and HOST.is_file()


@unittest.skipUnless(available(), 'requires zig build outputs')
class StoreGatewayTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='store-gateway-')
        self.addCleanup(self.temporary.cleanup)
        parent = Path(self.temporary.name)
        baseline = parent / 'baseline'
        shutil.copytree(PRACTICE / 'solution', baseline,
                        ignore=shutil.ignore_patterns('check_practice.py'))
        module = telemetry.load_frozen(REPO / 'scripts/store_server.py').store
        # The store arm's baseline is its own rendering, so protected files never drift.
        runner.canonicalize(baseline, COMPILER, module)
        public = baseline / '.trial-public'
        public.mkdir()
        (public / 'TASK.md').write_text('# Fixture task\n\nOnboarding fixture, never a scored task.\n')
        self.cases = practice_cases.cases()
        self.root = parent / 'attempt'
        protected = [str(path.relative_to(baseline)) for path in sorted(baseline.rglob('*'))
                     if path.is_file() and ('.trial-public' in path.parts or
                                            path.name in ('main.my', 'io.my'))]
        session.prepare(self.root, baseline, language='my', block='fixture', cohort='store-fixture',
                        participant='store-fixture', model='fixture', kind='fixture',
                        arm='declaration-store', protected=protected)
        runner.import_store(module, self.root / 'store.sqlite', COMPILER, baseline)
        session.start_preparation(self.root)
        session.start_task(self.root, 'passed')
        for path in sorted((self.root / 'work').rglob('*.my')):
            path.unlink()
        tools = {'compiler': str(COMPILER), 'byte_io': str(HOST),
                 'stdlib': str(REPO / 'src/stdlib'), 'workflow': str(REPO / 'scripts'),
                 'store_server': str(REPO / 'scripts/store_server.py')}
        adapter = freeze_adapter('my', {key: tools[key] for key in ('compiler', 'byte_io', 'stdlib', 'workflow')},
                                 [{'phase': 'run', 'argv': ['/tools/byte_io', '--project', '/work', '--timings=json']}],
                                 runner.LIMITS)
        self.gateway = telemetry.StoreGateway(self.root, tools, runner.LIMITS, adapter=adapter,
                                              public_case=self.cases)

    def test_verbs_are_dispatched_recorded_and_checked_through_the_rendering(self):
        gateway = self.gateway
        opened = gateway.dispatch('open', {})
        self.assertEqual(opened['version'], 'store-session-v1')
        self.assertEqual(opened['record'], 0)
        self.assertNotIn('operation_record', opened)  # The session record number is the only one.
        modules = {row['module']: row['protected'] for row in opened['modules']}
        self.assertEqual(modules, {'helper': False, 'io': True, 'main': True})
        self.assertTrue(any(row['name'] == '.trial-public/TASK.md' for row in opened['assets']))

        context = gateway.dispatch('context', {'ids': ['helper::multiply']})
        entry = context['entries'][0]
        self.assertIn('fn multiply', entry['source'])
        self.assertRegex(entry['hash'], '^[0-9a-f]{64}$')
        self.assertEqual(gateway.dispatch('search', {'text': 'multiply'})['mode'], 'text')
        page = gateway.dispatch('asset', {'name': '.trial-public/TASK.md', 'offset': 0, 'limit': 64})
        self.assertEqual(page['offset'], 0)
        self.assertTrue(page['text'])

        answer = gateway.dispatch('context', {'ids': ['main::answer']})['entries'][0]
        self.assertTrue(answer['protected'])  # Protected declarations read, and never write.
        protected = gateway.dispatch('batch', {'ops': [{'op': 'remove', 'id': 'main::answer'}],
                                               'if_match': {'main::answer': answer['hash']}})
        self.assertEqual(protected['status'], 'rejected')
        self.assertEqual(protected['scope_violations'], ['main::answer'])
        self.assertEqual([row['reason'] for row in protected['rejections']], ['protected-declaration'])
        conflict = gateway.dispatch('batch', {'ops': [{'op': 'replace', 'id': 'helper::multiply',
                                                       'source': entry['source']}],
                                              'if_match': {'helper::multiply': '1' * 64}})
        self.assertEqual(conflict['reason'], 'if-match-mismatch')

        committed = gateway.dispatch('batch', {'ops': [{'op': 'add', 'module': 'helper',
                                                        'source': MARKER}], 'if_match': {}})
        self.assertEqual(committed['status'], 'committed')
        self.assertEqual([row['id'] for row in committed['applied']], ['helper::store_gateway_marker'])
        probe = gateway.dispatch('probe', {'request': {}})
        self.assertEqual(probe['outcome'], 'exited')

        checked = gateway.dispatch('check', {})
        self.assertTrue(checked['passed'], checked)
        self.assertEqual(checked['submission'], 0)
        self.assertEqual(checked['scope_violations'], [])
        manifest = session.load(self.root)
        published = self.root / 'submissions/000/source'
        self.assertIn('fn store_gateway_marker', (published / 'helper.my').read_text())
        self.assertEqual(inventory(source_files(published)), manifest['submissions'][0]['source']['files'])
        self.assertEqual(manifest['submissions'][0]['scope_violations'], [])

        paged = gateway.dispatch('output', {'record': 0, 'offset': 0, 'limit': 256})
        self.assertEqual(paged['source_record'], 0)
        self.assertTrue(paged['text'].startswith('{'))

        sealed = gateway.dispatch('finish', {'reason': 'completed'})
        self.assertEqual((sealed['phase'], sealed['reason']), ('sealed', 'completed'))
        self.assertEqual(session.load(self.root)['phase'], 'sealed')

        records = sorted((self.root / 'telemetry').glob('[0-9]' * 6))
        operations = [read_json(path / 'request.json')['operation'] for path in records]
        self.assertEqual(operations, ['open', 'context', 'search', 'asset', 'context', 'batch',
                                      'batch', 'batch', 'probe', 'check', 'output', 'finish'])
        for path in records:
            result = read_json(path / 'result.json')
            self.assertEqual(result['request_sha256'], digest(read_json(path / 'request.json')))
            self.assertTrue(result['source_capture_complete'])
        added = read_json(records[7] / 'result.json')
        self.assertEqual(added['changed_files'], ['helper.my'])

        profile = telemetry.summarize(self.root, arm='my-store', interface='store')
        metrics = profile['store_metrics']
        self.assertEqual(set(metrics), set(telemetry.STORE_METRICS))
        self.assertEqual(metrics['verb_counts'], {'open': 1, 'context': 2, 'search': 1, 'asset': 1,
                                                  'batch': 3, 'probe': 1, 'check': 1, 'output': 1,
                                                  'finish': 1})
        self.assertEqual((metrics['batch_rejections'], metrics['if_match_conflicts']), (2, 1))
        self.assertEqual(metrics['context_omitted_total'], 0)
        self.assertGreater(metrics['bytes_returned'], 0)
        self.assertEqual(profile['interface'], 'store')
        self.assertEqual(profile['arm'], 'my-store')
        self.assertEqual([row['operation'] for row in profile['operations']], operations)

    def test_unknown_operations_and_command_are_refused(self):
        for name, arguments in (('command', {'argv': ['/usr/bin/true']}), ('render', {})):
            with self.subTest(name=name), self.assertRaisesRegex(ValueError, 'unknown participant operation'):
                self.gateway.dispatch(name, arguments)
        with self.assertRaisesRegex(ValueError, 'invalid command purpose'):
            self.gateway.dispatch('open', {'purpose': 'inspect'})

    def test_the_rendered_snapshot_is_reused_until_the_branch_changes(self):
        self.gateway.dispatch('open', {})
        cache = read_json(self.root / 'store/renders.json')['snapshot']
        self.assertTrue(Path(cache['path']).is_dir())
        self.gateway.dispatch('search', {'text': 'fn'})
        self.assertEqual(read_json(self.root / 'store/renders.json')['snapshot']['path'], cache['path'])
        self.gateway.dispatch('batch', {'ops': [{'op': 'add', 'module': 'helper', 'source': MARKER}],
                                        'if_match': {}})
        moved = read_json(self.root / 'store/renders.json')['snapshot']
        self.assertNotEqual(moved['path'], cache['path'])
        self.assertNotEqual(moved['inventory_sha256'], cache['inventory_sha256'])
        text = json.dumps(self.gateway.dispatch('open', {}))
        self.assertNotIn(str(self.root / 'store'), text)


if __name__ == '__main__':
    unittest.main()
