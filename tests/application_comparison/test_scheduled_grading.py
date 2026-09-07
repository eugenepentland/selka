"""Full fresh-process pipeline with three deliberately abandoned fixture attempts."""
from pathlib import Path
import tempfile
import shutil
import unittest
from experiments.application_comparison import cohort, cohort_summary, cohort_sessions, coordinator_receipt, coordinator_run, practice_pack, scheduled_grading, task_pack, trial_configuration
from experiments.application_comparison.storage import digest, read_json

ROOT = Path(__file__).resolve().parents[2] / 'experiments/application_comparison'


class ScheduledGradingTests(unittest.TestCase):
    def test_abandoned_registered_trio_remains_in_fresh_hidden_grading(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            toolchain = root / 'toolchain'
            toolchain.mkdir()
            (toolchain / 'lib').mkdir()
            (toolchain / 'zig').write_text('fixture compiler; never executed')
            host = root / 'host'
            host.write_text('fixture runtime; never executed')
            task = 'planner-input-boundary'
            task_pack.create(root / 'task', task=task, hidden_seed='abandoned-trio-construction-only')
            practices, configurations = {}, {}
            for language in cohort.LANGUAGES:
                practices[language] = root / ('practice-' + language)
                practice_pack.create(practices[language], language=language)
                for arm in ('main', 'language-focused'):
                    configurations[f'{arm}/{task}/{language}'] = trial_configuration.freeze(language, 'planner', arm,
                        zig=toolchain, guardian=host, byte_io=host, compiler=host, navigate=host)
            responses = [{'model': 'fixture-model', 'id': f'r{index}', 'status': 'completed',
                'usage': {'input_tokens': 1, 'output_tokens': 1, 'total_tokens': 2},
                'output': [{'type': 'function_call', 'call_id': f'c{index}', 'name': 'finish',
                            'arguments': '{"reason":"abandoned"}'}]} for index in (1, 2)]
            transport = 'fixture-replay:' + digest(responses)
            provenance = coordinator_receipt.capture(transport)
            frozen = root / 'cohort'
            cohort.freeze(frozen, blocks=[dict(id=task, application='planner', tier='small', family='local-boundary')],
                seed='fixture', model_settings={'model': 'fixture-model'},
                budgets=dict(preparation_seconds=1200, task_seconds=1800, max_submissions=20, max_output_tokens=37, max_turns=6),
                baseline_paths={f'planner/small/{language}': ROOT / 'baselines/planner' / language for language in cohort.LANGUAGES},
                task_paths={task: root / 'task'}, practice_paths=practices, configurations=configurations, coordinator=provenance)
            roots = []
            for language in cohort.LANGUAGES:
                envelope = root / language
                cohort_sessions.prepare_fixture(frozen, f'{task}-r1-{language}', envelope)
                request = {'operation': 'fixture', 'cohort': str(frozen), 'envelope': str(envelope),
                           'coordinator': provenance, 'transport_identity': transport, 'responses': responses}
                output = root / ('launch-' + language)
                run = coordinator_run.run(request, output, wall_seconds=60)
                self.assertEqual(run['outcome'], 'completed', (output / 'stderr').read_text())
                self.assertEqual(read_json(output / 'stdout')['result']['seal_reason'], 'abandoned')
                roots.append(envelope / 'session')
            with self.assertRaisesRegex(ValueError, 'fresh verified'):
                scheduled_grading.run_fixture(frozen, roots, root / 'forbidden', transport_identity=transport)
            self.assertFalse((root / 'forbidden').exists())
            request = {'operation': 'grade-fixture', 'cohort': str(frozen), 'roots': [str(path) for path in roots],
                       'directory': str(root / 'grading'), 'coordinator': provenance, 'transport_identity': transport}
            output = root / 'grade-launch'
            run = coordinator_run.run(request, output, wall_seconds=60)
            self.assertEqual(run['outcome'], 'completed', (output / 'stderr').read_text())
            report = read_json(root / 'grading/result.json')
            self.assertFalse(report['comparative_claim'])
            graded = report['grading']['grading']
            for language in cohort.LANGUAGES:
                self.assertFalse(graded['outcomes'][language]['accepted'])
                for case in graded['cases']:
                    self.assertEqual(case['result']['outcomes'][language]['reason'], 'no-submission')
            self.assertTrue((root / 'grading/coordinator-after.json').exists())
            self.assertTrue((root / 'grading/verified/environment-after.json').exists())
            summary = cohort_summary.summarize(frozen, [root / 'grading'])
            for language in cohort.LANGUAGES:
                values = summary['languages'][language]
                self.assertEqual((values['assigned'], values['graded'], values['accepted']), (2, 1, 0))
                self.assertEqual(values['status_counts'], {'graded': 1, 'not-launched': 1})
                self.assertFalse(values['grading_complete'])
            for comparison in summary['paired'].values():
                self.assertEqual(comparison['assigned_pairs'], 2)
                self.assertEqual(comparison['neither_accepted'], 1)
                self.assertEqual(comparison['incomplete'], 1)
                self.assertIsNone(comparison['task_time_ratio_when_both_accepted']['median_ratio'])
            copied = roots[0].parent / 'copied-session'
            shutil.copytree(roots[0], copied)
            changed = dict(request, roots=[str(copied), *[str(path) for path in roots[1:]]],
                           directory=str(root / 'copied-grading'))
            rejected = coordinator_run.run(changed, root / 'copied-grade-launch', wall_seconds=60)
            self.assertEqual(rejected['outcome'], 'failed')
            self.assertIn('registered session directory', (root / 'copied-grade-launch/stderr').read_text())
            self.assertFalse((root / 'copied-grading').exists())
            with self.assertRaisesRegex(ValueError, 'duplicate grading'):
                cohort_summary.summarize(frozen, [root / 'grading', root / 'grading'])


if __name__ == '__main__':
    unittest.main()
