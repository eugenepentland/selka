from pathlib import Path
import tempfile
import copy
from experiments.application_comparison.storage import digest
import unittest
from unittest.mock import patch
from experiments.application_comparison import trial_configuration as config


class TrialConfigurationTests(unittest.TestCase):
    def test_condition_commands_and_complete_tool_mounts(self):
        # Unit test command selection without scanning the entire host per condition.
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / 'lib').mkdir()
            (root / 'zig').write_text('compiler')
            host = root / 'byte-host'
            host.write_text('vm')
            guardian = root / 'guardian'
            guardian.write_text('gate')
            with patch.object(config.environment_receipt, 'capture', return_value={'fixture': True}) as capture:
                for app in ('planner', 'eda'):
                    for language in ('my', 'python', 'zig'):
                        for arm in ('main', 'language-focused'):
                            item = config.freeze(language, app, arm, zig=root, guardian=guardian, byte_io=host, compiler=host, navigate=host)
                            phases = [step['phase'] for step in item['task_adapter']['commands']]
                            self.assertEqual('guardian' in phases, language == 'zig' and arm == 'main')
                            self.assertNotIn('guardian', [step['phase'] for step in item['practice_adapter']['commands']])
                            self.assertFalse(item['scored_launch_authorized'])
                            paths = capture.call_args.kwargs['tools']
                            if language == 'zig':
                                self.assertEqual(paths['task:zig'], str(root))
                                self.assertEqual(paths['practice:zig'], str(root))
                            elif language == 'my':
                                self.assertEqual(phases, ['run'])
                                self.assertEqual(paths['task:byte_io'], str(host))
                                self.assertEqual('task:compiler' in paths, arm == 'main')
                                self.assertEqual('task:navigate' in paths, arm == 'main')
                                self.assertEqual('practice:compiler' in paths, arm == 'main')
                            else:
                                self.assertEqual(paths, {})

    def test_rehashed_wrong_conditions_and_commands_reject(self):
        item = config.freeze('python', 'planner', 'main')
        config.validate(item)
        def change_command(value):
            value['task_adapter']['commands'][0]['argv'][-1] = 'inspector.py'
            adapter = value['task_adapter']
            adapter['sha256'] = digest({key: data for key, data in adapter.items() if key != 'sha256'})
        mutations = [
            lambda value: value.update(language='my'),
            lambda value: value.update(application='eda'),
            lambda value: value.update(arm='unrecognized'),
            lambda value: value.update(tools={'extra': '/usr/bin/python3'}),
            lambda value: value.update(unexpected=True),
            lambda value: value['practice_adapter']['limits'].update(wall_seconds=600),
            change_command,
        ]
        for mutate in mutations:
            changed = copy.deepcopy(item)
            mutate(changed)
            changed['sha256'] = digest({key: data for key, data in changed.items() if key != 'sha256'})
            with self.subTest(mutation=mutate), self.assertRaises(ValueError):
                config.validate(changed)

    def test_workflow_directory_is_bound_only_in_version_three_my_main(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            host = root / 'host'
            host.write_text('tool')
            workflow = root / 'workflow'
            workflow.mkdir()
            (workflow / 'project.py').write_text('pass')
            item = config.freeze('my', 'planner', 'main', byte_io=host, compiler=host, navigate=host, workflow=workflow)
            config.validate(item)
            self.assertEqual('application-trial-configuration-v3', item['version'])
            self.assertEqual(str(workflow), item['tools']['workflow'])
            (workflow / 'project.py').write_text('changed')
            with self.assertRaises(ValueError):
                config.verify(item)
        with self.assertRaisesRegex(ValueError, 'workflow directory'):
            config.freeze('python', 'planner', 'main', workflow='/usr/bin')

    def test_missing_toolchain_or_gate_rejects(self):
        with self.assertRaisesRegex(ValueError, 'complete Zig'):
            config.freeze('zig', 'planner', 'main')
        with self.assertRaisesRegex(ValueError, 'bytecode host'):
            config.freeze('my', 'planner', 'main')
        with self.assertRaisesRegex(ValueError, 'invalid trial'):
            config.freeze('python', 'unknown', 'main')
        with self.assertRaisesRegex(ValueError, 'compiler and navigation'):
            config.freeze('my', 'planner', 'main', byte_io='/usr/bin/true')


if __name__ == '__main__':
    unittest.main()
