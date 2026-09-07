"""Frozen environment selection, inventory validation, and a complete Python fixture."""
import json
from pathlib import Path
import tempfile
import shutil
import unittest
from experiments.application_comparison import cohort, cohort_sessions, environment_receipt, practice_pack, scheduled_driver, session, session_driver, task_pack, trial_configuration, coordinator_receipt, coordinator_run
from experiments.application_comparison.execution import freeze_adapter
from experiments.application_comparison.storage import digest, read_json, write_json

ROOT = Path(__file__).resolve().parents[2] / 'experiments/application_comparison'


class EnvironmentCohortTests(unittest.TestCase):
    def test_frozen_environment_survives_origin_mutation_and_is_used_by_session(self):
        self.run_bound_case(False)

    def test_full_configuration_is_frozen_and_cannot_be_overridden(self):
        self.run_bound_case(True)

    def run_bound_case(self, configured):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            task = 'planner-input-boundary'
            pack = root / 'pack'
            task_pack.create(pack, task=task, hidden_seed='environment-construction-only')
            practices = {}
            for language in cohort.LANGUAGES:
                practices[language] = root / ('practice-' + language)
                practice_pack.create(practices[language], language=language)
            blocks = [dict(id=task, application='planner', tier='small', family='local-boundary')]
            receipt = environment_receipt.capture()
            environments = {key: receipt for key in cohort.environment_keys(cohort.schedule(blocks, seed='fixture'))}
            settings = dict(blocks=blocks, seed='fixture', model_settings={'model': 'fixture-model'},
                budgets=dict(preparation_seconds=1200, task_seconds=1800, max_submissions=20,
                             max_output_tokens=37, max_turns=6),
                baseline_paths={f'planner/small/{language}': ROOT / 'baselines/planner' / language
                                for language in cohort.LANGUAGES},
                task_paths={task: pack}, practice_paths=practices, environments=environments)
            if configured:
                toolchain = root / 'toolchain'
                toolchain.mkdir()
                (toolchain / 'lib').mkdir()
                (toolchain / 'zig').write_text('fixture executable; never executed')
                host = root / 'host'
                host.write_text('fixture VM; never executed')
                settings.pop('environments')
                configurations = {}
                for condition in environments:
                    arm, _, language = condition.split('/')
                    configurations[condition] = trial_configuration.freeze(language, 'planner', arm,
                        zig=toolchain, guardian=host, byte_io=host, compiler=host, navigate=host)
                settings['configurations'] = configurations
            solution = (ROOT / 'practice/python/solution/main.py').read_text()
            calls = []
            def complete(body, timeout):
                calls.append(body)
                index = len(calls)
                if index == 1:
                    name, arguments = 'command', {'argv': ['/usr/bin/python3', '-c',
                        'from pathlib import Path; Path("main.py").write_text(' + repr(solution) + ')']}
                elif index == 4:
                    name, arguments = 'command', {'argv': ['/usr/bin/python3', '-c',
                        "from pathlib import Path; p=Path('planner.py'); p.write_text(p.read_text().replace('if len(payload) >= MAX_INPUT_BYTES:', 'if len(payload) > MAX_INPUT_BYTES:'))"]}
                elif index in (2, 5):
                    name, arguments = 'check', {}
                else:
                    name, arguments = 'finish', {'reason': 'completed'}
                return {'model': 'fixture-model', 'id': f'r{index}', 'status': 'completed',
                    'usage': {'input_tokens': 1, 'output_tokens': 1, 'total_tokens': 2},
                    'output': [{'type': 'function_call', 'call_id': f'c{index}', 'name': name,
                                'arguments': json.dumps(arguments)}]}
            if configured:
                planned = [complete({}, 1) for _ in range(6)]
                calls.clear()
                frozen_transport = 'fixture-replay:' + digest(planned)
                settings['coordinator'] = coordinator_receipt.capture(frozen_transport)
            frozen = root / 'cohort'
            manifest = cohort.freeze(frozen, **settings)
            self.assertEqual(manifest['version'], 'application-cohort-v5' if configured else 'application-cohort-v3')
            self.assertFalse(manifest['launch_authorized'])
            key = f'main/{task}/python'
            original = read_json(frozen / 'cohort.json')
            changed = read_json(frozen / 'cohort.json')
            changed['environments'][key]['cpu_count'] += 1
            write_json(frozen / 'cohort.json', changed)
            with self.assertRaisesRegex(ValueError, 'definition changed'):
                cohort.load(frozen)
            write_json(frozen / 'cohort.json', original)
            if configured:
                del configurations[key]
            else:
                del environments[key]
            with self.assertRaisesRegex(ValueError, 'every scheduled'):
                cohort.freeze(root / 'incomplete', **settings)
            self.assertFalse((root / 'incomplete').exists())
            self.assertEqual(cohort.load(frozen), manifest)
            envelope = root / 'attempt'
            cohort_sessions.prepare_fixture(frozen, task + '-r1-python', envelope)
            adapter = freeze_adapter('python', {}, [{'phase': 'run', 'argv': ['/usr/bin/python3', '-S', '-B', 'planner.py']}])
            practice_adapter = freeze_adapter('python', {}, [{'phase': 'run', 'argv': ['/usr/bin/python3', '-S', '-B', 'main.py']}])
            prepared = session.load(envelope / 'session')
            self.assertEqual(prepared['environment_sha256'], receipt['sha256'])
            with self.assertRaisesRegex(ValueError, 'frozen coordinator receipt' if configured else 'frozen environment'):
                session_driver.run_fixture(envelope / 'session', None, tools={}, task_adapter=adapter,
                    practice_adapter=practice_adapter, task_case=None, practice_case=None,
                    practice_source=None, practice_prompt='practice', task_prompt='task', transport_identity='fixture')
            if configured:
                with self.assertRaisesRegex(ValueError, 'cohort transport'):
                    scheduled_driver.run_fixture(frozen, envelope, complete, transport_identity='different')
                with self.assertRaisesRegex(ValueError, 'fresh verified coordinator'):
                    scheduled_driver.run_fixture(frozen, envelope, complete, transport_identity=frozen_transport)
                with self.assertRaisesRegex(ValueError, 'cannot be overridden'):
                    scheduled_driver.run_fixture(frozen, envelope, complete, tools={}, transport_identity=frozen_transport)
                self.assertFalse(calls)
                responses = [complete({}, 1) for _ in range(6)]
                transport = 'fixture-replay:' + digest(responses)
                request = root / 'fresh-request.json'
                write_json(request, {'operation': 'fixture', 'coordinator': manifest['coordinator'],
                    'transport_identity': transport, 'responses': responses, 'cohort': str(frozen), 'envelope': str(envelope)})
                launch = root / 'fresh-launch'
                execution = coordinator_run.run(read_json(request), launch, wall_seconds=60)
                self.assertEqual(execution['outcome'], 'completed', (launch / 'stderr').read_text())
                fresh = read_json(launch / 'stdout')
                self.assertEqual(fresh['source_imports'], 'verified-in-memory-bytes')
                self.assertEqual(fresh['model_calls'], 0)
                result = fresh['result']
            else:
                result = scheduled_driver.run_fixture(frozen, envelope, complete, tools={},
                    task_adapter=adapter, practice_adapter=practice_adapter, transport_identity='fixture')
            self.assertEqual(len(calls), 6)
            self.assertEqual(result['environment']['status'], 'before-and-after-verified')
            self.assertEqual(result['environment']['sha256'], manifest['environments'][key]['sha256'])
            self.assertEqual(result['seal_reason'], 'completed')
            self.assertTrue(result['preparation']['usage_complete'])
            final = session.load(envelope / 'session')
            evidence = environment_receipt.grading_evidence(envelope / 'session', final)
            self.assertEqual(evidence['sha256'], receipt['sha256'])
            if configured:
                self.assertEqual(final['coordinator_sha256'], manifest['coordinator']['sha256'])
                after_path = envelope / 'session/driver/coordinator-after.json'
                recorded = read_json(after_path)
                after_path.unlink()
                with self.assertRaisesRegex(ValueError, 'missing required coordinator'):
                    environment_receipt.grading_evidence(envelope / 'session', final)
                write_json(after_path, recorded)
            if configured:
                calibration = root / 'calibration-cohort'
                shutil.copytree(frozen, calibration)
                definition = read_json(calibration / 'cohort.json')
                definition['record_kind'] = 'calibration'
                definition['sha256'] = digest({name: value for name, value in definition.items() if name != 'sha256'})
                write_json(calibration / 'cohort.json', definition)
                prepared_calibration = cohort_sessions.prepare_calibration(calibration, task + '-r1-python', root / 'calibration-attempt')
                self.assertEqual(prepared_calibration['record_kind'], 'calibration')
                self.assertEqual(session.load(root / 'calibration-attempt/session')['record_kind'], 'calibration')
                self.assertTrue((calibration / 'calibration-reservations/main' / (task + '-r1-python') / 'reservation.json').exists())
                with self.assertRaises(ValueError):
                    cohort_sessions.prepare_fixture(calibration, task + '-r2-python', root / 'wrong-kind')
            (envelope / 'session/driver/environment-after.json').unlink()
            with self.assertRaisesRegex(ValueError, 'missing required'):
                environment_receipt.grading_evidence(envelope / 'session', final)


if __name__ == '__main__':
    unittest.main()
