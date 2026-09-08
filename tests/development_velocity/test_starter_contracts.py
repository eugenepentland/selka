"""Cross-check independent repaired starters against generated contract expectations."""
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from experiments.application_comparison.execution import parse_output
from experiments.application_comparison.inputs import decode_case
from experiments.application_comparison.storage import canonical
from experiments.development_velocity.corpus.cases import build

ROOT = Path(__file__).resolve().parents[2]
HERE = ROOT / 'experiments/development_velocity'


class RepairedContracts(unittest.TestCase):
    def test_independently_written_repaired_starters_match_all_contract_groups(self):
        rules = json.loads((HERE / 'starter-mutations.json').read_text())['tasks']
        for task, languages in rules.items():
            for language, rule in languages.items():
                with self.subTest(task=task, language=language), tempfile.TemporaryDirectory() as temporary:
                    work = Path(temporary) / 'work'
                    shutil.copytree(HERE / 'runtime' / language, work)
                    shutil.copytree(HERE / 'starters' / task / language, work, dirs_exist_ok=True)
                    target = work / rule['file']
                    original = target.read_text()
                    self.assertEqual(original.count(rule['seeded']), 1)
                    target.write_text(original.replace(rule['seeded'], rule['correct']))
                    command = ([str(ROOT / 'zig-out/bin/mylang-io'), '--project', str(work)]
                               if language == 'my' else ['/usr/bin/python3', '-B', str(work / 'main.py')])
                    cases = build(task, 'independent-readiness-v1', public=False)
                    cases += build(task, 'ignored-public', public=True)
                    for case in cases:
                        with self.subTest(case=case['name']):
                            request, raw, expected = decode_case(case['case'])
                            result = subprocess.run(command, input=canonical(request) if raw is None else raw,
                                                    capture_output=True, timeout=90)
                            self.assertEqual(result.returncode, 0, result.stderr.decode(errors='replace'))
                            self.assertEqual(parse_output(result.stdout), expected)


if __name__ == '__main__':
    unittest.main()
