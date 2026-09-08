from pathlib import Path
import tempfile
import unittest
from experiments.application_comparison import session
from experiments.application_comparison.participant_gateway import Gateway
from experiments.application_comparison.storage import read_json, write_json


class ParticipantGatewayTests(unittest.TestCase):
    def test_phase_mounts_private_records_and_exact_tool_surface(self):
        with tempfile.TemporaryDirectory() as temporary:
            parent = Path(temporary)
            baseline = parent / 'baseline'
            baseline.mkdir()
            (baseline / 'task.txt').write_text('scored source')
            root = parent / 'session'
            session.prepare(root, baseline, language='python', block='fixture', cohort='fixture',
                            participant='fixture', model='fixture')
            gateway = Gateway(root, {})
            with self.assertRaisesRegex(ValueError, 'not active'):
                gateway.dispatch('command', {'argv': ['true']})
            session.start_preparation(root)
            result = gateway.dispatch('command', {'argv': ['/usr/bin/python3', '-c',
                'from pathlib import Path;assert not Path("/work/task.txt").exists();Path("/work/practice.txt").write_text("practice")']})
            self.assertEqual(result['returncode'], 0, result)
            session.start_task(root, 'passed')
            result = gateway.dispatch('command', {'argv': ['/usr/bin/python3', '-c',
                'from pathlib import Path;assert Path("/work/task.txt").read_text()=="scored source";'
                'assert not Path("/work/practice.txt").exists();assert not Path("/session.json").exists();'
                'Path("/work/new.txt").write_text("edit");print("ok")']})
            self.assertEqual(result['stdout'], 'ok\n', result)
            self.assertEqual((root / 'work/new.txt').read_text(), 'edit')
            records = list((root / 'gateway').glob('*/result.json'))
            self.assertEqual(len(records), 2)
            self.assertTrue(all(read_json(path)['isolated'] for path in records))
            for name, args in [('grade', {}), ('command', {'argv': ['true'], 'cwd': '/'}),
                               ('command', {'argv': 'true'})]:
                with self.assertRaises(ValueError):
                    gateway.dispatch(name, args)
            manifest = read_json(root / 'session.json')
            manifest['task_started']['monotonic_ns'] -= 1801 * 1000000000
            write_json(root / 'session.json', manifest)
            with self.assertRaisesRegex(ValueError, 'deadline exhausted'):
                gateway.dispatch('command', {'argv': ['true']})
            self.assertEqual(len(list((root / 'gateway').glob('*/result.json'))), 2)

    def test_opt_in_retains_each_command_cache_without_cross_command_reuse(self):
        with tempfile.TemporaryDirectory() as temporary:
            parent = Path(temporary)
            baseline = parent / 'baseline'
            baseline.mkdir()
            (baseline / 'main.py').write_text('pass')
            root = parent / 'session'
            session.prepare(root, baseline, language='python', block='fixture', cohort='fixture', participant='fixture', model='fixture')
            gateway = Gateway(root, {}, retain_command_cache=True)
            session.start_preparation(root)
            for value in ('first', 'second'):
                code = "from pathlib import Path;p=Path('/cache/report.json');assert not p.exists();p.write_text(" + repr(value) + ")"
                self.assertEqual(0, gateway.dispatch('command', {'argv': ['/usr/bin/python3', '-c', code]})['returncode'])
            reports = sorted((root / 'gateway').glob('*/cache/report.json'))
            self.assertEqual(['first', 'second'], [p.read_text() for p in reports])
            results = sorted((root / 'gateway').glob('*/result.json'))
            self.assertTrue(all('retained_cache' in read_json(p) for p in results))
            with self.assertRaisesRegex(ValueError, 'configuration changed'):
                Gateway(root, {})


if __name__ == '__main__':
    unittest.main()

class PublicCheckGatewayTests(unittest.TestCase):
    def setUp(self):
        from experiments.application_comparison.execution import freeze_adapter
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        parent = Path(self.temp.name)
        baseline = parent / 'baseline'
        baseline.mkdir()
        (baseline / 'main.py').write_text('import json,sys; print(json.dumps(json.load(sys.stdin)))')
        self.root = parent / 'session'
        session.prepare(self.root, baseline, language='python', block='fixture', cohort='fixture',
                        participant='fixture', model='fixture')
        self.adapter = freeze_adapter('python', {}, [
            {'phase': 'run', 'argv': ['/usr/bin/python3', '-S', '-B', 'main.py']}])
        self.case = {'request': {'value': 42}, 'expected': {'value': 42}}
        self.gateway = Gateway(self.root, {}, adapter=self.adapter, public_case=self.case)
        session.start_preparation(self.root)
        session.start_task(self.root, 'passed')

    def test_checked_completion_rejects_unchecked_edits_and_config_changes(self):
        with self.assertRaisesRegex(ValueError, 'checked'):
            self.gateway.dispatch('finish', {'reason': 'completed'})
        result = self.gateway.dispatch('check', {})
        self.assertTrue(result['passed'], result)
        self.assertIn('42', result['diagnostics'][0]['stdout'])
        (self.root / 'work/new.py').write_text('change = True')
        with self.assertRaisesRegex(ValueError, 'final edits'):
            self.gateway.dispatch('finish', {'reason': 'completed'})
        self.case['expected'] = None  # Caller mutation cannot change a live gateway.
        self.assertTrue(self.gateway.dispatch('check', {})['passed'])
        with self.assertRaisesRegex(ValueError, 'configuration changed'):
            Gateway(self.root, {}, adapter=self.adapter, public_case=self.case)
        sealed = self.gateway.dispatch('finish', {'reason': 'completed'})
        self.assertEqual(sealed, {'phase': 'sealed', 'reason': 'completed', 'final_submission': 1})
        with self.assertRaisesRegex(ValueError, 'active task'):
            self.gateway.dispatch('check', {})

    def test_late_completion_is_preserved_as_budget(self):
        manifest = read_json(self.root / 'session.json')
        manifest['task_started']['monotonic_ns'] -= 1801 * 1000000000
        write_json(self.root / 'session.json', manifest)
        with self.assertRaisesRegex(ValueError, 'budget exhausted'):
            self.gateway.dispatch('check', {})
        result = self.gateway.dispatch('finish', {'reason': 'completed'})
        self.assertEqual(result['reason'], 'budget')
        self.assertIsNone(result['final_submission'])

    def test_required_check_cannot_outlive_remaining_budget(self):
        (self.root / 'work/main.py').write_text('import time; time.sleep(10); print("{}")')
        manifest = read_json(self.root / 'session.json')
        manifest['task_started']['monotonic_ns'] = session.clock()['monotonic_ns'] - 1798 * 1000000000
        write_json(self.root / 'session.json', manifest)
        result = self.gateway.dispatch('check', {})
        self.assertFalse(result['passed'])
        stored = session.load(self.root)['submissions'][0]['check']
        self.assertFalse(stored['passed'])
        self.assertEqual(stored['steps'][0]['outcome'], 'timeout')
        self.assertLessEqual(stored['steps'][0]['limits']['wall_seconds'], 2)

    def test_main_zig_public_check_requires_guardian_phase(self):
        from experiments.application_comparison.execution import freeze_adapter
        manifest = read_json(self.root / 'session.json')
        manifest.update(language='zig', record_kind='agent')
        write_json(self.root / 'session.json', manifest)
        adapter = freeze_adapter('zig', {}, [
            {'phase': 'run', 'argv': ['/usr/bin/python3', '-S', '-B', 'main.py']}])
        with self.assertRaisesRegex(ValueError, 'trusted Guardian'):
            Gateway(self.root, {}, adapter=adapter, public_case=self.case)
        fake = freeze_adapter('zig', {}, [
            {'phase': 'guardian', 'argv': ['/usr/bin/true']},
            {'phase': 'run', 'argv': ['/usr/bin/python3', '-S', '-B', 'main.py']}])
        with self.assertRaisesRegex(ValueError, 'trusted Guardian'):
            Gateway(self.root, {}, adapter=fake, public_case=self.case)
