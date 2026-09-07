import copy
from pathlib import Path
import tempfile
import unittest
from experiments.application_comparison import environment_receipt, trial_configuration, verified_grading
from experiments.application_comparison.storage import digest


class GraderConfigurationTests(unittest.TestCase):
    def test_frozen_task_tools_form_verifiable_grader_runtime(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            zig = root / 'zig-toolchain'
            zig.mkdir()
            (zig / 'zig').write_text('fixture executable; not executed')
            (zig / 'lib').mkdir()
            host = root / 'host'
            host.write_text('fixture VM; not executed')
            configurations = {language: trial_configuration.freeze(language, 'planner', 'main',
                zig=zig, guardian=host, byte_io=host, compiler=host, navigate=host) for language in ('my', 'python', 'zig')}
            derived = verified_grading.from_configurations(configurations)
            environment = derived['environment']
            self.assertEqual(set(environment['tools']), {'my:byte_io', 'my:compiler', 'my:navigate', 'zig:zig', 'zig:guardian',
                'zig:guardian_runner', 'zig:guardian_policy'})
            self.assertEqual(environment['tools']['zig:zig']['source_path'], str(zig))
            environment_receipt.verify(environment, require_system=True,
                                       required_tools=verified_grading.tools(derived['adapters']))
            # Derivation must not expose aliases that can mutate the cohort.
            derived['adapters']['zig']['commands'].clear()
            self.assertTrue(configurations['zig']['task_adapter']['commands'])
            bad = copy.deepcopy(configurations)
            bad['python']['environment']['cpu_count'] += 1
            receipt = bad['python']['environment']
            receipt['sha256'] = digest({key: value for key, value in receipt.items() if key not in ('sha256', 'capture_seconds')})
            value = bad['python']
            value['sha256'] = digest({key: item for key, item in value.items() if key != 'sha256'})
            with self.assertRaisesRegex(ValueError, 'identical system'):
                verified_grading.from_configurations(bad)
            with self.assertRaisesRegex(ValueError, 'three frozen'):
                verified_grading.from_configurations({'python': configurations['python']})


if __name__ == '__main__':
    unittest.main()
